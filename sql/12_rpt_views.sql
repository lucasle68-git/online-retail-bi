/* =====================================================================
   12_rpt_views.sql  |  Step 7a: Reporting views (the semantic layer)
   ---------------------------------------------------------------------
   Purpose : The ONLY objects Power BI reads. Business-friendly column names,
             metric logic defined once, and a stable contract: tables behind
             the views can change without breaking the dashboard.
             - rpt.vw_sales            : fact, one row per sales line (+ gross / cancelled split)
             - rpt.vw_date             : calendar
             - rpt.vw_customer         : customer + lifetime profile, Segment, RFM, win-back flag
             - rpt.vw_product          : product + ABC class
             - rpt.vw_country          : country + market
             - rpt.vw_data_quality     : row waterfall, staging -> exclusions -> fact
             - rpt.vw_pipeline_status  : last successful refresh
             - role rpt_reader         : may read rpt and nothing else
   Input   : dw.*, dq.*, stg.online_retail_raw, etl.run_log
   Output  : views in schema rpt (views store no data; they always show the latest load)
   Re-run  : Safe to re-run (CREATE OR ALTER).
   Metrics : docs/metric_definitions.md
   ===================================================================== */
USE RetailDW;
GO

IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');
GO

/* ---------- 1. Sales: one row per sales line ---------- */
CREATE OR ALTER VIEW rpt.vw_sales
AS
SELECT f.sales_line_id    AS [Sales Line ID],
       f.invoice_no       AS [Invoice No],
       f.date_key,                                   -- keys keep technical names; hidden in Power BI
       f.customer_key,
       f.product_key,
       f.country_key,
       f.invoice_ts       AS [Invoice Time],
       f.quantity         AS [Quantity],
       f.unit_price       AS [Unit Price],
       f.line_amount      AS [Net Amount],          -- sales minus cancellations
       CASE WHEN f.is_cancellation = 0 THEN f.line_amount ELSE 0 END   AS [Gross Sales Amount],
       CASE WHEN f.is_cancellation = 1 THEN -f.line_amount ELSE 0 END  AS [Cancelled Amount],  -- shown as a positive number
       f.is_cancellation  AS [Is Cancellation]
FROM dw.fact_sales AS f;
GO

/* ---------- 2. Date ---------- */
CREATE OR ALTER VIEW rpt.vw_date
AS
SELECT date_key,
       full_date      AS [Date],
       calendar_year  AS [Year],
       quarter_num    AS [Quarter Number],
       quarter_label  AS [Quarter],
       month_num      AS [Month Number],        -- sort [Month] by this column in Power BI
       month_name     AS [Month],
       month_short    AS [Month Short],
       year_month     AS [Year Month],
       month_start    AS [Month Start],
       day_of_month   AS [Day],
       weekday_num    AS [Weekday Number],      -- sort [Weekday] by this column in Power BI
       weekday_name   AS [Weekday],
       is_weekend     AS [Is Weekend],
       iso_week       AS [ISO Week]
FROM dw.dim_date;
GO

/* ---------- 3. Product + ABC class ----------
   ABC (Pareto) ranks products by lifetime net revenue: the products that make the
   first 80% of revenue are A, the next 15% are B, the rest are C. A grouping label,
   not a number to sum: revenue itself stays a measure. */
CREATE OR ALTER VIEW rpt.vw_product
AS
WITH product_revenue AS (
    SELECT f.product_key, SUM(f.line_amount) AS net_revenue
    FROM dw.fact_sales  AS f
    JOIN dw.dim_product AS p ON p.product_key = f.product_key
    WHERE p.is_product = 1
    GROUP BY f.product_key
    HAVING SUM(f.line_amount) > 0
),
ranked AS (
    SELECT product_key,
           -- share of revenue held by the products ranked above this one
           (SUM(net_revenue) OVER (ORDER BY net_revenue DESC, product_key ROWS UNBOUNDED PRECEDING) - net_revenue)
           / SUM(net_revenue) OVER () AS share_before
    FROM product_revenue
)
SELECT p.product_key,
       p.stock_code                                   AS [Stock Code],
       COALESCE(p.description, N'(no description)')   AS [Product],
       p.product_category                             AS [Category],
       p.is_product                                   AS [Is Product],
       CASE WHEN p.is_product = 0       THEN N'Not a product'
            WHEN r.product_key IS NULL  THEN N'C'          -- zero or negative net revenue
            WHEN r.share_before < 0.80  THEN N'A'
            WHEN r.share_before < 0.95  THEN N'B'
            ELSE N'C' END                             AS [ABC Class]
FROM dw.dim_product AS p
LEFT JOIN ranked    AS r ON r.product_key = p.product_key;
GO

/* ---------- 4. Country ---------- */
CREATE OR ALTER VIEW rpt.vw_country
AS
SELECT country_key,
       country_name  AS [Country],
       market        AS [Market]
FROM dw.dim_country;
GO

/* ---------- 5. Customer + segments (product lines only, see metric_definitions.md) ----------
   Lifetime columns cover the whole data period and do NOT follow report filters:
   they exist to put customers into groups. Revenue by period is a Power BI measure.
   Recency is measured from the last date in the data (snapshot), not from today.
   Segment rule (threshold chosen from check V7-V8 in 13_check_rpt.sql):
     lifetime average order value >= GBP 500 -> Wholesale, otherwise Retail. */
CREATE OR ALTER VIEW rpt.vw_customer
AS
WITH settings AS (
    SELECT CAST(500 AS DECIMAL(14,2)) AS wholesale_aov_threshold
),
snapshot AS (
    SELECT CAST(MAX(invoice_ts) AS DATE) AS snapshot_date
    FROM dw.fact_sales
),
activity AS (
    SELECT f.customer_key,
           COUNT(DISTINCT CASE WHEN f.is_cancellation = 0 THEN f.invoice_no END)   AS orders,
           SUM(CASE WHEN f.is_cancellation = 0 THEN f.line_amount ELSE 0 END)      AS gross_sales,
           SUM(f.line_amount)                                                      AS net_revenue,
           CAST(MAX(CASE WHEN f.is_cancellation = 0 THEN f.invoice_ts END) AS DATE) AS last_purchase
    FROM dw.fact_sales  AS f
    JOIN dw.dim_product AS p ON p.product_key = f.product_key
    WHERE p.is_product = 1
      AND f.customer_key <> -1
    GROUP BY f.customer_key
),
rfm AS (   -- scores 1-5, 5 = best; only customers with at least one product order
    SELECT a.customer_key,
           NTILE(5) OVER (ORDER BY DATEDIFF(DAY, a.last_purchase, s.snapshot_date) DESC, a.customer_key) AS r_score,
           CASE WHEN a.orders >= 10 THEN 5
                WHEN a.orders >= 5  THEN 4
                WHEN a.orders >= 3  THEN 3
                WHEN a.orders =  2  THEN 2
                ELSE 1 END                                                                            AS f_score,
           NTILE(5) OVER (ORDER BY a.net_revenue, a.customer_key)                                     AS m_score
    FROM activity AS a
    CROSS JOIN snapshot AS s
    WHERE a.orders > 0
)
SELECT c.customer_key,
       c.customer_id                                              AS [Customer ID],
       c.customer_label                                           AS [Customer],
       c.is_known_customer                                        AS [Is Known Customer],
       c.first_purchase_date                                      AS [First Purchase],
       c.cohort_month                                             AS [Cohort Month],
       a.last_purchase                                            AS [Last Purchase],
       DATEDIFF(DAY, a.last_purchase, s.snapshot_date)            AS [Days Since Last Purchase],
       CASE WHEN c.customer_key = -1 THEN NULL
            ELSE COALESCE(a.orders, 0) END                        AS [Lifetime Orders],
       a.net_revenue                                              AS [Lifetime Net Revenue],
       CAST(a.gross_sales / NULLIF(a.orders, 0) AS DECIMAL(14,2)) AS [Lifetime AOV],
       CASE WHEN c.customer_key = -1 THEN NULL
            WHEN a.orders >= 2      THEN 1
            ELSE 0 END                                            AS [Is Repeat Customer],
       CASE WHEN c.customer_key = -1                 THEN N'Unknown'
            WHEN COALESCE(a.orders, 0) = 0           THEN N'No product orders'
            WHEN a.gross_sales / a.orders >= t.wholesale_aov_threshold THEN N'Wholesale'
            ELSE N'Retail' END                                    AS [Segment],
       r.r_score                                                  AS [R Score],
       r.f_score                                                  AS [F Score],
       r.m_score                                                  AS [M Score],
       CASE WHEN r.r_score IS NULL THEN NULL
            ELSE CONCAT(r.r_score, r.f_score, r.m_score) END      AS [RFM Score],
       CASE WHEN r.r_score IS NULL                   THEN NULL
            WHEN r.r_score >= 4 AND r.f_score >= 4   THEN N'Champions'
            WHEN r.r_score <= 2 AND r.f_score >= 3   THEN N'At risk'
            WHEN r.f_score >= 3                      THEN N'Loyal'
            WHEN r.r_score >= 4                      THEN N'New or promising'
            WHEN r.r_score <= 2                      THEN N'Hibernating'
            ELSE N'Needs attention' END                           AS [RFM Segment],
       CASE WHEN r.r_score IS NULL THEN NULL
            WHEN r.r_score <= 2 AND r.f_score >= 3 AND r.m_score >= 4 THEN 1
            ELSE 0 END                                            AS [Is Win-back Target]
FROM dw.dim_customer AS c
LEFT JOIN activity   AS a ON a.customer_key = c.customer_key
LEFT JOIN rfm        AS r ON r.customer_key = c.customer_key
CROSS JOIN snapshot  AS s
CROSS JOIN settings  AS t;
GO

/* ---------- 6. Data-quality waterfall: every row accounted for ----------
   Exclusions are negative, so Power BI can draw them as steps down. */
CREATE OR ALTER VIEW rpt.vw_data_quality
AS
SELECT 0                     AS [Step Order],
       N'Rows received'      AS [Step],
       CAST(NULL AS VARCHAR(5)) AS [Rule],
       COUNT(*)              AS [Rows]
FROM stg.online_retail_raw
UNION ALL
SELECT 1 + CAST(STUFF(r.rule_id, 1, 1, '') AS INT),   -- R0 -> 1, R1 -> 2 ... keeps the rule order
       r.rule_name,
       r.rule_id,
       -COUNT(l.issue_id)
FROM dq.quality_rule AS r
LEFT JOIN dq.issue_log AS l ON l.rule_id = r.rule_id AND l.issue_action = 'excluded'
WHERE r.rule_action = 'exclude'
GROUP BY r.rule_id, r.rule_name
UNION ALL
SELECT 10,
       N'Rows in the sales model',
       NULL,
       COUNT(*)
FROM dw.fact_sales;
GO

/* ---------- 7. Pipeline status: when the data was last refreshed ---------- */
CREATE OR ALTER VIEW rpt.vw_pipeline_status
AS
SELECT TOP (1)
       run_id        AS [Run ID],
       finished_at   AS [Last Refreshed],
       duration_sec  AS [Duration Seconds],
       staging_rows  AS [Rows Received],
       excluded_rows AS [Rows Excluded],
       fact_rows     AS [Rows In Model],
       fact_gbp      AS [Net Amount In Model]
FROM etl.run_log
WHERE run_status = 'succeeded'
ORDER BY run_id DESC;
GO

/* ---------- 8. Read-only role: whoever is in it can read rpt and nothing else ---------- */
IF DATABASE_PRINCIPAL_ID('rpt_reader') IS NULL CREATE ROLE rpt_reader;
GRANT SELECT ON SCHEMA::rpt TO rpt_reader;
GO

-- Check: 7 views in schema rpt, with their column counts
SELECT v.name AS view_name, COUNT(c.column_id) AS columns
FROM sys.views AS v
JOIN sys.columns AS c ON c.object_id = v.object_id
WHERE v.schema_id = SCHEMA_ID('rpt')
GROUP BY v.name
ORDER BY v.name;
