# Findings so far

Numbers from the SQL checks (`sql/05`, `08`, `13`). Product lines only unless stated. Data period: 1 Dec 2009 to 9 Dec 2011.

## Data quality

- 1,067,371 rows received; 37,751 (3.5%) excluded, each with one logged reason; 1,029,620 in the model. Every run reconciles to zero.
- 91% of exclusions (34,335 rows) are source-file problems: a 9-day overlap between the two files and exact duplicates.
- Lines with no customer ID carry 13.6% of product revenue (14.3% of all net revenue). They are kept under an Unknown customer instead of being deleted.
- Fees (Amazon, bank, charity) are GBP -264.9k, booked as credit notes. Non-product lines are 6% of cancelled lines but 51% of cancelled value, so the cancellation rate is measured on products only.

## Revenue trend: 2011 vs 2010, same dates (1 Jan – 9 Dec)

- Product revenue rose 2.7% (£8.78m to £9.01m).
- **All of the growth came in the autumn.** January–August was flat (£5.07m both years); September–November grew 5.9% (£3.31m to £3.50m). November 2011 was the busiest month (£1.43m).
- **Fewer, bigger orders.** Orders fell 4.9% (19,885 to 18,916) while the average order rose 10.5% (£453 to £501). Customers buying rose 1.0% (4,173 to 4,215); the share ordering more than once slipped from 65.9% to 64.1%.
- **Cancellations almost doubled** as a share of sales (2.5% to 4.8%). Two products, cancelled almost in full, account for £246k of the £716k cancelled across all data (check N6 in `sql/14_story_numbers.sql`).

## Markets (all data)

- The UK brings 85.4% of product revenue; 41 other countries bring 14.5% (15.7% in 2011).
- Ireland (22%), the Netherlands (20%) and Germany (14%) make 55% of revenue outside the UK.

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
