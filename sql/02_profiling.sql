/* =====================================================================
   02_profiling.sql  |  Step 3: Data profiling
   ---------------------------------------------------------------------
   Purpose : Measure every data-quality issue in staging BEFORE writing
             cleaning rules. Read-only: changes nothing.
   Input   : RetailDW.stg.online_retail_raw  (from 01_staging_load.sql)
   Output  : Result grids only. Findings are recorded in docs/data_quality.md
   Re-run  : Safe to re-run at any time.
   ===================================================================== */
USE RetailDW;
GO

/* ---------------------------------------------------------------------
   Part A. First overview
   --------------------------------------------------------------------- */

-- A1. Date range per file: where does file 1 end and file 2 begin?
SELECT source_file,
       MIN(TRY_CAST(InvoiceDate AS DATETIME2)) AS first_date,
       MAX(TRY_CAST(InvoiceDate AS DATETIME2)) AS last_date
FROM stg.online_retail_raw
GROUP BY source_file
ORDER BY first_date;

-- A2. One-line data-quality profile
SELECT
    COUNT(*)                                                                    AS total_rows,
    SUM(CASE WHEN NULLIF(CustomerID, '') IS NULL THEN 1 ELSE 0 END)             AS missing_customer,
    SUM(CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END)                          AS cancelled_lines,
    SUM(CASE WHEN TRY_CAST(Invoice AS INT) IS NULL
              AND Invoice NOT LIKE 'C%' THEN 1 ELSE 0 END)                      AS other_odd_invoices,
    SUM(CASE WHEN TRY_CAST(Quantity AS INT) <= 0 THEN 1 ELSE 0 END)             AS non_positive_qty,
    SUM(CASE WHEN TRY_CAST(Price AS DECIMAL(12,3)) <= 0 THEN 1 ELSE 0 END)      AS zero_or_negative_price,
    SUM(CASE WHEN TRY_CAST(InvoiceDate AS DATETIME2) IS NULL THEN 1 ELSE 0 END) AS unreadable_dates
FROM stg.online_retail_raw;

-- A3. Exact duplicate rows (all 8 business columns identical)
SELECT SUM(cnt - 1) AS duplicate_rows
FROM (
    SELECT COUNT(*) AS cnt
    FROM stg.online_retail_raw
    GROUP BY Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country
    HAVING COUNT(*) > 1
) d;

/* ---------------------------------------------------------------------
   Part B. Drill-down: explain each number from Part A
   --------------------------------------------------------------------- */

-- B1. The overlap: how many rows fall in 1-9 Dec 2010, in each file?
SELECT source_file, COUNT(*) AS rows_1_to_9_dec_2010
FROM stg.online_retail_raw
WHERE TRY_CAST(InvoiceDate AS DATETIME2) >= '2010-12-01'
  AND TRY_CAST(InvoiceDate AS DATETIME2) <  '2010-12-10'
GROUP BY source_file;

-- B2. Split the duplicates: repeated across the two files vs within one file
WITH dup AS (
    SELECT COUNT(*)                    AS n_rows,
           COUNT(DISTINCT source_file) AS n_files
    FROM stg.online_retail_raw
    GROUP BY Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country
    HAVING COUNT(*) > 1
)
SELECT CASE WHEN n_files = 2 THEN 'in both files (overlap)' ELSE 'repeated within one file' END AS duplicate_type,
       COUNT(*)        AS duplicate_groups,
       SUM(n_rows - 1) AS extra_rows
FROM dup
GROUP BY CASE WHEN n_files = 2 THEN 'in both files (overlap)' ELSE 'repeated within one file' END;

-- B3. The "other odd invoices": what are they?
SELECT Invoice, StockCode, Description, Quantity, Price, CustomerID, InvoiceDate
FROM stg.online_retail_raw
WHERE TRY_CAST(Invoice AS INT) IS NULL
  AND Invoice NOT LIKE 'C%';

-- B4. Stock codes that are not ordinary products (ordinary = start with 5 digits)
SELECT StockCode,
       MIN(Description) AS example_description,
       COUNT(*)         AS lines
FROM stg.online_retail_raw
WHERE StockCode NOT LIKE '[0-9][0-9][0-9][0-9][0-9]%'
GROUP BY StockCode
ORDER BY lines DESC;

-- B5. Zero or negative quantity that is NOT a cancellation: what is it?
SELECT CASE WHEN NULLIF(CustomerID, '') IS NULL THEN 'no customer' ELSE 'has customer' END AS customer,
       CASE WHEN TRY_CAST(Price AS DECIMAL(12,3)) = 0 THEN 'price = 0' ELSE 'price > 0' END AS price,
       COUNT(*) AS lines
FROM stg.online_retail_raw
WHERE TRY_CAST(Quantity AS INT) <= 0
  AND Invoice NOT LIKE 'C%'
GROUP BY CASE WHEN NULLIF(CustomerID, '') IS NULL THEN 'no customer' ELSE 'has customer' END,
         CASE WHEN TRY_CAST(Price AS DECIMAL(12,3)) = 0 THEN 'price = 0' ELSE 'price > 0' END;

SELECT TOP 20 Invoice, StockCode, Description, Quantity, Price, CustomerID
FROM stg.online_retail_raw
WHERE TRY_CAST(Quantity AS INT) <= 0
  AND Invoice NOT LIKE 'C%';

-- B6. Revenue at stake: how much revenue sits on lines with no customer ID?
--     (Preliminary: still includes duplicates and the overlap. Final figure comes after cleaning.)
SELECT CASE WHEN NULLIF(CustomerID, '') IS NULL THEN 'missing customer' ELSE 'known customer' END AS customer_group,
       COUNT(*) AS lines,
       SUM(TRY_CAST(Quantity AS INT) * TRY_CAST(Price AS DECIMAL(12,3))) AS revenue_gbp
FROM stg.online_retail_raw
GROUP BY CASE WHEN NULLIF(CustomerID, '') IS NULL THEN 'missing customer' ELSE 'known customer' END;

-- B7. Reconciliation check: 22,950 non-positive quantities - 3,457 non-cancellation ones = 19,493,
--     but there are 19,494 cancellation lines. So one cancellation line must have a positive quantity.
SELECT *
FROM stg.online_retail_raw
WHERE Invoice LIKE 'C%'
  AND TRY_CAST(Quantity AS INT) > 0;
