{{ config(materialized='ephemeral') }}

WITH

source as (
	select * from {{ ref('stg_order_items') }}
),

total_orders as (

    select 
	order_id,
	count(order_item_id) as total_items,
	sum(price) as total_price,
	sum(freight_value) as total_freight 
     from source
     group by 
	order_id
)
select * from total_orders 
