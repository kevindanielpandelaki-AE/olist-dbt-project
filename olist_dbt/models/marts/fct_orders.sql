-- candidate for incremental when billing is enabled
-- (sandbox BigQuery rejects DML, so built as a plain table for now)

-- Partitioning + clustering already tried and validated (see README):
-- partition_by={'field': 'order_purchase_timestamp', 'data_type': 'timestamp', 'granularity': 'month'}
-- cluster_by=['order_status']
-- Not enabled: sandbox enforces a default table expiration <=60 days for partitioned
-- tables, and expiration is calculated from the partition column's value (not create time),
-- so partitions on Olist's historical data (2016-2018) are immediately considered expired.
-- Requires billing to override.

{{
    config(
        materialized='table'
    )
}}

with orders as (

    select * from {{ ref('int_orders_with_status') }}

),

available as (

    select * from orders 

    {% if var('excluded_status_group', none) is not none %}
    where status_group != '{{ var("excluded_status_group") }}'
    {% endif %}

)

select * from available