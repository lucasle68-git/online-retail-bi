/* =====================================================================
   06_dw_objects.sql  |  Step 5a: Star schema objects
   ---------------------------------------------------------------------
   Purpose : Create the dimensional model that Power BI will read.
             - dw.dim_date      : one row per calendar day, full years
             - dw.dim_customer  : one row per customer ID, plus -1 "Unknown customer"
             - dw.dim_product   : one row per stock code, with category and is_product
             - dw.dim_country   : one row per country, plus -1 "Unknown"
             - dw.fact_sales    : one row per clean sales line (the grain)
   Input   : none
   Output  : empty tables with primary keys and relationships (foreign keys)
   Re-run  : Safe to re-run: drops and recreates everything in this file.
   Design  : docs/star_schema.md
   ===================================================================== */
USE RetailDW;
GO

IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO

-- Drop the fact first: it points to every dimension
DROP TABLE IF EXISTS dw.fact_sales;
DROP TABLE IF EXISTS dw.dim_date;
DROP TABLE IF EXISTS dw.dim_customer;
DROP TABLE IF EXISTS dw.dim_product;
DROP TABLE IF EXISTS dw.dim_country;
GO

/* ---------- 1. Date: every day, so Power BI time intelligence (YoY, YTD) works ---------- */
CREATE TABLE dw.dim_date (
    date_key       INT          NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,  -- 20101201
    full_date      DATE         NOT NULL CONSTRAINT UQ_dim_date_full UNIQUE,
    calendar_year  SMALLINT     NOT NULL,
    quarter_num    TINYINT      NOT NULL,
    quarter_label  CHAR(7)      NOT NULL,   -- 2010-Q4
    month_num      TINYINT      NOT NULL,
    month_name     VARCHAR(10)  NOT NULL,   -- December
    month_short    CHAR(3)      NOT NULL,   -- Dec
    year_month     CHAR(7)      NOT NULL,   -- 2010-12
    month_start    DATE         NOT NULL,   -- 2010-12-01, for monthly chart axes
    day_of_month   TINYINT      NOT NULL,
    weekday_num    TINYINT      NOT NULL,   -- 1 = Monday ... 7 = Sunday
    weekday_name   VARCHAR(10)  NOT NULL,
    is_weekend     BIT          NOT NULL,
    iso_week       TINYINT      NOT NULL
);

/* ---------- 2. Customer: who bought. -1 holds every line with no customer ID (R8) ---------- */
CREATE TABLE dw.dim_customer (
    customer_key         INT           NOT NULL CONSTRAINT PK_dim_customer PRIMARY KEY,  -- surrogate key; -1 = Unknown
    customer_id          INT           NULL,      -- natural key from the source; NULL only for Unknown
    customer_label       NVARCHAR(30)  NOT NULL,  -- 'Customer 13085' or 'Unknown customer'
    is_known_customer    BIT           NOT NULL,
    first_purchase_date  DATE          NULL,      -- first product purchase that was not a cancellation
    cohort_month         DATE          NULL,      -- month of first purchase, for retention analysis
    CONSTRAINT UQ_dim_customer_id UNIQUE (customer_id)
);

/* ---------- 3. Product: what was sold. Non-product codes stay, with is_product = 0 (R6) ---------- */
CREATE TABLE dw.dim_product (
    product_key       INT            NOT NULL CONSTRAINT PK_dim_product PRIMARY KEY,
    stock_code        NVARCHAR(50)   NOT NULL CONSTRAINT UQ_dim_product_code UNIQUE,
    description       NVARCHAR(255)  NULL,      -- the most frequent description of this code
    product_category  NVARCHAR(30)   NOT NULL,  -- 'Product', 'Shipping', 'Fees', ...
    is_product        BIT            NOT NULL   -- KPI filter: revenue and cancellation rate use 1
);

/* ---------- 4. Country: where the order was shipped ---------- */
CREATE TABLE dw.dim_country (
    country_key   INT            NOT NULL CONSTRAINT PK_dim_country PRIMARY KEY,  -- -1 = Unknown
    country_name  NVARCHAR(100)  NOT NULL CONSTRAINT UQ_dim_country_name UNIQUE,
    market        NVARCHAR(20)   NOT NULL   -- 'UK', 'International' or 'Unknown' (business question 2)
);

/* ---------- 5. Fact: one row per sales line. Numbers here, descriptions in the dimensions ---------- */
CREATE TABLE dw.fact_sales (
    sales_line_id    BIGINT         NOT NULL CONSTRAINT PK_fact_sales PRIMARY KEY,  -- = stg_row_id (lineage)
    invoice_no       NVARCHAR(50)   NOT NULL,   -- degenerate dimension: groups lines into orders
    date_key         INT            NOT NULL CONSTRAINT FK_fact_date     REFERENCES dw.dim_date (date_key),
    customer_key     INT            NOT NULL CONSTRAINT FK_fact_customer REFERENCES dw.dim_customer (customer_key),
    product_key      INT            NOT NULL CONSTRAINT FK_fact_product  REFERENCES dw.dim_product (product_key),
    country_key      INT            NOT NULL CONSTRAINT FK_fact_country  REFERENCES dw.dim_country (country_key),
    invoice_ts       DATETIME2(0)   NOT NULL,   -- keeps the time of day
    quantity         INT            NOT NULL,
    unit_price       DECIMAL(12,3)  NOT NULL,
    line_amount      DECIMAL(14,3)  NOT NULL,
    is_cancellation  BIT            NOT NULL,
    dq_flag          VARCHAR(5)     NULL
);
GO

-- Check: 5 tables in the dw schema, with their column counts
SELECT t.name AS table_name, COUNT(c.column_id) AS columns
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE t.schema_id = SCHEMA_ID('dw')
GROUP BY t.name
ORDER BY t.name;
