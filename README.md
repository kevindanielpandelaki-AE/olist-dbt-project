# Olist dbt Project

An analytics engineering practice project: transforming the Olist Brazilian e-commerce dataset into clean, tested models with **dbt** on **BigQuery**.

> **Status:** work in progress. The project now runs a full staging -> intermediate -> marts structure: staging covers all nine Olist source tables, the intermediate layer handles order-status mapping and order-level aggregation (items, payments), and the marts layer includes a refactored order fact table (`fct_orders`) joined against those aggregates, plus a new product dimension (`dim_products`). Tests, documentation, and a BigQuery cost-optimization pass (partitioning and clustering) are in place.

## Tech stack

- dbt-core 1.12 with the dbt-bigquery adapter
- `dbt_utils` package, for composite-key uniqueness tests and range checks
- Google BigQuery (sandbox, no billing required)
- Python virtual environment
- Git and GitHub (feature branches and Pull Requests)

## Data source

This project uses the **Brazilian E-Commerce Public Dataset by Olist**, published on Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

- The dataset is released under the **CC BY-NC-SA 4.0** license. Please check the dataset page for the current terms.
- This repository is for learning and portfolio purposes only (non-commercial).
- **The raw data is not included in this repository.** Download it from Kaggle and load it into your own BigQuery project (see below).
- The only data stored in the repo is `order_status_mapping.csv`, a small mapping table written by hand (not taken from Olist).

## Project structure

```
raw (BigQuery dataset: olist_raw)
  -> staging       (views, prefix stg_)
  -> intermediate  (ephemeral, prefix int_)
  -> marts         (tables, prefix fct_ / dim_)
```

| Layer | Folder | Materialization | Purpose |
|---|---|---|---|
| Raw | `olist_raw` dataset | n/a | Source tables loaded as-is from the Kaggle CSV files |
| Seeds | `seeds/` | table | Small static lookup tables managed as code |
| Staging | `models/staging/` | view | Rename, cast, light cleaning. One model per source table. No joins, no business logic |
| Intermediate | `models/intermediate/` | ephemeral | Reusable building blocks — joins and aggregations. Compiled into the calling model as a CTE, so no object is created in BigQuery |
| Marts | `models/marts/` | table | Analytics-ready fact and dimension models for consumption |

Sources are declared in `models/staging/_olist__sources.yml`.

## Current models

| Model | Type | Grain | Notes |
|---|---|---|---|
| `order_status_mapping` | seed | one row per `order_status` | Groups 8 order statuses into 3 status groups |
| `stg_customers` | staging | one row per `customer_id` | |
| `stg_orders` | staging | one row per `order_id` | |
| `stg_order_items` | staging | one row per `(order_id, order_item_id)` | `order_item_id` is a per-order sequence, not globally unique |
| `stg_order_payments` | staging | one row per `(order_id, payment_sequential)` | Orders can have split/installment payments |
| `stg_order_reviews` | staging | one row per `(review_id, order_id)` | A `review_id` can map to more than one `order_id` |
| `stg_products` | staging | one row per `product_id` | |
| `stg_sellers` | staging | one row per `seller_id` | |
| `stg_geolocation` | staging | not unique by design | Many coordinate points share a `geolocation_zip_code_prefix`; only `not_null` is enforced |
| `stg_product_category_translation` | staging | one row per `product_category_name` | English translation of the category name |
| `int_orders_with_status` | intermediate | one row per `order_id` | Joins `stg_orders` to the status-mapping seed |
| `int_order_items_aggregated` | intermediate | one row per `order_id` | Item count and price/freight totals per order |
| `int_order_payments_aggregated` | intermediate | one row per `order_id` | Total payment value per order, across installments |
| `fct_orders` | mart | one row per `order_id` | Joins order status, item aggregates, and payment aggregates |
| `dim_products` | mart | one row per `product_id` | Joins product attributes to the English category translation |

**Status mapping.** The seed groups the eight Olist order statuses into three groups: `completed` (`delivered`), `failed` (`canceled`, `unavailable`), and `in_progress` (`shipped`, `invoiced`, `processing`, `created`, `approved`). `int_orders_with_status` joins it to `stg_orders` with a left join, so an order with an unmapped status is kept (with a NULL group) instead of being dropped.

**Variable.** `fct_orders` accepts an optional `excluded_status_group` variable. The default is `null`, so a normal `dbt run` returns all rows. To exclude a group for a single run:

```bash
dbt run --select fct_orders --vars '{excluded_status_group: "failed"}'
```

Note that this filter uses `!=`, so rows with a NULL `status_group` are also excluded when the variable is set.

**Grain verification.** Several staging models look like they should be unique on a single column but aren't — `order_item_id`, the payments' `order_id`, and `review_id` are all per-order or per-row sequence values, not global identifiers. Each case was confirmed with a failing `unique` test, then investigated with a manual BigQuery query before settling on the correct composite grain and testing it with `dbt_utils.unique_combination_of_columns`. The practice: verify grain from the data, never assume it from the column name.

**Data note.** In Olist, `customer_id` is generated per order, while the same person is identified by `customer_unique_id` (96,096 distinct values). A future customer dimension should use `customer_unique_id` as its natural key.

**Known data gap.** In `dim_products`, `product_category_name` and `product_category_name_english` have a small number of NULLs (610 and 623 rows respectively) — some products carry a category name with no matching entry in the translation table. These columns are tested with `severity: warn` rather than failing the build, since the gap is a property of the source data, not a modeling error.

## BigQuery cost optimization

BigQuery charges on-demand queries by **bytes scanned**, not by execution time. This project explored two techniques to reduce that: partitioning and clustering.

**Partitioning and clustering — tried and validated, not currently live.** `fct_orders` was configured with:

```python
partition_by={'field': 'order_purchase_timestamp', 'data_type': 'timestamp', 'granularity': 'month'}
cluster_by=['order_status']
```

BigQuery confirmed the table was correctly built as `Partitioned by: MONTH` on `order_purchase_timestamp` and `Clustered by: order_status` (verified in the BigQuery console, Table Details tab). However, this configuration is **not active in the current model**, because:

- The BigQuery sandbox enforces a default table expiration of 60 days or less, with no way to disable it without enabling billing.
- For a time-partitioned table, expiration is calculated from the **partition column's value**, not from when the table was created.
- Since Olist's order dates are from 2016–2018, every partition is immediately considered "expired" the moment the table is built, wiping all rows.

The validated config is kept as a comment in `models/marts/fct_orders.sql` for reference, and the model currently runs as a plain table (`materialized='table'`). Revisiting this is tracked in the Roadmap below.

**Query cost impact, measured with dry run.** With `fct_orders` as a plain (non-partitioned) table, a filtered query and an unfiltered query over the same table process an identical number of bytes:

| Query | Bytes processed |
|---|---|
| `SELECT * FROM fct_orders WHERE order_purchase_timestamp BETWEEN '2018-03-01' AND '2018-03-31' AND order_status = 'delivered'` | 12.29 MB |
| `SELECT * FROM fct_orders` (no filter) | 12.29 MB |

This confirms a key BigQuery principle: a `WHERE` clause only reduces bytes scanned (and therefore cost) when the table is partitioned or clustered on the filtered column(s). On a plain table, BigQuery still reads every selected column across every row before applying the filter.

**Note on dry run and caching.** A dry run can report `0 B` not because a query is free, but because BigQuery served an identical query from its 24-hour result cache. Disable caching (`Query settings` -> uncheck "Use cached results" in the console, or `bq query --nouse_cache`) to get an honest estimate.

**`dbt build`.** Running `dbt build` executes seeds, models, and tests together in DAG order with fail-fast behavior: if a model fails its tests, dbt skips building anything downstream of it in the same run, rather than building the full DAG first and only surfacing failures at the end.

## How to run this project

**Prerequisites:** Python 3, Git, a Google account, and the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install).

1. **Clone the repo and create a virtual environment**

   ```bash
   git clone https://github.com/kevindanielpandelaki-AE/olist-dbt-project.git
   cd olist-dbt-project
   python -m venv .venv
   source .venv/Scripts/activate      # Git Bash on Windows
   # .venv\Scripts\Activate.ps1       # PowerShell
   # source .venv/bin/activate        # macOS / Linux
   pip install dbt-bigquery
   ```

2. **Create a GCP project (BigQuery sandbox) and a dataset**

   Create a project in the [Google Cloud console](https://console.cloud.google.com/), then create a dataset named `olist_raw` in location `US`.

3. **Load the raw tables**

   Download the dataset from Kaggle and load these files into `olist_raw`. The table names must match the source declarations in `models/staging/_olist__sources.yml`:

   | CSV file | BigQuery table |
   |---|---|
   | `olist_customers_dataset.csv` | `olist_customers_dataset` |
   | `olist_orders_dataset.csv` | `olist_orders_dataset` |
   | `olist_order_items_dataset.csv` | `olist_order_items_dataset` |
   | `olist_order_payments_dataset.csv` | `olist_order_payments_dataset` |
   | `olist_order_reviews_dataset.csv` | `olist_order_reviews_dataset` |
   | `olist_products_dataset.csv` | `olist_products_dataset` |
   | `olist_sellers_dataset.csv` | `olist_sellers_dataset` |
   | `olist_geolocation_dataset.csv` | `olist_geolocation_dataset` |
   | `product_category_name_translation.csv` | `product_category_name_translation` |

   Skip the header row for every file (for the smaller files, BigQuery's schema auto-detect can miss the header — if columns come in as `string_field_0`, `string_field_1`, etc., delete the table and re-upload with a manually defined schema and "Header rows to skip = 1"). For `olist_order_reviews_dataset.csv`, enable "Allow quoted newlines" in the Advanced Options, since the free-text review columns contain embedded commas and line breaks. Keep identifiers and codes as `STRING`, and the five date columns of the orders table as `TIMESTAMP`.

4. **Authenticate**

   ```bash
   gcloud auth application-default login
   gcloud config set project <your-gcp-project-id>
   ```

   Approve all requested permissions on the consent screen.

5. **Create your dbt profile**

   dbt reads connection settings from `~/.dbt/profiles.yml` (outside the repo, never committed). Create it with:

   ```yaml
   olist_dbt:
     target: dev
     outputs:
       dev:
         type: bigquery
         method: oauth
         project: <your-gcp-project-id>
         dataset: dbt_dev
         threads: 4
         location: US
   ```

6. **Install packages, verify, and build**

   Run dbt from the folder that contains `dbt_project.yml`:

   ```bash
   cd olist_dbt
   dbt deps
   dbt debug
   dbt build
   ```

   `dbt debug` should end with `All checks passed!`. `dbt deps` installs `dbt_utils`, used by several composite-grain tests. `dbt build` runs seeds, models, and tests together in DAG order — after it finishes, the staging views, the `fct_orders` and `dim_products` tables, and their tests all appear under the `dbt_dev` dataset. The intermediate models (`int_*`) do not appear as objects in BigQuery because they are ephemeral.

> **BigQuery sandbox notes**
> - Tables and views expire after 60 days. Views can be rebuilt with `dbt run`; raw tables must be reloaded from the CSV files.
> - The sandbox rejects DML statements (`MERGE`, `INSERT`, `UPDATE`, `DELETE`). Incremental models and snapshots rely on DML, so they cannot run here without enabling billing. Seeds work in the sandbox.

## Conventions

- One change per branch (`feature/`, `fix/`, `docs/`), merged to `main` through a Pull Request. No direct commits to `main`.
- Small commits with one topic each, using prefixes such as `feat:`, `docs:`, `chore:`.
- Staging models follow the CTE pattern: `source` -> `renamed` -> `select * from renamed`.
- Raw tables are read with `source()`; seeds and other models are read with `ref()`.
- Credentials, `profiles.yml`, and raw data never enter the repository.

## Roadmap

- [x] Project setup, BigQuery connection, source declarations
- [x] Staging models for all nine Olist source tables
- [x] Seed, ephemeral intermediate models (order status, item aggregation, payment aggregation), `fct_orders`, project variable
- [x] Mart layer refactored into staging -> intermediate -> mart, 3-layer structure; `dim_products` added
- [ ] Incremental model on BigQuery (requires billing; the incremental pattern was verified separately on a local PostgreSQL instance)
- [x] Tests (`not_null`, `unique`, `dbt_utils.unique_combination_of_columns`, `accepted_range`, `relationships`, singular tests) and documentation with lineage
- [ ] Customer and seller dimensions (`dim_customers`, `dim_sellers`) — deferred until there's a concrete enrichment need beyond the raw staging columns
- [x] Query cost optimization explored: partitioning and clustering validated in BigQuery, query cost estimation (dry run) measured, `dbt build` adopted; partitioning/clustering not live pending billing (see "BigQuery cost optimization" above)

## Author

Kevin Daniel Pandelaki, [@kevindanielpandelaki-AE](https://github.com/kevindanielpandelaki-AE)
