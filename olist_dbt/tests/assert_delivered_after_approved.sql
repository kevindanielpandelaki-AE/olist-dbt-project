{{ config(severity='warn') }}

select
    order_id,
    order_approved_at,
    order_delivered_carrier_date
from {{ ref('fct_orders') }}
where order_delivered_carrier_date < order_approved_at