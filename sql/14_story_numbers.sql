/* =====================================================================
   14_story_numbers.sql  |  Step 9 prep: numbers for the report headlines
   ---------------------------------------------------------------------
   Purpose : The figures the dashboard titles need, read from the reporting
             views only (the same source Power BI uses), product lines only.
             N1 like-for-like KPIs: 1 Jan - 9 Dec 2011 vs the same dates in 2010
             N2 revenue by month (monthly chart, peak month)
             N3 UK vs international (Overview and page 2)
             N4 top 10 countries outside the UK
             N5 most cancelled products by value
   Why like-for-like: 2011 data stops on 9 Dec, so a full-year comparison would
             compare 11.3 months with 12 and understate 2011.
   Re-run  : Safe to re-run (read only).
   ===================================================================== */
USE RetailDW;
GO

-- N1. Like-for-like KPIs, 2010 vs 2011 (1 Jan - 9 Dec of each year)
WITH lines AS (
    SELECT CASE WHEN d.[Date] BETWEEN '2010-01-01' AND '2010-12-09' THEN 2010
                WHEN d.[Date] BETWEEN '2011-01-01' AND '2011-12-09' THEN 2011 END AS period,
           s.[Invoice No]          AS invoice_no,
           s.customer_key,
           s.[Net Amount]          AS net_amount,
           s.[Gross Sales Amount]  AS gross,
           s.[Cancelled Amount]    AS cancelled,
           s.[Is Cancellation]     AS is_cancellation
    FROM rpt.vw_sales   AS s
    JOIN rpt.vw_date    AS d ON d.date_key    = s.date_key
    JOIN rpt.vw_product AS p ON p.product_key = s.product_key
    WHERE p.[Is Product] = 1
),
cust AS (   -- one row per known customer who bought in the period
    SELECT period, customer_key, COUNT(DISTINCT invoice_no) AS orders
    FROM lines
    WHERE period IS NOT NULL AND is_cancellation = 0 AND customer_key <> -1
    GROUP BY period, customer_key
)
SELECT l.period,
       SUM(l.net_amount)                                                             AS net_revenue,
       COUNT(DISTINCT CASE WHEN l.is_cancellation = 0 THEN l.invoice_no END)         AS orders,
       CAST(SUM(l.gross) / NULLIF(COUNT(DISTINCT CASE WHEN l.is_cancellation = 0
                                                      THEN l.invoice_no END), 0) AS DECIMAL(10,2)) AS avg_order,
       CAST(100.0 * SUM(l.cancelled) / SUM(l.gross) AS DECIMAL(5,2))                 AS cancelled_pct,
       (SELECT COUNT(*) FROM cust AS c WHERE c.period = l.period)                    AS customers,
       (SELECT CAST(100.0 * SUM(CASE WHEN c.orders >= 2 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1))
        FROM cust AS c WHERE c.period = l.period)                                    AS repeat_pct
FROM lines AS l
WHERE l.period IS NOT NULL
GROUP BY l.period
ORDER BY l.period;

-- N2. Revenue by month (Dec 2011 stops on the 9th)
SELECT d.[Year], d.[Month Number], d.[Month Short],
       SUM(s.[Net Amount]) AS net_revenue
FROM rpt.vw_sales   AS s
JOIN rpt.vw_date    AS d ON d.date_key    = s.date_key
JOIN rpt.vw_product AS p ON p.product_key = s.product_key
WHERE p.[Is Product] = 1
GROUP BY d.[Year], d.[Month Number], d.[Month Short]
ORDER BY d.[Year], d.[Month Number];

-- N3. UK vs international: all data, and 1 Jan - 9 Dec 2011
SELECT k.[Market],
       COUNT(DISTINCT k.[Country])                                                    AS countries,
       SUM(s.[Net Amount])                                                            AS revenue_all,
       CAST(100.0 * SUM(s.[Net Amount]) / SUM(SUM(s.[Net Amount])) OVER () AS DECIMAL(5,1)) AS pct_all,
       SUM(CASE WHEN d.[Date] BETWEEN '2011-01-01' AND '2011-12-09' THEN s.[Net Amount] END) AS revenue_2011,
       CAST(100.0 * SUM(CASE WHEN d.[Date] BETWEEN '2011-01-01' AND '2011-12-09' THEN s.[Net Amount] END)
            / SUM(SUM(CASE WHEN d.[Date] BETWEEN '2011-01-01' AND '2011-12-09' THEN s.[Net Amount] END)) OVER ()
            AS DECIMAL(5,1))                                                          AS pct_2011
FROM rpt.vw_sales   AS s
JOIN rpt.vw_date    AS d ON d.date_key    = s.date_key
JOIN rpt.vw_product AS p ON p.product_key = s.product_key
JOIN rpt.vw_country AS k ON k.country_key = s.country_key
WHERE p.[Is Product] = 1
GROUP BY k.[Market]
ORDER BY revenue_all DESC;

-- N4. Top 10 countries outside the UK (all data), with their share of international revenue
SELECT TOP (10)
       k.[Country],
       SUM(s.[Net Amount]) AS net_revenue,
       CAST(100.0 * SUM(s.[Net Amount]) / SUM(SUM(s.[Net Amount])) OVER () AS DECIMAL(5,1)) AS pct_of_international
FROM rpt.vw_sales   AS s
JOIN rpt.vw_product AS p ON p.product_key = s.product_key
JOIN rpt.vw_country AS k ON k.country_key = s.country_key
WHERE p.[Is Product] = 1
  AND k.[Market] = 'International'
GROUP BY k.[Country]
ORDER BY net_revenue DESC;

-- N5. Most cancelled products by value (all data)
SELECT TOP (5)
       p.[Stock Code], p.[Product], p.[ABC Class],
       SUM(s.[Cancelled Amount])   AS cancelled_value,
       SUM(s.[Gross Sales Amount]) AS gross_sales,
       CAST(100.0 * SUM(s.[Cancelled Amount]) / NULLIF(SUM(s.[Gross Sales Amount]), 0) AS DECIMAL(6,1)) AS cancelled_pct_of_sales
FROM rpt.vw_sales   AS s
JOIN rpt.vw_product AS p ON p.product_key = s.product_key
WHERE p.[Is Product] = 1
GROUP BY p.[Stock Code], p.[Product], p.[ABC Class]
ORDER BY cancelled_value DESC;

-- N6. Check before claiming: when were the two big cancellations, and do they explain
--     why the 2011 cancellation rate (4.8%) is almost double 2010 (2.5%)?
SELECT p.[Stock Code], p.[Product], s.[Invoice No], s.[Is Cancellation],
       CAST(s.[Invoice Time] AS DATE) AS invoice_date,
       s.[Quantity], s.[Net Amount], c.[Customer ID]
FROM rpt.vw_sales    AS s
JOIN rpt.vw_product  AS p ON p.product_key  = s.product_key
JOIN rpt.vw_customer AS c ON c.customer_key = s.customer_key
WHERE p.[Stock Code] IN ('23843', '23166')
  AND ABS(s.[Quantity]) >= 1000
ORDER BY p.[Stock Code], s.[Invoice Time];
