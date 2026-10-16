# Olist dbt Project

An analytics engineering practice project: transforming the Olist Brazilian e-commerce dataset into clean, tested models with **dbt** on **BigQuery**.

> **Status:** work in progress. Currently at the staging layer (customers and orders). Marts, tests, and documentation are planned next.

## Tech stack

- dbt-core 1.12 with the dbt-bigquery adapter
- Google BigQuery (sandbox, no billing required)
- Python virtual environment
- Git and GitHub (feature branches and Pull Requests)

## Data source

This project uses the **Brazilian E-Commerce Public Dataset by Olist**, published on Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

- The dataset is released under the **CC BY-NC-SA 4.0** license. Please check the dataset page for the current terms.
- This repository is for learning and portfolio purposes only (non-commercial).
- **The raw data is not included in this repository.** Download it from Kaggle and load it into your own BigQuery project (see below).

## Project structure

```
raw (BigQuery dataset: olist_raw)
  -> staging  (views, prefix stg_)
  -> marts    (tables, planned)
```

| Layer | Folder | Materialization | Purpose |
|---|---|---|---|
| Raw | `olist_raw` dataset | n/a | Source tables loaded as-is from the Kaggle CSV files |
| Staging | `models/staging/` | view | Rename, cast, light cleaning. No joins, no business logic |
| Marts | `models/marts/` | table | Dimensional models (fact and dimension tables), planned |

Sources are declared in `models/staging/_olist__sources.yml`.

## Current models

| Model | Grain | Rows |
|---|---|---|
| `stg_customers` | one row per `customer_id` | 99,441 |
| `stg_orders` | one row per `order_id` | 99,441 |

Data note: in Olist, `customer_id` is generated per order, while the same person is identified by `customer_unique_id` (96,096 distinct values). A future customer dimension should use `customer_unique_id` as its natural key.

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

   Download the dataset from Kaggle and load these two files into `olist_raw`. The table names must match the source declarations:

   | CSV file | BigQuery table |
   |---|---|
   | `olist_customers_dataset.csv` | `olist_customers_dataset` |
   | `olist_orders_dataset.csv` | `olist_orders_dataset` |

   Skip the header row. Keep identifiers and codes as `STRING`, and the five date columns of the orders table as `TIMESTAMP`.

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

6. **Verify and build**

   Run dbt from the folder that contains `dbt_project.yml`:

   ```bash
   cd olist_dbt
   dbt debug
   dbt run
   ```

   `dbt debug` should end with `All checks passed!`. After `dbt run`, the views `stg_customers` and `stg_orders` appear in the `dbt_dev` dataset.

> **BigQuery sandbox note:** tables and views expire after 60 days. Views can be rebuilt with `dbt run`; raw tables must be reloaded from the CSV files.

## Conventions

- One change per branch (`feature/`, `fix/`, `docs/`), merged to `main` through a Pull Request. No direct commits to `main`.
- Small commits with one topic each, using prefixes such as `feat:`, `docs:`, `chore:`.
- Staging models follow the CTE pattern: `source` -> `renamed` -> `select * from renamed`.
- Raw tables are read with `source()`; other models are read with `ref()`.
- Credentials, `profiles.yml`, and raw data never enter the repository.

## Roadmap

- [x] Project setup, BigQuery connection, source declarations
- [x] Staging models: customers, orders
- [ ] Incremental models, seeds, variables
- [ ] Tests (`not_null`, `unique`, `relationships`) and documentation with lineage
- [ ] Mart layer: fact and dimension models
- [ ] Query cost optimization (partitioning and clustering)

## Author

Kevin Daniel Pandelaki, [@kevindanielpandelaki-AE](https://github.com/kevindanielpandelaki-AE)
