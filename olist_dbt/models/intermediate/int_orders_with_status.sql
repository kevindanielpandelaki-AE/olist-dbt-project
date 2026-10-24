{{ config(materialized='ephemeral') }}

WITH

orders as (
	select * from {{ ref('stg_orders') }}
),

status_mapping as (

    select * from {{ ref('order_status_mapping') }}
),

joined as (

    select
        orders.*,
        status_mapping.status_group

    from orders
    left join status_mapping 
    on orders.order_status = status_mapping.order_status
)
select * from joined

