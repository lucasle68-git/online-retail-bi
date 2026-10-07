/* =====================================================================
   10_usp_run_all.sql  |  Step 6b: The one-command pipeline
   ---------------------------------------------------------------------
   Purpose : Run the whole pipeline in order, test the layers against each
             other, and write every run to etl.run_log.
               step 1  stg.usp_load_staging      CSV files    -> staging
               step 2  clean.usp_load_sales_line staging      -> clean + dq.issue_log
               step 3  dw.usp_load_star          clean        -> star schema
               step 4  end-to-end tests          staging = clean + excluded; fact = clean (rows and GBP)
   Run     : EXEC etl.usp_run_all;
             EXEC etl.usp_run_all @simulate_failure = 1;   -- test the failure path
   Safety  : Each step is its own transaction. If a step fails, it rolls back,
             the later steps do not run, and the log records which step failed.
   ===================================================================== */
USE RetailDW;
GO

CREATE OR ALTER PROCEDURE etl.usp_run_all
    @simulate_failure BIT = 0          -- 1 = stop on purpose before step 3, to test the failure path
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @run_id INT,
            @step VARCHAR(30),
            @staging INT, @clean INT, @excluded INT, @fact INT,
            @clean_gbp DECIMAL(18,3), @fact_gbp DECIMAL(18,3);

    /* 0a. Close any earlier run still marked 'running'. TRY/CATCH cannot catch a run that was
           cancelled or disconnected, so such a run never reaches its UPDATE and stays 'running' */
    UPDATE etl.run_log
    SET run_status    = 'abandoned',
        error_message = N'Run never finished (cancelled or disconnected). Closed by the next run.'
    WHERE run_status = 'running';

    /* 0b. Open a diary entry before anything else, so even a crash leaves a trace */
    INSERT INTO etl.run_log (started_at, run_status) VALUES (SYSDATETIME(), 'running');
    SET @run_id = SCOPE_IDENTITY();   -- the run_id SQL Server just generated

    BEGIN TRY
        SET @step = '1 staging';
        EXEC stg.usp_load_staging;

        SET @step = '2 clean';
        EXEC clean.usp_load_sales_line;

        SET @step = '3 star schema';
        IF @simulate_failure = 1
            THROW 50099, N'Simulated failure, to test the failure path.', 1;
        EXEC dw.usp_load_star;

        /* 4. End-to-end tests between the layers */
        SET @step = '4 tests';
        SELECT @staging   = COUNT(*) FROM stg.online_retail_raw;
        SELECT @clean     = COUNT(*), @clean_gbp = SUM(line_amount) FROM clean.sales_line;
        SELECT @excluded  = COUNT(*) FROM dq.issue_log WHERE issue_action = 'excluded';
        SELECT @fact      = COUNT(*), @fact_gbp  = SUM(line_amount) FROM dw.fact_sales;

        IF @staging <> @clean + @excluded
            THROW 50010, N'Test failed: staging rows <> clean rows + excluded rows.', 1;
        IF @fact <> @clean OR @fact_gbp <> @clean_gbp
            THROW 50011, N'Test failed: fact does not match clean (rows or GBP).', 1;

        /* 5. Close the diary entry: success */
        UPDATE etl.run_log
        SET finished_at   = SYSDATETIME(),
            run_status    = 'succeeded',
            staging_rows  = @staging,
            clean_rows    = @clean,
            excluded_rows = @excluded,
            fact_rows     = @fact,
            fact_gbp      = @fact_gbp
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        /* Close the diary entry: failure, with the step and the error text */
        UPDATE etl.run_log
        SET finished_at   = SYSDATETIME(),
            run_status    = 'failed',
            failed_step   = @step,
            error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;

        THROW;   -- still show the error to whoever ran the pipeline
    END CATCH;

    -- Final summary: this run's diary entry
    SELECT * FROM etl.run_log WHERE run_id = @run_id;
END;
GO
