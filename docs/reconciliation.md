# Reconciliation: Power BI measures vs SQL

Every Power BI measure was checked against the number the SQL checks produced. All match.

| Measure (Power BI) | Power BI | SQL | SQL check |
|---|---:|---:|---|
| Net Amount (All Lines) | £19,002,944.28 | 19,002,944.278 | C5, V2 |
| Net Revenue (products) | £18,927,399.07 | 18,927,399.067 | C5, S7, V3 |
| Gross Sales | £19,643,861.64 | 19,643,861.637 | product gross sales |
| Cancelled Value | £716,462.57 | 716,462.570 | product cancellations |
| Cancellation Rate | 3.6% | 716,462.57 ÷ 19,643,861.64 = 3.65% | derived |
| Active Customers | 5,853 | 5,853 | V6 |
| Repeat Customers | 4,234 | 4,234 | V6 |
| Unknown Customer Revenue % | 13.6% | 2,568,806.36 ÷ 18,927,399.07 = 13.57% | V3 |
| Rows Received / In Model / Excluded | 1,067,371 / 1,029,620 / 37,751 | same | V4, C1 |

New from Power BI (no SQL equivalent yet): 41,358 orders and an average order value of £474.97.

Note: the order-level AOV (£474.97 = gross sales ÷ all orders) is higher than the median customer's AOV (£277.81, check V7), because large customers place more orders and so weigh more in the overall average.
