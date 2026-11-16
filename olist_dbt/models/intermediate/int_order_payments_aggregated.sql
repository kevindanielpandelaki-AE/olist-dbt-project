{{ config(materialized='ephemeral') }}

WITH

source as (
	select * from {{ ref('stg_order_payments') }}
),

total_payments as (

    select 
	order_id,
	sum(payment_value) as total_payment_value
     from source
     group by 
	order_id
)
select * from total_payments 