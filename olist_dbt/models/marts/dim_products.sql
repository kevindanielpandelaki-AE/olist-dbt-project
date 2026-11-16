{{ config(materialized='table') }}

WITH

source_1 as (
	select * from {{ ref('stg_products') }}
),
source_2 as (
	select * from {{ ref('stg_product_category_translation') }}
),

product_detail as (

    select 
	product_id,
	source_1.product_category_name,
	product_category_name_english,
	product_name_lenght,
	product_description_lenght,
	product_photos_qty,
	product_weight_g,
	product_length_cm,
	product_height_cm,
	product_width_cm
     from source_1
     left join source_2
     on source_1.product_category_name = source_2.product_category_name

)
select * from product_detail 