WITH 

source as (
	select * from {{ source('olist', 'olist_sellers_dataset')}}
),
renamed AS (
SELECT
    	seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    FROM source
)
select * from renamed