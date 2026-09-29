"""
convert_to_csv.py  |  Step 1: Extract

Purpose : Convert the two sheets of the UCI Online Retail II workbook into CSV files
          that SQL Server can bulk-load.
Input   : C:\data\online_retail_II.xlsx  (sheets "Year 2009-2010", "Year 2010-2011")
Output  : C:\data\online_retail_2009_2010.csv, C:\data\online_retail_2010_2011.csv
Re-run  : py C:\data\convert_to_csv.py   (safe to re-run; overwrites the CSVs)

Every value is read as text (dtype=str) so nothing is silently re-typed
(dates, customer IDs, prices). Type conversion happens later, in SQL, with logging.
"""
import pandas as pd
from pathlib import Path

src = Path(r"C:\data\online_retail_II.xlsx")
print("Reading Excel (takes 2-4 minutes)...")
sheets = pd.read_excel(src, sheet_name=None, dtype=str)

for name, df in sheets.items():
    year = name.replace("Year ", "").replace("-", "_")      # "Year 2009-2010" -> "2009_2010"
    out = src.with_name(f"online_retail_{year}.csv")
    df.to_csv(out, index=False, encoding="utf-8")
    print(f"{name}: {len(df):,} rows -> {out.name}")
