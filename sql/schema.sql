/* APPLE RETAIL SALES & WARRANTY ANALYSIS
   FILE: schema.sql
   PURPOSE: Table creation, constraints, indexes, and data import
   DATABASE: PostgreSQL
   DATASET SOURCE: Kaggle - "Apple_Retail_Sales_Dataset"
*/

/* 1. DROP EXISTING TABLES (child tables first, FK order) */

DROP TABLE IF EXISTS warranty;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS stores;

/* 2. TABLE DEFINITIONS */

/* STORES */
CREATE TABLE stores (
    store_id    VARCHAR(10) PRIMARY KEY,
    store_name  VARCHAR(30),
    city        VARCHAR(30),
    country     VARCHAR(30)
);

/* CATEGORY */
CREATE TABLE category (
    category_id    VARCHAR(10) PRIMARY KEY,
    category_name  VARCHAR(30)
);

/* PRODUCTS */
CREATE TABLE products (
    product_id    VARCHAR(10) PRIMARY KEY,
    product_name  VARCHAR(35),
    category_id   VARCHAR(10),
    launch_date   DATE,
    price         NUMERIC(10,2),
    CONSTRAINT fk_category
        FOREIGN KEY (category_id)
        REFERENCES category(category_id)
);

/* SALES */
CREATE TABLE sales (
    sale_id     VARCHAR(10) PRIMARY KEY,
    sale_date   DATE,
    store_id    VARCHAR(10),
    product_id  VARCHAR(10),
    quantity    INT,
    CONSTRAINT fk_store
        FOREIGN KEY (store_id)
        REFERENCES stores(store_id),
    CONSTRAINT fk_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
);

/* WARRANTY */
CREATE TABLE warranty (
    claim_id       VARCHAR(10) PRIMARY KEY,
    claim_date     DATE,
    sale_id        VARCHAR(10),
    repair_status  VARCHAR(20),
    CONSTRAINT fk_sale
        FOREIGN KEY (sale_id)
        REFERENCES sales(sale_id)
);

/* 3. DATA IMPORT
   IMPORTANT:Run psql from the project's root directory, e.g.:

       psql -U your_username -d apple_retail -f sql/schema.sql

   Place the raw CSV files (downloaded from the Kaggle dataset
   "Apple_Retail_Sales_Dataset") inside a top-level `dataset/`
   folder before running this script:

       apple-retail-sales-sql-analysis/
       ├── dataset/
       │   ├── stores.csv
       │   ├── category.csv
       │   ├── products.csv
       │   ├── sales.csv
       │   └── warranty.csv
       └── sql/
           ├── schema.sql
           ├── eda.sql
           ├── data_quality_checks.sql
           └── business_analysis.sql

   Import order matters because of foreign-key dependencies:
   stores/category -> products -> sales -> warranty.
*/

\copy stores    FROM 'dataset/stores.csv'   WITH (FORMAT csv, HEADER true);
\copy category  FROM 'dataset/category.csv' WITH (FORMAT csv, HEADER true);
\copy products  FROM 'dataset/products.csv' WITH (FORMAT csv, HEADER true);
\copy sales     FROM 'dataset/sales.csv'    WITH (FORMAT csv, HEADER true);
\copy warranty  FROM 'dataset/warranty.csv' WITH (FORMAT csv, HEADER true);

/* 4. INDEXES
   The sales table is the largest and most frequently joined /
   filtered table (1M+ rows), so indexes are added on the
   foreign-key and date columns used across the EDA and business
   analysis queries. Indexes on small dimension tables (stores,
   category, products) are unnecessary since their primary keys
   are already indexed and the tables themselves are small.
*/

CREATE INDEX idx_sales_product_id ON sales(product_id);
CREATE INDEX idx_sales_store_id   ON sales(store_id);
CREATE INDEX idx_sales_sale_date  ON sales(sale_date);
CREATE INDEX idx_warranty_sale_id ON warranty(sale_id);
CREATE INDEX idx_warranty_claim_date ON warranty(claim_date);

/* Example of verifying index usage on a representative query
   (see business_analysis.sql for the full query context):

   EXPLAIN ANALYZE
   SELECT store_id, SUM(quantity)
   FROM sales
   WHERE sale_date >= '2023-01-01'
   GROUP BY store_id;

   Run this before and after creating the indexes above and
   compare the "Execution Time" and whether the planner switches
   from a Seq Scan to an Index Scan on idx_sales_sale_date.
*/


