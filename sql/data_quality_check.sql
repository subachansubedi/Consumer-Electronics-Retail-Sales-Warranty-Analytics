/* 
   APPLE RETAIL SALES & WARRANTY ANALYSIS
   FILE: data_quality_checks.sql
   PURPOSE: Validate data integrity before running EDA / business
            analysis. Checks for duplicates, orphaned foreign keys,
            invalid numeric values, and out-of-range dates.
   RUN AFTER: schema.sql
*/
 
 
/* 1. Duplicate primary keys
   (Should be impossible given PK constraints, but confirms the
   import completed without silently failing/rejecting rows.) */
 
SELECT sale_id, COUNT(*)
FROM sales
GROUP BY sale_id
HAVING COUNT(*) > 1;
 
SELECT claim_id, COUNT(*)
FROM warranty
GROUP BY claim_id
HAVING COUNT(*) > 1;
 
 
/* 2. Orphaned foreign keys
   Sales referencing a store_id or product_id that doesn't exist
   in the dimension tables. */
 
SELECT s.*
FROM sales AS s
LEFT JOIN stores AS st
    ON s.store_id = st.store_id
WHERE st.store_id IS NULL;
 
SELECT s.*
FROM sales AS s
LEFT JOIN products AS p
    ON s.product_id = p.product_id
WHERE p.product_id IS NULL;
 
/* Warranty claims referencing a sale_id that doesn't exist in sales. */
 
SELECT w.*
FROM warranty AS w
LEFT JOIN sales AS s
    ON w.sale_id = s.sale_id
WHERE s.sale_id IS NULL;
 
 
/* 3. Invalid quantities
   Sales with zero, negative, or NULL quantity are not valid
   transactions and would distort sales totals if included. */
 
SELECT *
FROM sales
WHERE quantity IS NULL
   OR quantity <= 0;
 
 
/* 4. Invalid prices
   Products with a NULL, zero, or negative price would break
   revenue calculations (Q4 in business_analysis.sql). */
 
SELECT *
FROM products
WHERE price IS NULL
   OR price <= 0;
 
 
/* 5. Warranty claims filed before the purchase date
   A claim_date earlier than the corresponding sale_date is
   logically impossible and would corrupt the claim-timing
   analysis (Q10 in business_analysis.sql). */
 
SELECT
    w.claim_id,
    w.claim_date,
    s.sale_id,
    s.sale_date
FROM warranty AS w
JOIN sales AS s
    ON w.sale_id = s.sale_id
WHERE w.claim_date < s.sale_date;
 
 
/* 6. Sales recorded before the product's launch date
   A sale_date earlier than the product's launch_date is not
   possible for a legitimate transaction and would distort the
   product lifecycle analysis (Q13, Q14 in business_analysis.sql). */
 
SELECT
    s.sale_id,
    s.sale_date,
    p.product_id,
    p.launch_date
FROM sales AS s
JOIN products AS p
    ON s.product_id = p.product_id
WHERE s.sale_date < p.launch_date;
 
 
/* 7. NULL checks on key dimension columns
   Missing country/city on a store, or a missing category on a
   product, would silently drop rows out of GROUP BY results
   without an obvious warning. */
 
SELECT *
FROM stores
WHERE country IS NULL
   OR city IS NULL;
 
SELECT *
FROM products
WHERE category_id IS NULL;
 
 
/* 8. Date range sanity check
   Confirms the sales data actually covers the multi-year window
   described in the README, and flags any suspicious future-dated
   or clearly erroneous (e.g. year 1900) records. */
 
SELECT
    MIN(sale_date) AS earliest_sale,
    MAX(sale_date) AS latest_sale
FROM sales;
 
SELECT *
FROM sales
WHERE sale_date > CURRENT_DATE;
 
