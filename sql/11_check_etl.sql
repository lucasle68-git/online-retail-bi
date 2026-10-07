/* =====================================================================
   11_check_etl.sql  |  Step 6c: Test the pipeline
   ---------------------------------------------------------------------
   Purpose : Prove three things about etl.usp_run_all:
             E1-E2  one command rebuilds everything from the CSV files
             E3     running it again gives exactly the same numbers (idempotent)
             E4-E5  a failure stops the run, is logged, and leaves the dashboard data intact
   Run     : one batch at a time (select a block, then Execute). E4 shows a red error ON PURPOSE.
   ===================================================================== */
USE RetailDW;
GO

-- E1. Full run from the CSV files. Expect the last grid: run_status = succeeded
--     (the grids before it are the summaries of each step)
EXEC etl.usp_run_all;
GO

-- E2. Run it a second time
EXEC etl.usp_run_all;
GO

-- E3. Idempotency: the last two successful runs must have identical numbers. Expect same_numbers = 1
SELECT run_id, started_at, duration_sec, run_status,
       staging_rows, clean_rows, excluded_rows, fact_rows, fact_gbp
FROM etl.run_log
ORDER BY run_id DESC;

SELECT CASE WHEN COUNT(DISTINCT CONCAT(staging_rows, '|', clean_rows, '|', excluded_rows, '|', fact_rows, '|', fact_gbp)) = 1
            THEN 1 ELSE 0 END AS same_numbers
FROM (SELECT TOP (2) * FROM etl.run_log WHERE run_status = 'succeeded' ORDER BY run_id DESC) AS last_two;
GO

-- E4. Failure test. A red error message is EXPECTED here: "Simulated failure, to test the failure path."
EXEC etl.usp_run_all @simulate_failure = 1;
GO

-- E5. After the failure: the log says what happened, and the star schema still holds the last good load
SELECT TOP (1) run_id, run_status, failed_step, error_message, duration_sec
FROM etl.run_log
ORDER BY run_id DESC;                                  -- expect: failed | 3 star schema

SELECT COUNT(*) AS fact_rows_still_there FROM dw.fact_sales;   -- expect 1,029,620
