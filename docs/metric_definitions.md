# Metric definitions

Every number in the dashboard uses one of these definitions. Each definition states its scope, because the same data gives very different answers with a different scope.

| Metric | Definition | Scope | Why this scope |
|---|---|---|---|
| **Net product revenue** | Sum of `line_amount` (sales minus cancellations) | `is_product = 1` | Shipping, fees, discounts and manual adjustments are not product sales. Headline revenue KPI. |
| **Net revenue (all lines)** | Sum of `line_amount` on every clean line | All lines | Reconciles to the clean table (GBP 19,002,944). Used for reconciliation, not as a KPI. |
| **Cancellation rate (value)** | Cancelled value ÷ gross sales, where gross sales = `line_amount` on non-cancellation lines | `is_product = 1` | Non-product lines are 6% of cancellation lines but 51% of cancelled value (mostly fees booked as credit notes). Including them would roughly double the rate, from about 3.6% to 7.1%. See `data_quality.md` section 5. |

More definitions (orders, average order value, customers, retention) will be added with the Power BI measures.
