WITH

source as (
     select * from {{ source('olist', 'olist_order_items_dataset') }}
), renamed AS (
    SELECT
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    FROM source
)
select * from renamed
