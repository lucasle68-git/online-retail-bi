/* =====================================================================
   07_usp_load_star.sql  |  Step 5b: Load the star schema
   ---------------------------------------------------------------------
   Purpose : Fill the dimensions, then the fact, from clean.sales_line.
             Full refresh inside one transaction; commits only if the fact
             reconciles with the clean table (same rows, same GBP total).
   Input   : clean.sales_line (step 4)
   Output  : dw.dim_date, dw.dim_customer, dw.dim_product, dw.dim_country, dw.fact_sales
   Re-run  : Safe to re-run: same input gives the same keys and the same result.
   ===================================================================== */
USE RetailDW;
GO

CREATE OR ALTER PROCEDURE dw.usp_load_star
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @first_day DATE, @last_day DATE,
            @clean_rows INT, @clean_gbp DECIMAL(18,3),
            @fact_rows  INT, @fact_gbp  DECIMAL(18,3),
            @msg NVARCHAR(400);

    -- Calendar covers whole years: 1 Jan of the first sales year to 31 Dec of the last
    SELECT @first_day = DATEFROMPARTS(YEAR(MIN(invoice_ts)), 1, 1),
           @last_day  = DATEFROMPARTS(YEAR(MAX(invoice_ts)), 12, 31)
    FROM clean.sales_line;
    -- return a time span from 2009-01-01 to 2021-12-31, so Power BI time intelligence works for all years

    BEGIN TRY
        BEGIN TRANSACTION;

        /* 1. Empty the model. Fact first: it points to the dimensions.
              TRUNCATE is fast but is not allowed on a table that a foreign key points to,
              so the dimensions are emptied with DELETE. */
        TRUNCATE TABLE dw.fact_sales;
        DELETE FROM dw.dim_date;
        DELETE FROM dw.dim_customer;
        DELETE FROM dw.dim_product;
        DELETE FROM dw.dim_country;

        /* 2. Date: one row per day. GENERATE_SERIES gives 0, 1, 2 ... = days after @first_day */
        INSERT INTO dw.dim_date (date_key, full_date, calendar_year, quarter_num, quarter_label,
                                 month_num, month_name, month_short, year_month, month_start,
                                 day_of_month, weekday_num, weekday_name, is_weekend, iso_week)
        SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),           -- 2010-12-01 -> 20101201
               d,
               YEAR(d),
               DATEPART(QUARTER, d),
               CONCAT(YEAR(d), '-Q', DATEPART(QUARTER, d)),
               MONTH(d),
               DATENAME(MONTH, d),
               LEFT(DATENAME(MONTH, d), 3),
               CONVERT(CHAR(7), d, 126),                            -- yyyy-mm
               DATEFROMPARTS(YEAR(d), MONTH(d), 1),
               DAY(d),
               DATEDIFF(DAY, '19000101', d) % 7 + 1,                -- 1 Jan 1900 was a Monday
               DATENAME(WEEKDAY, d),
               CASE WHEN DATEDIFF(DAY, '19000101', d) % 7 >= 5 THEN 1 ELSE 0 END,
               DATEPART(ISO_WEEK, d)
        FROM (SELECT DATEADD(DAY, value, @first_day) AS d
              FROM GENERATE_SERIES(0, DATEDIFF(DAY, @first_day, @last_day))) AS days;

        /* 3. Customer: the Unknown member, then one row per customer ID */
        INSERT INTO dw.dim_customer (customer_key, customer_id, customer_label, is_known_customer,
                                     first_purchase_date, cohort_month)
        VALUES (-1, NULL, N'Unknown customer', 0, NULL, NULL);

        INSERT INTO dw.dim_customer (customer_key, customer_id, customer_label, is_known_customer,
                                     first_purchase_date, cohort_month)
        SELECT ROW_NUMBER() OVER (ORDER BY customer_id),
               customer_id,
               CONCAT(N'Customer ', customer_id),
               1,
               first_purchase,
               DATEFROMPARTS(YEAR(first_purchase), MONTH(first_purchase), 1)
        FROM (SELECT customer_id,
                     CAST(MIN(CASE WHEN is_cancellation = 0 AND is_product = 1
                                   THEN invoice_ts END) AS DATE) AS first_purchase
              FROM clean.sales_line
              WHERE customer_id IS NOT NULL
              GROUP BY customer_id) AS c;

        /* 4. Product: one row per stock code. A code can carry several descriptions over time;
              keep the most frequent non-empty one, and the most recent if tied. */
        INSERT INTO dw.dim_product (product_key, stock_code, description, product_category, is_product)
        SELECT ROW_NUMBER() OVER (ORDER BY stock_code),
               stock_code, description, product_category, is_product
        FROM (SELECT stock_code, description, product_category, is_product,
                     ROW_NUMBER() OVER (PARTITION BY stock_code
                                        ORDER BY CASE WHEN description IS NULL THEN 1 ELSE 0 END,
                                                 COUNT(*) DESC,
                                                 MAX(invoice_ts) DESC) AS pick
              FROM clean.sales_line
              GROUP BY stock_code, description, product_category, is_product) AS d
        WHERE pick = 1;

        /* 5. Country: the Unknown member, then one row per country */
        INSERT INTO dw.dim_country (country_key, country_name, market)
        VALUES (-1, N'Unknown', N'Unknown');

        INSERT INTO dw.dim_country (country_key, country_name, market)
        SELECT ROW_NUMBER() OVER (ORDER BY country),
               country,
               CASE WHEN country = N'United Kingdom' THEN N'UK'
                    WHEN country = N'Unspecified'    THEN N'Unknown'
                    ELSE N'International' END
        FROM (SELECT DISTINCT country FROM clean.sales_line WHERE country IS NOT NULL) AS c;

        /* 6. Fact: look up each line's keys in the dimensions.
              Customer and country: no match -> -1 (Unknown).
              Product and date always exist; if one is ever missing, the NOT NULL / FOREIGN KEY
              rules stop the load with an error instead of dropping the row silently. */
        INSERT INTO dw.fact_sales (sales_line_id, invoice_no, date_key, customer_key, product_key,
                                   country_key, invoice_ts, quantity, unit_price, line_amount,
                                   is_cancellation, dq_flag)
        SELECT s.stg_row_id,
               s.invoice_no,
               YEAR(s.invoice_ts) * 10000 + MONTH(s.invoice_ts) * 100 + DAY(s.invoice_ts),
               COALESCE(c.customer_key, -1),
               p.product_key,
               COALESCE(k.country_key, -1),
               s.invoice_ts, s.quantity, s.unit_price, s.line_amount,
               s.is_cancellation, s.dq_flag
        FROM clean.sales_line AS s
        LEFT JOIN dw.dim_customer AS c ON c.customer_id  = s.customer_id
        LEFT JOIN dw.dim_product  AS p ON p.stock_code   = s.stock_code
        LEFT JOIN dw.dim_country  AS k ON k.country_name = s.country;

        /* 7. Reconcile: the fact must hold every clean row and every penny */
        SELECT @clean_rows = COUNT(*), @clean_gbp = SUM(line_amount) FROM clean.sales_line;
        SELECT @fact_rows  = COUNT(*), @fact_gbp  = SUM(line_amount) FROM dw.fact_sales;

        IF @clean_rows <> @fact_rows OR @clean_gbp <> @fact_gbp
        BEGIN
            SET @msg = CONCAT(N'Star load does not reconcile. Clean: ', @clean_rows, N' rows, GBP ', @clean_gbp,
                              N'. Fact: ', @fact_rows, N' rows, GBP ', @fact_gbp, N'.');
            THROW 50002, @msg, 1;
        END;

        COMMIT TRANSACTION;

        SELECT @clean_rows               AS clean_rows,
               @fact_rows                AS fact_rows,
               @clean_rows - @fact_rows  AS row_difference,
               @clean_gbp                AS clean_gbp,
               @fact_gbp                 AS fact_gbp,
               @clean_gbp - @fact_gbp    AS gbp_difference;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
