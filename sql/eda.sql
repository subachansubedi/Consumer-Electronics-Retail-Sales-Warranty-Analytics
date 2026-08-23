
/*
   APPLE RETAIL SALES & WARRANTY ANALYSIS
   FILE: eda.sql
   PURPOSE: Exploratory data analysis - dataset shape, distributions,
            pricing, sales volume, and warranty overview.
   RUN AFTER: schema.sql (and, ideally, data_quality_checks.sql)
*/
 
 
/* Q1. Dataset Overview
   Count records in each table. */
 
SELECT 'stores' AS table_name, COUNT(*) AS record_count
FROM stores
 
UNION ALL
 
SELECT 'category', COUNT(*)
FROM category
 
UNION ALL
 
SELECT 'products', COUNT(*)
FROM products
 
UNION ALL
 
SELECT 'sales', COUNT(*)
FROM sales
 
UNION ALL
 
SELECT 'warranty', COUNT(*)
FROM warranty;
 
 
/* Q2. Store & Geographic Distribution
   Count stores by country. */
 
SELECT
    country,
    COUNT(*) AS store_count
FROM stores
GROUP BY country
ORDER BY store_count DESC;
 
 
/* Count stores by city within each country. */
 
SELECT
    country,
    city,
    COUNT(*) AS store_count
FROM stores
GROUP BY country, city
ORDER BY country, store_count DESC;
 
 
/* Q3. Product Catalog Overview
   Count total products and categories. */
 
SELECT
    (SELECT COUNT(*) FROM products) AS total_products,
    (SELECT COUNT(*) FROM category) AS total_categories;
 
 
/* Products by category. */
 
SELECT
    c.category_name,
    COUNT(p.product_id) AS product_count
FROM category AS c
LEFT JOIN products AS p
    ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY product_count DESC;
 
 
/* Q4. Product Pricing & Launch Trends
   Calculate price statistics. */
 
SELECT
    MIN(price) AS minimum_price,
    MAX(price) AS maximum_price,
    ROUND(AVG(price), 2) AS average_price
FROM products;
 
 
/* Products launched by year. */
 
SELECT
    EXTRACT(YEAR FROM launch_date) AS launch_year,
    COUNT(*) AS products_launched
FROM products
GROUP BY launch_year
ORDER BY launch_year;
 
 
/* Q5. Sales Overview & Trends
   Overall sales statistics. */
 
SELECT
    COUNT(*) AS total_transactions,
    SUM(quantity) AS total_units_sold,
    ROUND(AVG(quantity), 2) AS avg_units_per_transaction
FROM sales;
 
 
/* Sales by year. */
 
SELECT
    EXTRACT(YEAR FROM sale_date) AS sale_year,
    COUNT(*) AS transactions,
    SUM(quantity) AS units_sold
FROM sales
GROUP BY sale_year
ORDER BY sale_year;
 
 
/* Q6. Warranty Overview
   Total warranty claims. */
 
SELECT
    COUNT(*) AS total_warranty_claims
FROM warranty;
 
 
/* Warranty claims by repair status. */
 
SELECT
    repair_status,
    COUNT(*) AS claim_count
FROM warranty
GROUP BY repair_status
ORDER BY claim_count DESC;
 
 
/* Warranty claims with percentage by status. */
 
SELECT
    repair_status,
    COUNT(*) AS claim_count,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_claims
FROM warranty
GROUP BY repair_status
ORDER BY claim_count DESC;
 
