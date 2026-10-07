# Metric definitions

Every number in the dashboard uses one of these definitions. Each definition states its scope, because the same data gives very different answers with a different scope.

| Metric | Definition | Scope | Why this scope |
|---|---|---|---|
| **Net product revenue** | Sum of `line_amount` (sales minus cancellations) | `is_product = 1` | Shipping, fees, discounts and manual adjustments are not product sales. Headline revenue KPI. |
| **Net revenue (all lines)** | Sum of `line_amount` on every clean line | All lines | Reconciles to the clean table (GBP 19,002,944). Used for reconciliation, not as a KPI. |
| **Cancellation rate (value)** | Cancelled value ÷ gross sales, where gross sales = `line_amount` on non-cancellation lines | `is_product = 1` | Non-product lines are 6% of cancellation lines but 51% of cancelled value (mostly fees booked as credit notes). Including them would roughly double the rate, from about 3.6% to 7.1%. See `data_quality.md` section 5. |
| **Orders** | Count of distinct invoice numbers with at least one non-cancelled product line | `is_product = 1`, not cancelled | An order is an invoice; credit notes are not orders |
| **Average order value (AOV)** | Gross product sales ÷ orders | `is_product = 1` | Uses gross sales so a later cancellation does not shrink the original order |
| **Repeat customer** | Known customer with 2 or more orders | Known customers | Basis for retention (business question 4) |
| **Days since last purchase** | Days from the customer's last non-cancelled product purchase to the last date in the data (9 Dec 2011) | Known customers | The data is historical, so recency is measured from the end of the data, not from today |
| **Segment (Wholesale / Retail)** | Wholesale = lifetime AOV of GBP 500 or more; otherwise Retail | Known customers with at least one product order | The data has no B2B flag, so order size is the proxy. GBP 500 is chosen from the AOV distribution (check V8): 16% of customers above it hold 54% of revenue |
| **RFM scores** | R and M = quintiles (`NTILE(5)`) of days since last purchase and lifetime net revenue; F = fixed bands of orders (1, 2, 3-4, 5-9, 10+). 5 = best | Known customers with at least one product order | F uses fixed bands because many customers share the same order count, and quintiles would split them at random |
| **RFM segment** | Champions (R≥4, F≥4) · At risk (R≤2, F≥3) · Loyal (F≥3) · New or promising (R≥4) · Hibernating (R≤2) · Needs attention (the rest), checked in that order | As above | Plain labels a marketing team can act on |
| **Win-back target** | At risk and M≥4: used to buy often, spent a lot, has not bought recently | As above | The action list for a reactivation campaign |
| **ABC class** | Products ranked by lifetime net revenue: first 80% of revenue = A, next 15% = B, rest = C | `is_product = 1` | Pareto view for merchandising: which products must never run out |

Lifetime columns (orders, net revenue, AOV) describe a customer over the whole data period and do not change with report filters. They are used to group customers; revenue for a chosen period is a Power BI measure.

These definitions live in one place, the reporting views (`sql/12_rpt_views.sql`), so every report uses the same logic. More definitions will be added with the Power BI measures.
