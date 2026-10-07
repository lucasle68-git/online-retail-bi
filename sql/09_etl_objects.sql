/* =====================================================================
   09_etl_objects.sql  |  Step 6a: Pipeline objects
   ---------------------------------------------------------------------
   Purpose : Prepare the pieces the one-command pipeline needs.
             - etl.run_log           : one row per pipeline run (when, how long, result, row counts)
             - stg.usp_load_staging  : step 2 (01_staging_load.sql) turned into a re-runnable procedure
   Input   : C:\data\online_retail_2009_2010.csv, C:\data\online_retail_2010_2011.csv
   Output  : etl.run_log (empty), procedure stg.usp_load_staging
   Re-run  : Safe to re-run. WARNING: dropping etl.run_log deletes the run history.
   Needs   : stg.online_retail_raw and stg.v_online_retail_load from 01_staging_load.sql
   ===================================================================== */
USE RetailDW;
GO

IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');
GO

DROP TABLE IF EXISTS etl.run_log;
GO

/* ---------- 1. Run log: the pipeline's diary ---------- */
CREATE TABLE etl.run_log (
    run_id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_run_log PRIMARY KEY,
    started_at     DATETIME2(0)   NOT NULL,
    finished_at    DATETIME2(0)   NULL,
    duration_sec   AS DATEDIFF(SECOND, started_at, finished_at),   -- computed: how long the run took
    run_status     VARCHAR(10)    NOT NULL,   -- running | succeeded | failed | abandoned
    failed_step    VARCHAR(30)    NULL,       -- which step stopped the run
    error_message  NVARCHAR(4000) NULL,
    staging_rows   INT            NULL,
    clean_rows     INT            NULL,
    excluded_rows  INT            NULL,
    fact_rows      INT            NULL,
    fact_gbp       DECIMAL(18,3)  NULL
);
GO

/* ---------- 2. Step 2 as a procedure: reload staging from the two CSV files ---------- */
CREATE OR ALTER PROCEDURE stg.usp_load_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- TRUNCATE empties the table AND restarts stg_row_id at 1,
        -- so every run gives each source row the same ID (stable lineage)
        TRUNCATE TABLE stg.online_retail_raw;

        BULK INSERT stg.v_online_retail_load
        FROM 'C:\data\online_retail_2009_2010.csv'
        WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', TABLOCK);

        UPDATE stg.online_retail_raw
        SET source_file = 'online_retail_2009_2010.csv', loaded_at = SYSDATETIME()
        WHERE source_file IS NULL;

        BULK INSERT stg.v_online_retail_load
        FROM 'C:\data\online_retail_2010_2011.csv'
        WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', TABLOCK);

        UPDATE stg.online_retail_raw
        SET source_file = 'online_retail_2010_2011.csv', loaded_at = SYSDATETIME()
        WHERE source_file IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- a failed load leaves the previous staging data in place
        THROW;
    END CATCH;

    -- Summary: rows per file (expect 525,461 and 541,910)
    SELECT source_file, COUNT(*) AS rows_loaded
    FROM stg.online_retail_raw
    GROUP BY source_file
    ORDER BY source_file;
END;
GO

-- Check: the log table and the procedure exist
SELECT OBJECT_ID('etl.run_log')            AS run_log_exists,
       OBJECT_ID('stg.usp_load_staging')   AS staging_procedure_exists;
