# Findings so far

Numbers from the SQL checks (`sql/05`, `08`, `13`). Product lines only unless stated. Data period: 1 Dec 2009 to 9 Dec 2011.

## Data quality

- 1,067,371 rows received; 37,751 (3.5%) excluded, each with one logged reason; 1,029,620 in the model. Every run reconciles to zero.
- 91% of exclusions (34,335 rows) are source-file problems: a 9-day overlap between the two files and exact duplicates.
- Lines with no customer ID carry 13.6% of product revenue (14.3% of all net revenue). They are kept under an Unknown customer instead of being deleted.
- Fees (Amazon, bank, charity) are GBP -264.9k, booked as credit notes. Non-product lines are 6% of cancelled lines but 51% of cancelled value, so the cancellation rate is measured on products only.

## Customers (5,853 known customers with at least one product order)

- 72.3% bought more than once: a wholesale-style customer base.
- **Wholesale customers drive the business.** Customers whose average order is GBP 500 or more (segment Wholesale) are 16.2% of customers but 54.1% of revenue. They spend about 6 times more per customer (about GBP 9,300 vs 1,500), order more often (9.4 vs 5.6 orders) and return slightly more (76.0% vs 71.6%).
- **Champions** (recent and frequent) are 1,390 customers, 24% of the base, holding about 70% of known-customer revenue.
- **Win-back opportunity:** 327 customers are lapsed but used to buy often and spend a lot. Example: customer 17850 placed 155 orders worth GBP 50.4k, then stopped buying in December 2010.

## Products (4,802 product codes)

- **Pareto holds:** 1,038 products (22%) make 79.7% of product revenue (class A). Half the catalogue (2,507 products, class C) makes 5.0%.

## Caveats

- The data has no B2B flag. The GBP 500 segment rule is a proxy based on order size, chosen from the AOV distribution.
- Recency is measured from the last date in the data, not from today.
