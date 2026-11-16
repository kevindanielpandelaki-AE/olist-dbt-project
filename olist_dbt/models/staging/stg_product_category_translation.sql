WITH

source as (
     select * from {{ source('olist', 'product_category_name_translation') }}
), renamed AS (
    SELECT
        product_category_name,
        product_category_name_english
    FROM source
)
select * from renamed