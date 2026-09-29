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

Revenue on lines with no customer ID: **£2.64m of £19.29m (13.7%)**, preliminary (before de-duplication). Dropping these rows, as many public analyses do, would understate revenue by roughly this share.

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
| R8 | Missing customer ID | 243,007 lines, ≈13.7% of revenue | **Keep**, map to customer key `-1` ("Unknown") | Revenue stays complete; excluded only from customer analysis (question 4) |
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

## 4. Processing order and expected reconciliation

Rules are applied in this order, and each step's row count is written to `dq.issue_log` and checked in step 6:

1. Start: 1,067,371 rows in staging.
2. R1: exclude the file-2 copy of 1–9 Dec 2010 (−22,523).
3. R2: exclude remaining exact duplicates. Expected −11,812 (= 34,335 − 22,523), to be confirmed.
4. R3, R4, R5: exclude bad-debt, stock write-off and test lines (counts re-measured after de-duplication).
5. Everything else loads into the sales fact, with flags from R6–R10.

Check: `staging rows = fact rows + excluded rows`, with zero difference.

## 5. Out of scope

Stock write-offs (R4) point to an inventory-shrinkage question. With zero prices and no cost data, this dataset cannot value them in £, so they are listed under *Limitations and next steps* in the README.
