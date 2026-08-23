/* 
   APPLE RETAIL SALES & WARRANTY ANALYSIS
   FILE: business_analysis.sql
   PURPOSE: Answer 14 core business questions plus one summary
            KPI query, covering store performance, sales trends,
            product performance, pricing, and warranty analysis.
   RUN AFTER: schema.sql, eda.sql and data_quality_checks.sql)
*/

/* Q. OVERALL KPI SUMMARY
   Single-query snapshot of top-level KPIs: total revenue, total
   units sold, overall warranty claim rate, and current-year vs
   prior-year revenue growth. Intended as a quick "dashboard"
   query to anchor written findings/screenshots.
*/

WITH yearly_revenue AS (
    SELECT
        EXTRACT(YEAR FROM s.sale_date)::INT AS sales_year,
        SUM(p.price * s.quantity) AS revenue
    FROM sales AS s
    JOIN products AS p
        ON s.product_id = p.product_id
    GROUP BY sales_year
),

revenue_growth AS (
    SELECT
        sales_year,
        revenue,
        LAG(revenue) OVER (
            ORDER BY sales_year
        ) AS prior_year_revenue,

        ROUND(
            (
                (revenue - LAG(revenue) OVER (
                    ORDER BY sales_year
                ))
                * 100.0
                / NULLIF(
                    LAG(revenue) OVER (
                        ORDER BY sales_year
                    ),
                    0
                )
            )::numeric,
            2
        ) AS yoy_revenue_growth_pct

    FROM yearly_revenue
),

sales_totals AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        SUM(s.quantity) AS total_units_sold,
        SUM(p.price * s.quantity) AS total_revenue
    FROM sales AS s
    JOIN products AS p
        ON s.product_id = p.product_id
),

warranty_totals AS (
    SELECT
        COUNT(DISTINCT claim_id) AS total_warranty_claims
    FROM warranty
)

SELECT
    st.total_sales,
    st.total_units_sold,
    ROUND(st.total_revenue::numeric, 2) AS total_revenue,

    wt.total_warranty_claims,

    ROUND(
        (
            wt.total_warranty_claims * 100.0
            / NULLIF(st.total_sales, 0)
        )::numeric,
        2
    ) AS overall_warranty_claim_rate,

    rg.sales_year AS most_recent_year,

    rg.yoy_revenue_growth_pct
        AS most_recent_yoy_revenue_growth_pct

FROM sales_totals AS st
CROSS JOIN warranty_totals AS wt

LEFT JOIN revenue_growth AS rg
    ON rg.sales_year = (
        SELECT MAX(sales_year)
        FROM revenue_growth
    );


/* Q1. STORE PERFORMANCE BY COUNTRY
   Identify the top-performing store in each country based
   on total units sold. */

WITH store_sales AS (
    SELECT
        st.country,
        st.store_id,
        st.store_name,
        SUM(s.quantity) AS total_units_sold
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    GROUP BY
        st.country,
        st.store_id,
        st.store_name
)
SELECT
    country,
    store_id,
    store_name,
    total_units_sold,
    RANK() OVER (
        PARTITION BY country
        ORDER BY total_units_sold DESC
    ) AS sales_rank
FROM store_sales
ORDER BY country, sales_rank;


/* Q2. STORE YEAR-OVER-YEAR GROWTH
   Calculate year-over-year growth in units sold for each store. */

WITH yearly_sales AS (
    SELECT
        st.store_id,
        st.store_name,
        EXTRACT(YEAR FROM s.sale_date)::INT AS sales_year,
        SUM(s.quantity) AS units_sold
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    GROUP BY
        st.store_id,
        st.store_name,
        sales_year
)
SELECT
    store_id,
    store_name,
    sales_year,
    units_sold,
    LAG(units_sold) OVER (
        PARTITION BY store_id
        ORDER BY sales_year
    ) AS previous_year_units,
    ROUND(
        (
            units_sold -
            LAG(units_sold) OVER (
                PARTITION BY store_id
                ORDER BY sales_year
            )
        ) * 100.0 /
        NULLIF(
            LAG(units_sold) OVER (
                PARTITION BY store_id
                ORDER BY sales_year
            ),
            0
        ),
        2
    ) AS yoy_growth_percentage
FROM yearly_sales
ORDER BY store_id, sales_year;


/* Q3. STORE WARRANTY PERFORMANCE
   Identify stores with warranty claim rates above
   the company-wide claim rate. */

WITH store_metrics AS (
    SELECT
        st.store_id,
        st.store_name,
        st.country,
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS warranty_claims
    FROM stores AS st
    LEFT JOIN sales AS s
        ON st.store_id = s.store_id
    LEFT JOIN warranty AS w
        ON s.sale_id = w.sale_id
    GROUP BY
        st.store_id,
        st.store_name,
        st.country
),
store_rates AS (
    SELECT
        store_id,
        store_name,
        country,
        total_sales,
        warranty_claims,
        ROUND(
            warranty_claims * 100.0 /
            NULLIF(total_sales, 0),
            2
        ) AS store_claim_rate
    FROM store_metrics
),
company_rate AS (
    SELECT
        COUNT(DISTINCT w.claim_id) * 100.0 /
        NULLIF(COUNT(DISTINCT s.sale_id), 0) AS claim_rate
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON s.sale_id = w.sale_id
)
SELECT
    sr.store_id,
    sr.store_name,
    sr.country,
    sr.total_sales,
    sr.warranty_claims,
    sr.store_claim_rate,
    ROUND(cr.claim_rate, 2) AS company_claim_rate
FROM store_rates AS sr
CROSS JOIN company_rate AS cr
WHERE sr.store_claim_rate > cr.claim_rate
ORDER BY sr.store_claim_rate DESC;


/* Q4. CATEGORY REVENUE & CONTRIBUTION
   Calculate revenue and percentage contribution by category.

   NOTE: Revenue is calculated using each product's current
   catalog price (products.price), since the dataset does not
   include a historical price-at-time-of-sale table. If prices
   changed over the multi-year sales window, historical revenue
   figures below are directional estimates rather than exact
   point-in-time revenue. */

WITH category_revenue AS (
    SELECT
        c.category_name,
        SUM(p.price * s.quantity) AS total_revenue
    FROM sales AS s
    JOIN products AS p
        ON s.product_id = p.product_id
    JOIN category AS c
        ON p.category_id = c.category_id
    GROUP BY c.category_name
)
SELECT
    category_name,

    ROUND(total_revenue::numeric, 2) AS total_revenue,

    ROUND(
        (
            total_revenue * 100.0 /
            NULLIF(SUM(total_revenue) OVER (), 0)
        )::numeric,
        2
    ) AS revenue_percentage

FROM category_revenue
ORDER BY total_revenue DESC;


/* Q5. TOP 3 PRODUCTS BY COUNTRY
   Identify the top three products in each country based on
   total units sold.

   FIX: The original version ranked every product per country
   but never filtered down to the top 3, so it answered "rank
   all products" instead of "top 3 products." The WHERE clause
   below applies the missing filter. */

WITH product_sales AS (
    SELECT
        st.country,
        p.product_id,
        p.product_name,
        SUM(s.quantity) AS total_units_sold
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    JOIN products AS p
        ON s.product_id = p.product_id
    GROUP BY
        st.country,
        p.product_id,
        p.product_name
),
ranked_products AS (
    SELECT
        country,
        product_id,
        product_name,
        total_units_sold,
        ROW_NUMBER() OVER (
            PARTITION BY country
            ORDER BY total_units_sold DESC
        ) AS product_rank
    FROM product_sales
)
SELECT
    country,
    product_id,
    product_name,
    total_units_sold,
    product_rank
FROM ranked_products
WHERE product_rank <= 3
ORDER BY country, product_rank;


/* Q6. PRODUCT SALES BY PRICE SEGMENT
   Compare sales and warranty performance across price ranges. */

WITH product_metrics AS (
    SELECT
        p.product_id,
        p.price,
        CASE
            WHEN p.price < 500 THEN 'Under $500'
            WHEN p.price < 1000 THEN '$500-$999'
            WHEN p.price < 1500 THEN '$1,000-$1,499'
            ELSE '$1,500+'
        END AS price_segment,
        COUNT(DISTINCT s.sale_id) AS sales_transactions,
        COALESCE(SUM(s.quantity), 0) AS units_sold,
        COUNT(DISTINCT w.claim_id) AS warranty_claims
    FROM products AS p
    LEFT JOIN sales AS s
        ON p.product_id = s.product_id
    LEFT JOIN warranty AS w
        ON s.sale_id = w.sale_id
    GROUP BY
        p.product_id,
        p.price
)
SELECT
    price_segment,
    COUNT(*) AS product_count,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    SUM(warranty_claims) AS warranty_claims,
    ROUND(
        SUM(warranty_claims) * 100.0 /
        NULLIF(SUM(sales_transactions), 0),
        2
    ) AS warranty_claim_rate
FROM product_metrics
GROUP BY price_segment
ORDER BY MIN(price);


/* Q7. MONTHLY SALES TREND & GROWTH
   Calculate monthly sales, running totals, and MoM growth.

   NOTE: Months with zero sales for a given store simply do not
   appear as rows (there's nothing to GROUP BY), so month-over-
   month growth after a gap will reflect the jump from the last
   active month rather than a 0% baseline. This is a known
   limitation of the underlying data grain, not a query bug. */

WITH monthly_sales AS (
    SELECT
        s.store_id,
        st.store_name,
        DATE_TRUNC('month', s.sale_date) AS sales_month,
        SUM(s.quantity) AS monthly_units
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    WHERE s.sale_date >= (
        SELECT MAX(sale_date) - INTERVAL '4 years'
        FROM sales
    )
    GROUP BY
        s.store_id,
        st.store_name,
        DATE_TRUNC('month', s.sale_date)
)
SELECT
    store_id,
    store_name,
    sales_month,
    monthly_units,

    SUM(monthly_units) OVER (
        PARTITION BY store_id
        ORDER BY sales_month
    ) AS running_total_units,

    LAG(monthly_units) OVER (
        PARTITION BY store_id
        ORDER BY sales_month
    ) AS previous_month_units,

    ROUND(
        (
            monthly_units -
            LAG(monthly_units) OVER (
                PARTITION BY store_id
                ORDER BY sales_month
            )
        ) * 100.0 /
        NULLIF(
            LAG(monthly_units) OVER (
                PARTITION BY store_id
                ORDER BY sales_month
            ),
            0
        ),
        2
    ) AS mom_growth_percentage

FROM monthly_sales
ORDER BY store_id, sales_month;


/* Q8. BEST & WORST SALES MONTHS
   Identify the best and worst month for each country and year.

   NOTE: RANK() intentionally allows ties - if two months tie for
   best (or worst), both are returned. This is expected behavior,
   not a bug. */

WITH monthly_sales AS (
    SELECT
        st.country,
        EXTRACT(YEAR FROM s.sale_date)::INT AS sales_year,
        EXTRACT(MONTH FROM s.sale_date)::INT AS sales_month,
        SUM(s.quantity) AS units_sold
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    GROUP BY
        st.country,
        sales_year,
        sales_month
),
ranked_months AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country, sales_year
            ORDER BY units_sold DESC
        ) AS best_rank,
        RANK() OVER (
            PARTITION BY country, sales_year
            ORDER BY units_sold ASC
        ) AS worst_rank
    FROM monthly_sales
)
SELECT
    country,
    sales_year,
    sales_month,
    units_sold,
    CASE
        WHEN best_rank = 1 THEN 'Best Month'
        WHEN worst_rank = 1 THEN 'Worst Month'
    END AS month_performance
FROM ranked_months
WHERE best_rank = 1
   OR worst_rank = 1
ORDER BY country, sales_year, sales_month;


/* Q9. SALES SEASONALITY BY COUNTRY
   Identify months that consistently generate above-average sales. */

WITH monthly_sales AS (
    SELECT
        st.country,
        EXTRACT(MONTH FROM s.sale_date)::INT AS month_number,
        DATE_TRUNC('month', s.sale_date) AS sales_month,
        SUM(s.quantity) AS units_sold
    FROM sales AS s
    JOIN stores AS st
        ON s.store_id = st.store_id
    GROUP BY
        st.country,
        month_number,
        sales_month
),
country_average AS (
    SELECT
        country,
        AVG(units_sold) AS avg_monthly_sales
    FROM monthly_sales
    GROUP BY country
),
month_average AS (
    SELECT
        country,
        month_number,
        AVG(units_sold) AS avg_monthly_units
    FROM monthly_sales
    GROUP BY
        country,
        month_number
)
SELECT
    ma.country,
    ma.month_number,
    ROUND(ma.avg_monthly_units, 2) AS avg_monthly_units,
    ROUND(ca.avg_monthly_sales, 2) AS country_avg_monthly_sales
FROM month_average AS ma
JOIN country_average AS ca
    ON ma.country = ca.country
WHERE ma.avg_monthly_units > ca.avg_monthly_sales
ORDER BY ma.country, ma.avg_monthly_units DESC;


/* Q10. WARRANTY CLAIM TIMING
   Calculate the percentage of claims filed within
   30, 90, 180, and 365 days of the sale. */

WITH claim_timing AS (
    SELECT
        w.claim_id,
        w.claim_date - s.sale_date AS days_to_claim
    FROM warranty AS w
    JOIN sales AS s
        ON w.sale_id = s.sale_id
)
SELECT
    COUNT(*) AS total_claims,

    ROUND(
        COUNT(*) FILTER (
            WHERE days_to_claim <= 30
        ) * 100.0 / COUNT(*),
        2
    ) AS within_30_days,

    ROUND(
        COUNT(*) FILTER (
            WHERE days_to_claim <= 90
        ) * 100.0 / COUNT(*),
        2
    ) AS within_90_days,

    ROUND(
        COUNT(*) FILTER (
            WHERE days_to_claim <= 180
        ) * 100.0 / COUNT(*),
        2
    ) AS within_180_days,

    ROUND(
        COUNT(*) FILTER (
            WHERE days_to_claim <= 365
        ) * 100.0 / COUNT(*),
        2
    ) AS within_365_days

FROM claim_timing
WHERE days_to_claim >= 0;


/* Q11. HIGHEST-RISK PRODUCTS
   Identify the top 10 products by warranty claim rate.
   Only products with at least 100 sales are considered. */

SELECT
    p.product_id,
    p.product_name,
    COUNT(DISTINCT s.sale_id) AS total_sales,
    COUNT(DISTINCT w.claim_id) AS warranty_claims,
    ROUND(
        COUNT(DISTINCT w.claim_id) * 100.0 /
        COUNT(DISTINCT s.sale_id),
        2
    ) AS warranty_claim_rate
FROM products AS p
JOIN sales AS s
    ON p.product_id = s.product_id
LEFT JOIN warranty AS w
    ON s.sale_id = w.sale_id
GROUP BY
    p.product_id,
    p.product_name
HAVING COUNT(DISTINCT s.sale_id) >= 100
ORDER BY warranty_claim_rate DESC
LIMIT 10;


/* Q12. WARRANTY RISK BY PRODUCT CATEGORY
   Compare warranty claim rates across categories. */

SELECT
    c.category_name,
    COUNT(DISTINCT s.sale_id) AS total_sales,
    COUNT(DISTINCT w.claim_id) AS warranty_claims,
    ROUND(
        COUNT(DISTINCT w.claim_id) * 100.0 /
        COUNT(DISTINCT s.sale_id),
        2
    ) AS warranty_claim_rate
FROM category AS c
JOIN products AS p
    ON c.category_id = p.category_id
JOIN sales AS s
    ON p.product_id = s.product_id
LEFT JOIN warranty AS w
    ON s.sale_id = w.sale_id
GROUP BY c.category_name
ORDER BY warranty_claim_rate DESC;


/* Q13. PRODUCT LIFECYCLE SALES PERFORMANCE
   Analyze sales across product lifecycle stages:
   0-6, 6-12, 12-18, and 18+ months after launch. */

WITH lifecycle_sales AS (
    SELECT
        p.product_id,
        s.sale_id,
        s.quantity,

        CASE
            WHEN s.sale_date < p.launch_date + INTERVAL '6 months'
                THEN '0-6 Months'

            WHEN s.sale_date < p.launch_date + INTERVAL '12 months'
                THEN '6-12 Months'

            WHEN s.sale_date < p.launch_date + INTERVAL '18 months'
                THEN '12-18 Months'

            ELSE '18+ Months'
        END AS lifecycle_stage

    FROM sales AS s
    JOIN products AS p
        ON s.product_id = p.product_id

    WHERE s.sale_date >= p.launch_date
)
SELECT
    lifecycle_stage,
    COUNT(DISTINCT product_id) AS products,
    COUNT(DISTINCT sale_id) AS sales_transactions,
    SUM(quantity) AS total_units_sold,
    ROUND(AVG(quantity), 2) AS avg_units_per_transaction
FROM lifecycle_sales
GROUP BY lifecycle_stage
ORDER BY
    CASE lifecycle_stage
        WHEN '0-6 Months' THEN 1
        WHEN '6-12 Months' THEN 2
        WHEN '12-18 Months' THEN 3
        WHEN '18+ Months' THEN 4
    END;


/* Q14. PRODUCT LIFECYCLE WARRANTY RISK
   Analyze warranty claim rates across product lifecycle stages. */

WITH lifecycle_sales AS (
    SELECT
        p.product_id,
        s.sale_id,

        CASE
            WHEN s.sale_date < p.launch_date + INTERVAL '6 months'
                THEN '0-6 Months'

            WHEN s.sale_date < p.launch_date + INTERVAL '12 months'
                THEN '6-12 Months'

            WHEN s.sale_date < p.launch_date + INTERVAL '18 months'
                THEN '12-18 Months'

            ELSE '18+ Months'
        END AS lifecycle_stage

    FROM sales AS s
    JOIN products AS p
        ON s.product_id = p.product_id

    WHERE s.sale_date >= p.launch_date
),

lifecycle_warranty AS (
    SELECT
        ls.lifecycle_stage,
        ls.sale_id,
        COUNT(w.claim_id) AS warranty_claims
    FROM lifecycle_sales AS ls
    LEFT JOIN warranty AS w
        ON ls.sale_id = w.sale_id
    GROUP BY
        ls.lifecycle_stage, 
        ls.sale_id
)

SELECT
    lifecycle_stage,
    COUNT(*) AS total_sales,

    COUNT(*) FILTER (
        WHERE warranty_claims > 0
    ) AS sales_with_warranty_claims,

    ROUND(
        COUNT(*) FILTER (
            WHERE warranty_claims > 0
        ) * 100.0 / COUNT(*),
        2
    ) AS warranty_claim_rate

FROM lifecycle_warranty
GROUP BY lifecycle_stage
ORDER BY
    CASE lifecycle_stage
        WHEN '0-6 Months' THEN 1
        WHEN '6-12 Months' THEN 2
        WHEN '12-18 Months' THEN 3
        WHEN '18+ Months' THEN 4
    END;