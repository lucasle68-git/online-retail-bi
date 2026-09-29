/* =====================================================================
   01_staging_load.sql  |  Step 2: Staging load
   ---------------------------------------------------------------------
   Purpose : Load the raw Online Retail II CSV files into the staging layer,
             exactly as received, with lineage columns.
   Input   : C:\data\online_retail_2009_2010.csv
             C:\data\online_retail_2010_2011.csv   (from python/convert_to_csv.py)
   Output  : RetailDW.stg.online_retail_raw  (all columns text + source_file, loaded_at)
   Re-run  : Safe to re-run (idempotent): drops and recreates the staging objects.
   Check   : Final query must return 525,461 and 541,910 rows.
   ===================================================================== */
USE RetailDW;
GO

-- 1. A separate "stg" schema keeps raw data apart from the clean model
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
GO

DROP VIEW  IF EXISTS stg.v_online_retail_load;
DROP TABLE IF EXISTS stg.online_retail_raw;
GO

-- 2. Every column is text: staging stores data exactly as received
CREATE TABLE stg.online_retail_raw (
    Invoice      NVARCHAR(50)  NULL,
    StockCode    NVARCHAR(50)  NULL,
    Description  NVARCHAR(255) NULL,
    Quantity     NVARCHAR(50)  NULL,
    InvoiceDate  NVARCHAR(50)  NULL,
    Price        NVARCHAR(50)  NULL,
    CustomerID   NVARCHAR(50)  NULL,
    Country      NVARCHAR(100) NULL,
    source_file  NVARCHAR(100) NULL,   -- lineage: which file the row came from
    loaded_at    DATETIME2(0)  NULL    -- lineage: when it was loaded
);
GO

-- 3. A view exposing only the 8 columns in the CSV, used as the load target
CREATE VIEW stg.v_online_retail_load AS
SELECT Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country
FROM stg.online_retail_raw;
GO

-- 4. Load file 1, then stamp its lineage
BULK INSERT stg.v_online_retail_load
FROM 'C:\data\online_retail_2009_2010.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', TABLOCK);

UPDATE stg.online_retail_raw
SET source_file = 'online_retail_2009_2010.csv', loaded_at = SYSDATETIME()
WHERE source_file IS NULL;

-- 5. Load file 2, then stamp its lineage
BULK INSERT stg.v_online_retail_load
FROM 'C:\data\online_retail_2010_2011.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', TABLOCK);

UPDATE stg.online_retail_raw
SET source_file = 'online_retail_2010_2011.csv', loaded_at = SYSDATETIME()
WHERE source_file IS NULL;
GO

-- 6. Check: rows per file (expect 525,461 and 541,910)
SELECT source_file, COUNT(*) AS rows_loaded
FROM stg.online_retail_raw
GROUP BY source_file
ORDER BY source_file;
