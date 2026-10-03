/* =====================================================================
   04_usp_load_sales_line.sql  |  Step 4b: Cleansing procedure
   ---------------------------------------------------------------------
   Purpose : Apply rules R0-R10 (docs/data_quality.md) to staging and load
             clean.sales_line. Every excluded row is written to dq.issue_log.
   Input   : stg.online_retail_raw, clean.non_product_code
   Output  : clean.sales_line, dq.issue_log (both fully rebuilt on each run)
   Re-run  : Safe to re-run (full refresh). Run with: EXEC clean.usp_load_sales_line;
   Safety  : Runs in one transaction. If staging rows <> clean rows + excluded rows,
             the procedure raises an error and rolls everything back.
   ===================================================================== */
USE RetailDW;
GO

CREATE OR ALTER PROCEDURE clean.usp_load_sales_line
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- any error rolls back the whole transaction

    DECLARE @now DATETIME2(0) = SYSDATETIME();

    /* ---- 1. Working copy: convert text to proper types, row by row ----
       COALESCE(TRY_CAST(x AS type), TRY_CAST(TRY_CAST(x AS FLOAT) AS type)) also accepts
       values such as '13085.0' or '1e-05' that a direct cast would reject.
       dup_key is a fingerprint of the 8 raw columns, used to find exact duplicates (R2). */
    DROP TABLE IF EXISTS #work;

    SELECT
        s.stg_row_id,
        s.source_file,
        NULLIF(TRIM(s.Invoice), '')                          AS invoice_no,
        UPPER(NULLIF(TRIM(s.StockCode), ''))                 AS stock_code,
        NULLIF(TRIM(s.Description), '')                      AS description,
        COALESCE(TRY_CAST(s.Quantity AS INT),
                 TRY_CAST(TRY_CAST(s.Quantity AS FLOAT) AS INT))              AS quantity,
        COALESCE(TRY_CAST(s.Price AS DECIMAL(12,3)),
                 TRY_CAST(TRY_CAST(s.Price AS FLOAT) AS DECIMAL(12,3)))       AS unit_price,
        TRY_CAST(s.InvoiceDate AS DATETIME2(0))              AS invoice_ts,
        TRY_CAST(TRY_CAST(NULLIF(TRIM(s.CustomerID), '') AS FLOAT) AS INT)    AS customer_id,
        NULLIF(TRIM(s.Country), '')                          AS country,
        s.Quantity                                           AS quantity_raw,
        s.Price                                              AS price_raw,
        HASHBYTES('SHA2_256', CONCAT(
            ISNULL(s.Invoice, N'~'),     N'|', ISNULL(s.StockCode, N'~'),  N'|',
            ISNULL(s.Description, N'~'), N'|', ISNULL(s.Quantity, N'~'),   N'|',
            ISNULL(s.InvoiceDate, N'~'), N'|', ISNULL(s.Price, N'~'),      N'|',
            ISNULL(s.CustomerID, N'~'),  N'|', ISNULL(s.Country, N'~')))    AS dup_key,
        CAST(NULL AS VARCHAR(5))                             AS rule_id   -- first exclusion rule that applies
    INTO #work
    FROM stg.online_retail_raw AS s;

    /* ---- 2. Exclusion rules, applied in order. A row keeps the FIRST rule that hits it. ---- */

    -- R0 Validity: values that cannot be converted
    UPDATE #work SET rule_id = 'R0'
    WHERE rule_id IS NULL
      AND (invoice_no IS NULL OR stock_code IS NULL OR quantity IS NULL
           OR unit_price IS NULL OR invoice_ts IS NULL);

    -- R1 Uniqueness: file 2 repeats 1-9 Dec 2010, already in file 1
    UPDATE #work SET rule_id = 'R1'
    WHERE rule_id IS NULL
      AND source_file = 'online_retail_2010_2011.csv'
      AND invoice_ts >= '2010-12-01' AND invoice_ts < '2010-12-10';

    -- R2 Uniqueness: exact duplicates among the remaining rows; keep the first copy
    WITH d AS (
        SELECT rule_id,
               ROW_NUMBER() OVER (PARTITION BY dup_key ORDER BY stg_row_id) AS copy_no
        FROM #work
        WHERE rule_id IS NULL
    )
    UPDATE d SET rule_id = 'R2'
    WHERE copy_no > 1;

    -- R3 Scope: bad-debt adjustments (invoices starting with A)
    UPDATE #work SET rule_id = 'R3'
    WHERE rule_id IS NULL AND invoice_no LIKE 'A%';

    -- R4 Scope: stock write-offs (quantity <= 0 but not a cancellation)
    UPDATE #work SET rule_id = 'R4'
    WHERE rule_id IS NULL AND quantity <= 0 AND invoice_no NOT LIKE 'C%';

    -- R5 Scope: test records
    UPDATE #work SET rule_id = 'R5'
    WHERE rule_id IS NULL AND stock_code IN ('TEST001', 'TEST002');

    /* ---- 3. Write the results in one transaction ---- */
    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE clean.sales_line;
        DELETE FROM dq.issue_log;              -- DELETE, not TRUNCATE: the table has a foreign key

        -- Evidence: every excluded row, plus the R9 anomaly that is kept but flagged
        INSERT INTO dq.issue_log
            (rule_id, issue_action, stg_row_id, source_file, invoice_no, stock_code, quantity_raw, price_raw, logged_at)
        SELECT rule_id, 'excluded', stg_row_id, source_file, invoice_no, stock_code, quantity_raw, price_raw, @now
        FROM #work
        WHERE rule_id IS NOT NULL
        UNION ALL
        SELECT 'R9', 'flagged', stg_row_id, source_file, invoice_no, stock_code, quantity_raw, price_raw, @now
        FROM #work
        WHERE rule_id IS NULL AND invoice_no LIKE 'C%' AND quantity > 0;

        -- Clean lines: everything not excluded, with flags R6-R9
        INSERT INTO clean.sales_line
            (stg_row_id, invoice_no, stock_code, description, quantity, unit_price, invoice_ts,
             customer_id, country, is_cancellation, is_product, product_category, dq_flag, source_file)
        SELECT w.stg_row_id, w.invoice_no, w.stock_code, w.description, w.quantity, w.unit_price, w.invoice_ts,
               w.customer_id, w.country,
               CASE WHEN w.invoice_no LIKE 'C%' THEN 1 ELSE 0 END,                   -- R7
               CASE WHEN n.stock_code IS NULL THEN 1 ELSE 0 END,                     -- R6
               COALESCE(n.category, N'Product'),                                     -- R6
               CASE WHEN w.invoice_no LIKE 'C%' AND w.quantity > 0 THEN 'R9' END,    -- R9
               w.source_file
        FROM #work AS w
        LEFT JOIN clean.non_product_code AS n
               ON n.stock_code = w.stock_code
        WHERE w.rule_id IS NULL;

        /* ---- 4. Reconciliation test: no row may disappear ---- */
        DECLARE @stg      BIGINT = (SELECT COUNT(*) FROM stg.online_retail_raw);
        DECLARE @clean    BIGINT = (SELECT COUNT(*) FROM clean.sales_line);
        DECLARE @excluded BIGINT = (SELECT COUNT(*) FROM dq.issue_log WHERE issue_action = 'excluded');

        IF @stg <> @clean + @excluded
        BEGIN
            DECLARE @msg NVARCHAR(300) = CONCAT(
                N'Reconciliation failed: staging ', @stg, N' <> clean ', @clean, N' + excluded ', @excluded);
            THROW 50001, @msg, 1;
        END;

        COMMIT TRANSACTION;

        SELECT @stg                       AS staging_rows,
               @clean                     AS clean_rows,
               @excluded                  AS excluded_rows,
               @stg - (@clean + @excluded) AS difference;   -- must be 0
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- re-raise the original error so the caller sees it
    END CATCH;
END;
GO
