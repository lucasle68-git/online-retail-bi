/* =====================================================================
   05_check_clean.sql  |  Step 4c: Run the cleansing and check the results
   ---------------------------------------------------------------------
   Purpose : Run clean.usp_load_sales_line, then verify every number against
             the expectations in docs/data_quality.md.
   Input   : stg.online_retail_raw, objects from 03 and 04
   Output  : Result grids only (C1-C10)
   Re-run  : Safe to re-run.
   ===================================================================== */
USE RetailDW;
GO

-- C1. Run the cleansing. Expect one row: difference = 0
EXEC clean.usp_load_sales_line;

-- C2. Rows per rule. Expected: R0 0 | R1 22,523 | R2 11,812 | R3 6 | R4 about 3,400 | R5 up to 17 | R9 1
SELECT r.rule_id, r.rule_name, r.dq_dimension, r.rule_action,
       COUNT(l.issue_id) AS rows_logged
FROM dq.quality_rule AS r
LEFT JOIN dq.issue_log AS l ON l.rule_id = r.rule_id
GROUP BY r.rule_id, r.rule_name, r.dq_dimension, r.rule_action
ORDER BY LEN(r.rule_id), r.rule_id;

-- C3. Was R1 safe? Every file-2 row removed by R1 must have an identical twin in file 1. Expect 0
SELECT COUNT(*) AS r1_rows_without_twin_in_file_1
FROM dq.issue_log AS l
JOIN stg.online_retail_raw AS s2 ON s2.stg_row_id = l.stg_row_id
WHERE l.rule_id = 'R1'
  AND NOT EXISTS (
      SELECT 1 FROM stg.online_retail_raw AS s1
      WHERE s1.source_file = 'online_retail_2009_2010.csv'
        AND s1.Invoice = s2.Invoice AND s1.StockCode = s2.StockCode
        AND s1.Quantity = s2.Quantity AND s1.InvoiceDate = s2.InvoiceDate
        AND s1.Price = s2.Price
        AND ISNULL(s1.CustomerID, '') = ISNULL(s2.CustomerID, ''));

-- C4. Flags kept in the clean table (R6, R7, R8, R9)
SELECT COUNT(*)                                                   AS clean_rows,
       SUM(CASE WHEN is_cancellation = 1 THEN 1 ELSE 0 END)       AS r7_cancellations,
       SUM(CASE WHEN is_product = 0 THEN 1 ELSE 0 END)            AS r6_non_product,
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END)       AS r8_missing_customer,
       SUM(CASE WHEN dq_flag = 'R9' THEN 1 ELSE 0 END)            AS r9_flagged
FROM clean.sales_line;

-- C5. Non-product lines and revenue by category
SELECT product_category,
       COUNT(*)         AS lines,
       SUM(line_amount) AS revenue_gbp
FROM clean.sales_line
GROUP BY product_category
ORDER BY revenue_gbp DESC;

-- C6. Headline: share of net revenue on lines with no customer ID (after cleaning)
SELECT CASE WHEN customer_id IS NULL THEN 'missing customer' ELSE 'known customer' END AS customer_group,
       COUNT(*)         AS lines,
       SUM(line_amount) AS net_revenue_gbp,
       CAST(100.0 * SUM(line_amount) / SUM(SUM(line_amount)) OVER () AS DECIMAL(5,1)) AS pct_of_revenue
FROM clean.sales_line
GROUP BY CASE WHEN customer_id IS NULL THEN 'missing customer' ELSE 'known customer' END;

-- C7. R10 precision check: prices with more than 3 decimals would be rounded. Expect 0
SELECT COUNT(*) AS prices_with_more_than_3_decimals
FROM stg.online_retail_raw
WHERE TRY_CAST(Price AS DECIMAL(18,6)) <> TRY_CAST(Price AS DECIMAL(12,3));

/* ---------------------------------------------------------------------
   Rule tests on the OUTPUT: each rule must hold in clean.sales_line.
   Every number below must be 0.
   --------------------------------------------------------------------- */

-- C8. Nothing that should have been excluded is left in the clean table. Expect all 0
SELECT
    SUM(CASE WHEN invoice_no LIKE 'A%' THEN 1 ELSE 0 END)                         AS r3_bad_debt_left,
    SUM(CASE WHEN quantity <= 0 AND invoice_no NOT LIKE 'C%' THEN 1 ELSE 0 END)   AS r4_write_offs_left,
    SUM(CASE WHEN stock_code IN ('TEST001', 'TEST002') THEN 1 ELSE 0 END)         AS r5_tests_left,
    SUM(CASE WHEN source_file = 'online_retail_2010_2011.csv'
              AND invoice_ts >= '2010-12-01' AND invoice_ts < '2010-12-10'
             THEN 1 ELSE 0 END)                                                   AS r1_overlap_left
FROM clean.sales_line;

-- C9. No exact duplicates remain in the clean table (R2). Expect 0
SELECT COUNT(*) AS duplicate_groups_left
FROM (
    SELECT 1 AS x
    FROM clean.sales_line AS c
    JOIN stg.online_retail_raw AS s ON s.stg_row_id = c.stg_row_id
    GROUP BY s.Invoice, s.StockCode, s.Description, s.Quantity, s.InvoiceDate, s.Price, s.CustomerID, s.Country
    HAVING COUNT(*) > 1
) AS d;

-- C10. Every staging row lands in exactly one place: clean OR excluded, never both, never neither. Expect 0 and 0
SELECT
    SUM(CASE WHEN c.stg_row_id IS NULL AND l.stg_row_id IS NULL     THEN 1 ELSE 0 END) AS rows_in_neither,
    SUM(CASE WHEN c.stg_row_id IS NOT NULL AND l.stg_row_id IS NOT NULL THEN 1 ELSE 0 END) AS rows_in_both
FROM stg.online_retail_raw AS s
LEFT JOIN clean.sales_line AS c ON c.stg_row_id = s.stg_row_id
LEFT JOIN dq.issue_log     AS l ON l.stg_row_id = s.stg_row_id AND l.issue_action = 'excluded';
