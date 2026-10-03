/* =====================================================================
   03_clean_objects.sql  |  Step 4a: Objects for the cleansing layer
   ---------------------------------------------------------------------
   Purpose : Create the tables that hold cleaned data and data-quality evidence.
             - dq.quality_rule         : the 11 rules from docs/data_quality.md
             - dq.issue_log            : one row per excluded (or anomaly-flagged) staging row
             - clean.non_product_code  : hand-curated list of non-product stock codes (R6)
             - clean.sales_line        : typed, de-duplicated sales lines with flags
   Input   : none
   Output  : empty tables + reference data (dq.quality_rule, clean.non_product_code)
   Re-run  : Safe to re-run: drops and recreates everything in this file.
   ===================================================================== */
USE RetailDW;
GO

IF SCHEMA_ID('dq')    IS NULL EXEC('CREATE SCHEMA dq');
IF SCHEMA_ID('clean') IS NULL EXEC('CREATE SCHEMA clean');
GO

-- Drop in dependency order (the log points to the rule table)
DROP TABLE IF EXISTS dq.issue_log;
DROP TABLE IF EXISTS dq.quality_rule;
DROP TABLE IF EXISTS clean.sales_line;
DROP TABLE IF EXISTS clean.non_product_code;
GO

/* ---------- 1. Rule catalogue: every rule the pipeline applies ---------- */
CREATE TABLE dq.quality_rule (
    rule_id      VARCHAR(5)     NOT NULL CONSTRAINT PK_dq_quality_rule PRIMARY KEY,
    rule_name    NVARCHAR(100)  NOT NULL,
    dq_dimension NVARCHAR(30)   NOT NULL,   -- DAMA dimension, or Classification for business flags
    rule_action  VARCHAR(10)    NOT NULL,   -- exclude | flag | check
    description  NVARCHAR(300)  NOT NULL
);

INSERT INTO dq.quality_rule (rule_id, rule_name, dq_dimension, rule_action, description) VALUES
('R0',  'Unconvertible value',                 'Validity',         'exclude', 'Quantity, price or date cannot be converted to a number or date'),
('R1',  'Overlap between source files',        'Uniqueness',       'exclude', 'File-2 copy of 1-9 Dec 2010, already present in file 1'),
('R2',  'Exact duplicate line',                'Uniqueness',       'exclude', 'Extra copies of identical lines; the first copy is kept'),
('R3',  'Bad-debt adjustment',                 'Validity (scope)', 'exclude', 'Invoices starting with A: accounting write-offs, not sales'),
('R4',  'Stock write-off',                     'Validity (scope)', 'exclude', 'Quantity <= 0 on a non-cancellation invoice: lost or damaged stock'),
('R5',  'Test record',                         'Validity (scope)', 'exclude', 'Stock codes TEST001 and TEST002'),
('R6',  'Non-product line',                    'Classification',   'flag',    'Shipping, fees, discounts, samples, vouchers: is_product = 0'),
('R7',  'Cancellation',                        'Classification',   'flag',    'Invoice starts with C: is_cancellation = 1'),
('R8',  'Missing customer',                    'Completeness',     'flag',    'No customer ID: kept with customer_id NULL (Unknown in the model)'),
('R9',  'Cancellation with positive quantity', 'Consistency',      'flag',    'Kept as recorded, dq_flag = R9; immaterial'),
('R10', 'Price precision',                     'Accuracy',         'check',   'Price stored as DECIMAL(12,3); check that no value has more decimals');

/* ---------- 2. Row-level evidence: why each row was excluded or flagged ---------- */
CREATE TABLE dq.issue_log (
    issue_id      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dq_issue_log PRIMARY KEY,
    rule_id       VARCHAR(5)    NOT NULL CONSTRAINT FK_issue_log_rule REFERENCES dq.quality_rule (rule_id),
    issue_action  VARCHAR(10)   NOT NULL,   -- excluded | flagged
    stg_row_id    BIGINT        NOT NULL,   -- points back to stg.online_retail_raw
    source_file   NVARCHAR(100) NULL,
    invoice_no    NVARCHAR(50)  NULL,
    stock_code    NVARCHAR(50)  NULL,
    quantity_raw  NVARCHAR(50)  NULL,       -- raw text, so R0 rows are still readable
    price_raw     NVARCHAR(50)  NULL,
    logged_at     DATETIME2(0)  NOT NULL
);

/* ---------- 3. Hand-curated non-product stock codes (from profiling query B4) ---------- */
CREATE TABLE clean.non_product_code (
    stock_code NVARCHAR(50) NOT NULL CONSTRAINT PK_non_product_code PRIMARY KEY,
    category   NVARCHAR(30) NOT NULL
);

INSERT INTO clean.non_product_code (stock_code, category) VALUES
('POST', 'Shipping'), ('DOT', 'Shipping'), ('C2', 'Shipping'), ('C3', 'Shipping'),
('BANK CHARGES', 'Fees'), ('AMAZONFEE', 'Fees'), ('CRUK', 'Fees'),
('D', 'Discount'),
('M', 'Manual adjustment'), ('ADJUST', 'Manual adjustment'), ('ADJUST2', 'Manual adjustment'),
('S', 'Samples'),
('GIFT', 'Gift voucher'),
('GIFT_0001_10', 'Gift voucher'), ('GIFT_0001_20', 'Gift voucher'), ('GIFT_0001_30', 'Gift voucher'),
('GIFT_0001_40', 'Gift voucher'), ('GIFT_0001_50', 'Gift voucher'), ('GIFT_0001_60', 'Gift voucher'),
('GIFT_0001_70', 'Gift voucher'), ('GIFT_0001_80', 'Gift voucher'), ('GIFT_0001_90', 'Gift voucher');

/* ---------- 4. Cleaned sales lines: typed, de-duplicated, flagged ---------- */
CREATE TABLE clean.sales_line (
    stg_row_id        BIGINT         NOT NULL CONSTRAINT PK_sales_line PRIMARY KEY,
    invoice_no        NVARCHAR(50)   NOT NULL,
    stock_code        NVARCHAR(50)   NOT NULL,
    description       NVARCHAR(255)  NULL,
    quantity          INT            NOT NULL,
    unit_price        DECIMAL(12,3)  NOT NULL,
    line_amount       AS CAST(quantity * unit_price AS DECIMAL(14,3)) PERSISTED,
    invoice_ts        DATETIME2(0)   NOT NULL,
    customer_id       INT            NULL,
    country           NVARCHAR(100)  NULL,
    is_cancellation   BIT            NOT NULL,   -- R7
    is_product        BIT            NOT NULL,   -- R6
    product_category  NVARCHAR(30)   NOT NULL,   -- 'Product' or the non-product category
    dq_flag           VARCHAR(5)     NULL,       -- R9 anomalies
    source_file       NVARCHAR(100)  NOT NULL
);
GO

-- Check: 11 rules and 22 non-product codes
SELECT (SELECT COUNT(*) FROM dq.quality_rule)               AS rules,
       (SELECT COUNT(*) FROM clean.non_product_code) AS non_product_codes;
