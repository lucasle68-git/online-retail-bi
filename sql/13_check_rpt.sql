/* =====================================================================
   13_check_rpt.sql  |  Step 7b: Check the reporting views
   ---------------------------------------------------------------------
   Purpose : Prove the views show exactly what the model holds (V1-V6),
             profile customers to choose the wholesale / retail rule (V7-V8),
             then read the segments the views produce (V9-V11).
   Input   : views from 12_rpt_views.sql
   Output  : Result grids only
   Re-run  : Safe to re-run.
   ===================================================================== */
USE RetailDW;
GO

-- V1. Every view returns as many rows as the table behind it. Expect difference = 0 everywhere
SELECT 'vw_sales'    AS view_name, (SELECT COUNT(*) FROM rpt.vw_sales)    AS view_rows, (SELECT COUNT(*) FROM dw.fact_sales)   AS table_rows UNION ALL
SELECT 'vw_date',                  (SELECT COUNT(*) FROM rpt.vw_date),                 (SELECT COUNT(*) FROM dw.dim_date)              UNION ALL
SELECT 'vw_customer',              (SELECT COUNT(*) FROM rpt.vw_customer),             (SELECT COUNT(*) FROM dw.dim_customer)          UNION ALL
SELECT 'vw_product',               (SELECT COUNT(*) FROM rpt.vw_product),              (SELECT COUNT(*) FROM dw.dim_product)           UNION ALL
SELECT 'vw_country',               (SELECT COUNT(*) FROM rpt.vw_country),              (SELECT COUNT(*) FROM dw.dim_country);

-- V2. Money: the view keeps every penny, and gross - cancelled = net
--     Expect net_amount = 19,002,944.278 and both differences = 0
SELECT SUM([Net Amount])                                                  AS net_amount,
       SUM([Net Amount]) - (SELECT SUM(line_amount) FROM dw.fact_sales)   AS diff_vs_fact,
       SUM([Gross Sales Amount]) - SUM([Cancelled Amount]) - SUM([Net Amount]) AS diff_gross_minus_cancelled
FROM rpt.vw_sales;

-- V3. Customer view adds up: known customers + Unknown customer = net product revenue
--     Expect total = 18,927,399.067 (C5 / S7)
SELECT known_customers, unknown_customer, known_customers + unknown_customer AS total
FROM (SELECT (SELECT SUM([Lifetime Net Revenue]) FROM rpt.vw_customer) AS known_customers,
             (SELECT SUM(f.line_amount)
              FROM dw.fact_sales AS f
              JOIN dw.dim_product AS p ON p.product_key = f.product_key
              WHERE p.is_product = 1 AND f.customer_key = -1)       AS unknown_customer) AS x;

-- V4. Waterfall: received, each exclusion, rows in the model. Expect the first row + all exclusions = last row
SELECT * FROM rpt.vw_data_quality ORDER BY [Step Order];

SELECT SUM(CASE WHEN [Step Order] < 10 THEN [Rows] END)
     - SUM(CASE WHEN [Step Order] = 10 THEN [Rows] END) AS waterfall_difference      -- expect 0
FROM rpt.vw_data_quality;

-- V5. Last refresh, as Power BI will show it
SELECT * FROM rpt.vw_pipeline_status;

-- V6. Customer headline numbers (known customers with at least one product order)
SELECT COUNT(*)                                                        AS customers,
       SUM([Is Repeat Customer])                                       AS repeat_customers,
       CAST(100.0 * SUM([Is Repeat Customer]) / COUNT(*) AS DECIMAL(5,1)) AS repeat_rate_pct,
       AVG([Lifetime AOV])                                          AS mean_of_customer_aov
FROM rpt.vw_customer
WHERE [Lifetime Orders] > 0;

-- V7. Profile for the wholesale / retail rule: how customer average order value is spread
SELECT DISTINCT
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY [Lifetime AOV]) OVER () AS p25,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY [Lifetime AOV]) OVER () AS p50_median,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY [Lifetime AOV]) OVER () AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY [Lifetime AOV]) OVER () AS p90,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY [Lifetime AOV]) OVER () AS p99
FROM rpt.vw_customer
WHERE [Lifetime Orders] > 0;

-- V8. Customers and revenue by order-size band: where does the money come from?
SELECT band,
       COUNT(*)                                                         AS customers,
       SUM(revenue)                                                     AS net_product_revenue,
       CAST(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER () AS DECIMAL(5,1)) AS pct_of_revenue
FROM (SELECT [Lifetime Net Revenue] AS revenue,
             CASE WHEN [Lifetime AOV] <  250 THEN '1: under GBP 250'
                  WHEN [Lifetime AOV] <  500 THEN '2: GBP 250-499'
                  WHEN [Lifetime AOV] < 1000 THEN '3: GBP 500-999'
                  WHEN [Lifetime AOV] < 2500 THEN '4: GBP 1,000-2,499'
                  ELSE                               '5: GBP 2,500 and over' END AS band
      FROM rpt.vw_customer
      WHERE [Lifetime Orders] > 0) AS x
GROUP BY band
ORDER BY band;

-- V9. Wholesale vs retail (rule: lifetime AOV >= GBP 500). How different are the two groups?
SELECT [Segment],
       COUNT(*)                                                                AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1))          AS pct_of_customers,
       SUM([Lifetime Net Revenue])                                             AS net_product_revenue,
       CAST(100.0 * SUM([Lifetime Net Revenue]) / SUM(SUM([Lifetime Net Revenue])) OVER () AS DECIMAL(5,1)) AS pct_of_revenue,
       CAST(AVG([Lifetime AOV]) AS DECIMAL(10,2))                              AS avg_aov,
       CAST(AVG(CAST([Lifetime Orders] AS DECIMAL(10,2))) AS DECIMAL(10,1))    AS avg_orders,
       CAST(100.0 * AVG(CAST([Is Repeat Customer] AS DECIMAL(5,2))) AS DECIMAL(5,1)) AS repeat_rate_pct
FROM rpt.vw_customer
WHERE [Lifetime Orders] > 0
GROUP BY [Segment];

-- V10. RFM segments, and the win-back list (lapsed, frequent, high-value customers)
SELECT [RFM Segment],
       COUNT(*)                     AS customers,
       SUM([Lifetime Net Revenue])  AS net_product_revenue,
       SUM([Is Win-back Target])    AS win_back_targets
FROM rpt.vw_customer
WHERE [RFM Segment] IS NOT NULL
GROUP BY [RFM Segment]
ORDER BY net_product_revenue DESC;

SELECT TOP (10) [Customer ID], [Segment], [RFM Score], [Lifetime Orders],
       [Lifetime Net Revenue], [Last Purchase], [Days Since Last Purchase]
FROM rpt.vw_customer
WHERE [Is Win-back Target] = 1
ORDER BY [Lifetime Net Revenue] DESC;

-- V11. ABC classes. Expect class A to hold about 80% of product revenue with a minority of products
SELECT p.[ABC Class],
       COUNT(DISTINCT p.product_key)                                                AS products,
       SUM(s.[Net Amount])                                                          AS net_revenue,
       CAST(100.0 * SUM(s.[Net Amount]) / SUM(SUM(s.[Net Amount])) OVER () AS DECIMAL(5,1)) AS pct_of_revenue
FROM rpt.vw_product AS p
LEFT JOIN rpt.vw_sales AS s ON s.product_key = p.product_key
GROUP BY p.[ABC Class]
ORDER BY p.[ABC Class];
