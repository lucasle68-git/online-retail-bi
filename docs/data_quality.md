# Data quality findings and cleaning rules

Source: `stg.online_retail_raw` (1,067,371 rows). Evidence: `sql/02_profiling.sql` (queries A1–B7).
Principle: **no row disappears without a reason.** Every row is either kept (possibly flagged) or excluded and logged in `dq.issue_log` with its rule ID.

## 1. Profile summary

| Check | Rows | % of rows | Query |
|---|---:|---:|---|
| Total rows loaded | 1,067,371 | 100% | A2 |
| Missing customer ID | 243,007 | 22.8% | A2 |
| Exact duplicate rows (extra copies) | 34,335 | 3.2% | A3 |
| &nbsp;&nbsp;of which: copies across the two files | 22,844 | 2.1% | B2 |
| &nbsp;&nbsp;of which: repeated within one file | 11,491 | 1.1% | B2 |
| Quantity ≤ 0 | 22,950 | 2.2% | A2 |
| Cancellation lines (invoice starts with `C`) | 19,494 | 1.8% | A2 |
| Price ≤ 0 | 6,207 | 0.6% | A2 |
| Non-numeric invoices not starting with `C` | 6 | 0.0% | A2, B3 |
| Unreadable dates | 0 | 0% | A2 |

Revenue on lines with no customer ID: **£2.64m of £19.29m (13.7%)**, preliminary (before de-duplication). Dropping these rows, as many public analyses do, would understate revenue by roughly this share. Final figure after cleaning: **14.3%** (section 5).

## 2. Findings and rules

| Rule | Finding | Evidence | Decision | Rationale |
|---|---|---|---|---|
| R1 | The two source files overlap on 1–9 Dec 2010 | File 1 ends 2010-12-09 20:01, file 2 starts 2010-12-01 08:26 (A1); 22,523 rows in that window in **each** file (B1) | **Exclude** the file-2 copy of 1–9 Dec 2010 | Keeping both would double-count December 2010 revenue |
| R2 | Exact duplicate lines within a file (same invoice, product, quantity, price, minute) | 11,491 extra copies (B2) | **Exclude** extra copies, keep one | Treated as data-entry duplicates. Conservative: avoids overstating revenue. *Assumption, stated in README* |
| R3 | Invoices starting with `A` are bad-debt write-offs | 6 lines, stock code `B`, "Adjust bad debt", net ≈ −£147.6k, no customer (B3) | **Exclude** from sales fact | Accounting entries, not sales transactions |
| R4 | Stock write-offs: quantity ≤ 0, not a cancellation | 3,457 lines, **all** with price = 0 and no customer; descriptions "lost", "damages", "short" (B5) | **Exclude** from sales fact | Inventory adjustments: no buyer, no money. Would distort units sold |
| R5 | Test records | `TEST001` (15 lines), `TEST002` (2 lines), "This is a test product" (B4) | **Exclude** from sales fact | Not real transactions |
| R6 | Non-product codes: shipping, fees, discounts, manual adjustments, vouchers | See section 3 (B4) | **Keep**, flag `is_product = 0` with a category | Total revenue stays consistent with the books; product analysis filters them out |
| R7 | Cancellations | 19,494 lines, invoice starts with `C` | **Keep**, flag `is_cancellation = 1`, negative quantity | Net revenue stays correct; enables cancellation rate (business question 3) |
| R8 | Missing customer ID | 243,007 lines in staging (231,751 after cleaning), 14.3% of net revenue | **Keep**, map to customer key `-1` ("Unknown") | Revenue stays complete; excluded only from customer analysis (question 4) |
| R9 | One cancellation line with a positive quantity | `C496350`, code `M`, quantity +1, £373.57, no customer (B7) | **Keep as recorded**, flag | Sign looks inconsistent, but source values are never altered silently. Immaterial: 0.002% of revenue |
| R10 | Very small prices | 18 lines priced below £0.005 turned "zero" when cast to 2 decimals (A2: 6,225 vs 6,207) | **Keep**; store price as `DECIMAL(12,3)` | Wrong precision silently changes results |

## 3. Stock code classification (hand-curated from B4)

Rule of thumb: ordinary products start with 5 digits. Codes that do not were reviewed one by one, because the pattern also catches real products.

| Category | Codes | `is_product` | Treatment |
|---|---|---:|---|
| Shipping | `POST`, `DOT`, `C2`, `C3` | 0 | Keep (R6) |
| Fees and commissions | `BANK CHARGES`, `AMAZONFEE`, `CRUK` | 0 | Keep (R6) |
| Discounts and manual adjustments | `D`, `M`, `ADJUST`, `ADJUST2` | 0 | Keep (R6) |
| Samples | `S` | 0 | Keep (R6) |
| Gift vouchers | `gift_0001_10` … `gift_0001_90`, `GIFT` | 0 | Keep (R6) |
| Bad-debt adjustment | `B` | – | Exclude (R3) |
| Test records | `TEST001`, `TEST002` | – | Exclude (R5) |
| **Real products** with non-standard codes | `DCGS…` (dotcom gift shop range), `PADS`, `SP1002` | 1 | Keep as products |

Open point: three `DCGS` lines are described as "ebay" (`DCGS0067`, `DCGS0069`, `DCGS0073`; 8 lines in total). Kept as products; immaterial.

## 4. Processing order and reconciliation (official results)

Source: `sql/05_check_clean.sql`, run on 2026-10-03 after `EXEC clean.usp_load_sales_line`.
Each row gets the **first** rule it breaks, in the order below (`WHERE rule_id IS NULL`), so every excluded row has exactly one reason. Flags R6-R9 live as columns in `clean.sales_line`; only R9 (one row to review) is also written to `dq.issue_log`.

| Order | Rule | Action | Rows |
|---:|---|---|---:|
| 0 | R0 Unconvertible value | Exclude | 0 |
| 1 | R1 Overlap between source files | Exclude | 22,523 |
| 2 | R2 Exact duplicate line | Exclude | 11,812 |
| 3 | R3 Bad-debt adjustment | Exclude | 6 |
| 4 | R4 Stock write-off | Exclude | 3,393 |
| 5 | R5 Test record | Exclude | 17 |
| | **Total excluded** | | **37,751 (3.5%)** |
| | **Clean rows** | | **1,029,620** |
| | **Staging rows** | | **1,067,371** |

**Reconciliation:** 1,029,620 clean + 37,751 excluded = 1,067,371 staging. Difference: 0.

What the numbers say:

- R2 = 11,812, exactly as predicted (34,335 duplicate copies − 22,523 already removed by R1).
- R4 = 3,393, not the 3,457 write-offs seen in profiling: 64 write-off lines were already excluded by R1 or R2. Nothing is lost, it is counted under the earlier rule.
- R0 = 0: every quantity, price, date and customer ID converted (the text → FLOAT → INT fallback handled values such as `13085.0`).
- 91% of excluded rows (R1 + R2 = 34,335) are source-file problems, not business events.

Automated tests (C8-C10), all returned 0 rows: no excluded row type survives in the clean table, no duplicate survives, and every staging row sits in exactly one place (clean or excluded).

## 5. Clean table profile

**Flags (C4):** 19,100 cancellation lines (1.9%), 5,776 non-product lines, 231,751 lines with no customer ID (22.5%), 1 R9 line.

**Net revenue by line category (C5):**

| Category | Lines | Net revenue (£) |
|---|---:|---:|
| Product | 1,023,844 | 18,927,399 |
| Shipping | 3,788 | 433,411 |
| Gift voucher | 100 | 1,687 |
| Samples | 101 | −5,991 |
| Discount | 173 | −12,880 |
| Manual adjustment | 1,462 | −75,745 |
| Fees | 152 | −264,936 |
| **Total** | **1,029,620** | **19,002,944** |

**Missing customer ID (C6):** 231,751 lines (22.5% of lines) carry £2.71m of £19.00m net revenue (**14.3%**). These lines are smaller on average (about £11.70 per line vs £20.40 for known customers). Dropping them, as many public analyses do, would understate revenue by 14.3%; R8 keeps them under an "Unknown" customer.

Open points for the metric definitions page:

- *Net revenue* (£19.00m, all lines) and *net product revenue* (£18.93m, `is_product = 1`) are different numbers. Each report must say which one it uses.
- Fees are net negative (−£264.9k). Drill-down by stock code and cancellation flag:

  | Stock code | Cancellation | Lines | Net (£) |
  |---|---:|---:|---:|
  | AMAZONFEE | 1 | 33 | −241,988 |
  | BANK CHARGES | 1 | 66 | −36,001 |
  | CRUK | 1 | 16 | −7,933 |
  | BANK CHARGES | 0 | 34 | 519 |
  | AMAZONFEE | 0 | 3 | 20,468 |

  Credit notes outweigh charges about 12 to 1 for `AMAZONFEE`, and `CRUK` has no positive lines at all. These lines behave like **costs the company paid** (marketplace fees, bank charges, charity commission) booked as credit notes, not like customers cancelling orders. *Interpretation, not documented in the source.*
  **Decision:** keep them in the clean table so every row is accounted for, but leave them out of sales KPIs. Revenue and cancellation-rate measures use `is_product = 1`. Fees are reported on their own line.

## 6. Out of scope

Stock write-offs (R4) point to an inventory-shrinkage question. With zero prices and no cost data, this dataset cannot value them in £, so they are listed under *Limitations and next steps* in the README.
