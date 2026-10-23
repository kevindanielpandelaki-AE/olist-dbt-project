-- candidate for incremental when billing is enabled
-- (sandbox BigQuery menolak DML, jadi sementara dibangun sebagai table biasa)

with orders as (

    select * from {{ ref('int_orders_with_status') }}

)

select * from orders