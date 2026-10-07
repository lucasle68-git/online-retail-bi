/* =====================================================================
   08_check_star.sql  |  Step 5c: Run the star load and check the results
   ---------------------------------------------------------------------
   Purpose : Run dw.usp_load_star, then check that the model is complete,
             that Unknown members carry the right rows, and that the
             headline KPIs can be answered from the star alone.
   Input   : objects from 06 and 07, clean.sales_line
   Output  : Result grids only (S1-S9)
   Re-run  : Safe to re-run.
   ===================================================================== */
USE RetailDW;
GO

-- S1. Run the load. Expect one row: row_difference = 0 and gbp_difference = 0
EXEC dw.usp_load_star;

-- S2. Rows per table. Expect fact = 1,029,620 and dim_date = 1,095 (2009-2011, no leap year)
SELECT 'dim_date'     AS table_name, COUNT(*) AS rows_loaded FROM dw.dim_date     UNION ALL
SELECT 'dim_customer',               COUNT(*)                FROM dw.dim_customer UNION ALL
SELECT 'dim_product',                COUNT(*)                FROM dw.dim_product  UNION ALL
SELECT 'dim_country',                COUNT(*)                FROM dw.dim_country  UNION ALL
SELECT 'fact_sales',                 COUNT(*)                FROM dw.fact_sales;

-- S3. Unknown members. Expect unknown_customer_lines = 231,751 (C4, rule R8)
SELECT SUM(CASE WHEN customer_key = -1 THEN 1 ELSE 0 END) AS unknown_customer_lines,
       SUM(CASE WHEN country_key  = -1 THEN 1 ELSE 0 END) AS unknown_country_lines
FROM dw.fact_sales;

-- S4. Every dimension row has a key the fact can use: dimension members never used by the fact
--     Expect 0 for product and country; customers with no purchase are possible; days without sales are normal
SELECT (SELECT COUNT(*) FROM dw.dim_product  AS p WHERE NOT EXISTS (SELECT 1 FROM dw.fact_sales f WHERE f.product_key  = p.product_key))  AS unused_products,
       (SELECT COUNT(*) FROM dw.dim_country  AS k WHERE k.country_key <> -1
                                               AND NOT EXISTS (SELECT 1 FROM dw.fact_sales f WHERE f.country_key  = k.country_key))  AS unused_countries,
       (SELECT COUNT(*) FROM dw.dim_customer AS c WHERE c.first_purchase_date IS NULL AND c.customer_key <> -1)                       AS customers_without_purchase,
       (SELECT COUNT(*) FROM dw.dim_date     AS d WHERE NOT EXISTS (SELECT 1 FROM dw.fact_sales f WHERE f.date_key     = d.date_key))     AS days_without_sales;

-- S5. Design check: customers seen in more than one country (why country sits on the fact, not on the customer)
SELECT COUNT(*) AS customers_in_several_countries
FROM (SELECT customer_id
      FROM clean.sales_line
      WHERE customer_id IS NOT NULL
      GROUP BY customer_id
      HAVING COUNT(DISTINCT country) > 1) AS x;

-- S6. Design check: stock codes with more than one description (why dim_product picks one)
SELECT COUNT(*) AS codes_with_several_descriptions
FROM (SELECT stock_code
      FROM clean.sales_line
      GROUP BY stock_code
      HAVING COUNT(DISTINCT description) > 1) AS x;

-- S7. Headline KPIs from the star (product lines only, see docs/metric_definitions.md)
--     Expect net_product_revenue = 18,927,399.067 (C5) and a cancellation rate near 3.6%
SELECT SUM(f.line_amount)                                              AS net_product_revenue,
       SUM(CASE WHEN f.is_cancellation = 0 THEN f.line_amount END)     AS gross_product_sales,
       -SUM(CASE WHEN f.is_cancellation = 1 THEN f.line_amount END)    AS cancelled_value,
       CAST(-100.0 * SUM(CASE WHEN f.is_cancellation = 1 THEN f.line_amount END)
                   / SUM(CASE WHEN f.is_cancellation = 0 THEN f.line_amount END) AS DECIMAL(5,2)) AS cancellation_rate_pct
FROM dw.fact_sales AS f
JOIN dw.dim_product AS p ON p.product_key = f.product_key
WHERE p.is_product = 1;

-- S8. Preview of business questions 1 and 2: net product revenue by year and market
SELECT d.calendar_year, k.market,
       SUM(f.line_amount) AS net_product_revenue
FROM dw.fact_sales  AS f
JOIN dw.dim_date    AS d ON d.date_key    = f.date_key
JOIN dw.dim_country AS k ON k.country_key = f.country_key
JOIN dw.dim_product AS p ON p.product_key = f.product_key
WHERE p.is_product = 1
GROUP BY d.calendar_year, k.market
ORDER BY d.calendar_year, k.market;

-- S9. Preview of business question 4: new customers per cohort month (first 6 months)
SELECT TOP (6) cohort_month, COUNT(*) AS new_customers
FROM dw.dim_customer
WHERE cohort_month IS NOT NULL
GROUP BY cohort_month
ORDER BY cohort_month;
