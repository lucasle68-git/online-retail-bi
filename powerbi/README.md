# Power BI

- [`online_retail_bi.pbix`](online_retail_bi.pbix): the report (4 pages, import mode, data as of the last pipeline run)
- [`online_retail_bi.pdf`](online_retail_bi.pdf): the same report as a PDF
- [`theme.json`](theme.json): colours and fonts

## Measures

All DAX measures live in one file, [`tmdl/all_measures.tmdl`](tmdl/all_measures.tmdl).
To deploy: Power BI Desktop → TMDL view → new tab → paste the whole file → Preview → Apply.
Before the first deploy, create the `Reconciliation` table with [`reconciliation_table.dax`](reconciliation_table.dax) (Modeling → New table).

89 measures, grouped by display folder: `0 Core` holds the business numbers reused everywhere; `1`–`4` hold what each report page shows (card text, colours, page-specific ratios).


## 0 Core › Revenue

| Measure | What it is |
| --- | --- |
| Net Revenue | Net product revenue (fees excluded). All data: £18,927,399 |
| Net Amount (All Lines) | Every line incl. fees; reconciliation only. All data: £19,002,944 |
| Gross Sales | Product sales before cancellations |
| Cancelled Value | Value of cancelled product lines |
| Cancellation Rate | Cancelled value / gross sales |

## 0 Core › Orders & Customers

| Measure | What it is |
| --- | --- |
| Orders | Distinct product invoices, cancellations excluded |
| Average Order Value | Gross sales per order (pooled) |
| Units Sold | Units on non-cancelled product lines |
| Active Customers | Known customers who bought. All data: 5,853 |
| Repeat Customers | Customers with 2+ orders. All data: 4,234 |
| Repeat Customer Rate | Repeat customers / active customers. All data: 72.3% |
| Unknown Customer Revenue % | Share of revenue with no customer ID. All data: 13.6% |

## 0 Core › Time intelligence

| Measure | What it is |
| --- | --- |
| Has Full Prior Year | TRUE when the prior year has data from its first day (guards every YoY) |
| Net Revenue PY | Like-for-like prior year (stops at the last sale date) |
| Orders PY | Like-for-like prior year |
| Average Order Value PY | Like-for-like prior year |
| Cancellation Rate PY | Like-for-like prior year |
| Active Customers PY | Like-for-like prior year |
| Net Revenue YoY % | 2011: +2.7% |
| Orders YoY % | 2011: -4.9% |
| Average Order Value YoY % | 2011: +10.5% |
| Active Customers YoY % | 2011: +1.0% |
| Net Revenue YTD | Year to date |
| Net Revenue Rolling 3M | Last 3 months up to the latest date in context |

## 1 Overview › KPI cards

| Measure | What it is |
| --- | --- |
| Orders Display | Card value as text so it is not shortened to 19K |
| Average Order Value Display | Card value as text: £501 |
| Active Customers Display | Card value as text (also used on page 3) |
| Cancellation Rate Display | Card value as text |
| KPI Revenue Note | 2011: ▲ 2.7% vs 2010 (£8.78m) |
| KPI Orders Note | 2011: ▼ 4.9% vs 2010 (19,885) |
| KPI AOV Note | 2011: ▲ 10.5% vs 2010 (£453) |
| KPI Customers Note | 2011: ▲ 1.0% vs 2010 · 64% ordered again |
| KPI Cancellation Note | 2011: Up from 2.5% in 2010 |

## 1 Overview › KPI colours

| Measure | What it is |
| --- | --- |
| KPI Colour Revenue | Green up, orange down, grey with no prior year |
| KPI Colour Orders | Overview Orders card: orange when orders fall |
| KPI Colour AOV | Overview AOV card: green when the average order grows |
| KPI Colour Customers | Overview Customers card: green when customers grow |
| KPI Colour Cancellation | Orange when the cancellation rate goes UP |

## 1 Overview › Market split

| Measure | What it is |
| --- | --- |
| Revenue Share % | Market share of revenue. 2011: UK 84.2%, International 15.7% |
| Countries Abroad | Countries outside the UK with sales (also used on page 2) |
| Market Subtitle | Subtitle of Where revenue comes from |

## 2 Markets & Products › KPI cards

| Measure | What it is |
| --- | --- |
| International Revenue | All data: £2.75m |
| International Share % | All data: 14.5% |
| KPI International Note | £2.75m from 41 countries |
| Top Market Abroad | Ireland |
| KPI Top Market Note | £603k · 22% of revenue outside the UK |
| Products Sold | Stock codes with sales, fees excluded. All data: 4,802 |
| Products Sold Display | Card value as text |
| KPI Products Note | Page 2 Products card note |
| Class A Products | Best sellers. All data: 1,038 |
| Class A Products Display | Card value as text |
| KPI Class A Note | 22% of products, 80% of revenue |

## 2 Markets & Products › Charts

| Measure | What it is |
| --- | --- |
| Product Count Share % | ABC pair, Products bar: A 22% · B 26% · C 52% |
| Revenue Share by Class % | ABC pair, Revenue bar: A 80% · B 15% · C 5% |
| Country Bar Colour | Top 10 countries chart: top 3 blue, rest grey |
| Cancel Row Colour | Cancelled products table: orange when over 90% cancelled |

## 3 Customers › KPI cards

| Measure | What it is |
| --- | --- |
| Wholesale Revenue Share % | All data: 54.1% |
| KPI Wholesale Note | They are 16.2% of customers |
| KPI Repeat Note | 4,234 customers with 2+ orders |
| KPI Known Customers Note | Page 3 Customers card note |
| Win-back Customers | Lapsed, frequent, high-value customers. All data: 327 |
| KPI Win-back Note | Page 3 Win-back card note |

## 3 Customers › Charts

| Measure | What it is |
| --- | --- |
| Customer Share % | Wholesale 16.2% · Retail 83.8% |
| Revenue Share by Segment % | Wholesale 54.1% · Retail 45.9% |
| Avg Customer Order Value | Average of each customer's own average order: Wholesale £1,072 · Retail £251 |
| Orders per Customer | Wholesale 9.4 · Retail 5.6 |
| RFM Bar Colour | RFM bar charts: Champions blue, At risk orange, others grey |
| RFM Row Colour | Text colour for an RFM table (kept as an option; the page uses RFM Bar Colour) |

## 4 Data Quality › Pipeline

| Measure | What it is |
| --- | --- |
| Rows Received | Rows read from the two source files: 1,067,371 |
| Rows In Model | Rows in the Sales fact table: 1,029,620 |
| Rows Excluded | Received minus rows in the model: 37,751 |
| Last Refreshed Label | Header label on every page |

## 4 Data Quality › KPI cards

| Measure | What it is |
| --- | --- |
| Removed With Reason | Rows excluded by a named rule (R0-R5). Expect 37,751 |
| Rows or Pounds Lost | Rows not explained by a rule + pounds that differ from the database. Expect 0 |
| Rows Received Display | Card value as text: 1,067,371 |
| Rows Excluded Display | Card value as text: 37,751 |
| Rows or Pounds Lost Display | Card value as text: 0 |
| Refresh Duration Display | Seconds taken by the last successful pipeline run |
| KPI Received Note | Page 4 Rows received card note |
| KPI Excluded Note | 3.5% of rows · 91% were duplicate copies |
| KPI Lost Note | Page 4 Rows or pounds lost card note |
| KPI Refresh Note | The pipeline view only keeps succeeded runs |
| KPI Lost Colour | Green when nothing is lost, orange otherwise |

## 4 Data Quality › Reconciliation

| Measure | What it is |
| --- | --- |
| Recon Report Value | The number as Power BI calculates it |
| Recon Database Value | Rows 2 and 5 come live from etl.run_log; rows 1, 3, 4 from the SQL checks |
| Recon Report Display | Report value formatted: £ for money rows, #,0 for counts |
| Recon Database Display | Database value formatted the same way |
| Recon Status | Same when report and database differ by less than 1p |
| Recon Status Colour | Green for Same, orange for Different |
