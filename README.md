# Online Retail Sales BI: SQL Server → Power BI

> **Status: in progress.** Steps 1–4 of 10 complete, step 5 in progress. Target completion: 12 October 2026.

An end-to-end BI project on 1.07 million real transactions from a UK online retailer:
raw files → SQL Server staging → cleaned, quality-logged data → star schema → Power BI dashboard.

## Business questions

| # | Question | Asked by |
|---|---|---|
| 1 | Is net revenue growing, compared with the same period last year? | Managing director |
| 2 | Which markets outside the UK deserve more investment? | Head of international sales |
| 3 | Which products drive revenue, and which are cancelled or returned most? | Merchandising |
| 4 | Do customers come back? Which segments are most valuable, and which are at risk? | Marketing / CRM |
| 5 | How far can these numbers be trusted? | Every report user |

## Architecture

```
UCI Excel (2 sheets)
  → Extract       python/convert_to_csv.py        raw CSV, every value kept as text
  → Staging       sql/01_staging_load.sql         stg schema, lineage columns
  → Clean + DQ    sql/03-05                       typed data, dq.issue_log, reconciliation
  → Star schema   sql/06-08                       dw.fact_sales + date, customer, product, country
  → Pipeline      sql/09-11                       etl.usp_run_all: one command, tests, etl.run_log
  → Views         (step 7)                        rpt schema, the only source for Power BI
  → Power BI      (steps 8–9)                     Power Query, DAX, 3 pages, row-level security
```

## Repository structure

| Folder | Contents |
|---|---|
| `python/` | Extract script |
| `sql/` | T-SQL scripts, numbered in run order |
| `data/` | How to obtain the raw data (data itself is not committed) |
| `docs/` | Decision log, data dictionary, ERD (coming) |

## How to reproduce (so far)

1. Download the data (see `data/README.md`) to `C:\data\`.
2. `py C:\data\convert_to_csv.py` → two CSV files (525,461 and 541,910 rows).
3. In SSMS: `CREATE DATABASE RetailDW;` then run `sql/01_staging_load.sql`.
4. Cleaning: run `sql/03`, `04`, then `05` (checks C1-C10).
5. Star schema: run `sql/06`, `07`, then `08` (checks S1-S9). Design: `docs/star_schema.md`.
6. Pipeline: run `sql/09`, `10`, then `11` (checks E1-E5). From then on, one command rebuilds everything: `EXEC etl.usp_run_all;`

## Limitations and next steps

- **Stock write-offs are out of scope.** 3,457 lines are stock adjustments (lost, damaged, miscounted), recorded with zero price and no customer. They are excluded from sales, but they point to an inventory-shrinkage question this dataset cannot fully answer.
- **Next step:** with product cost data, stock write-offs could be valued in £ and ranked by product, to show where shrinkage costs the business most.

## Tools

SQL Server 2025 (Developer), T-SQL, SSMS 22, Python (pandas), Power BI Desktop. Runs on an Azure Windows VM.

---
Lucas Le · [LinkedIn](https://www.linkedin.com/in/lucasle68/) · [GitHub](https://github.com/lucasle68-git)
