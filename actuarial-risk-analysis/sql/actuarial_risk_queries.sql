/*
   Core actuarial idea:
   - Sales transactions are the exposure base.
   - Warranty claims are the observed event count.
   - Claim frequency = claims / exposure.
   - Risk segmentation should compare groups against the portfolio average,
     while guarding against unstable results from tiny samples.

   Portfolio use:
   - Higher-rate segments are candidates for quality review and monitoring.
   - Lower-rate segments provide comparative experience benchmarks.
*/

/* Q1. Portfolio experience baseline */
WITH portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON s.sale_id = w.sale_id
)
SELECT
    total_sales,
    total_claims,
    ROUND(total_claims * 100.0 / NULLIF(total_sales, 0), 2) AS overall_claim_rate_pct,
    ROUND(total_claims * 100.0 / NULLIF(total_sales, 0), 4) AS overall_claim_rate_decimals
FROM portfolio;

/* Q2. Category-level claim experience */
WITH category_exp AS (
    SELECT
        c.category_name,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM category AS c
    JOIN products AS p
        ON p.category_id = c.category_id
    JOIN sales AS s
        ON s.product_id = p.product_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY c.category_name
),
portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
)
SELECT
    ce.category_name,
    ce.sales_exposure,
    ce.total_claims,
    ROUND(ce.total_claims * 100.0 / NULLIF(ce.sales_exposure, 0), 2) AS claim_rate_pct,
    ROUND(
        (ce.total_claims * 100.0 / NULLIF(ce.sales_exposure, 0))
        - (p.total_claims * 100.0 / NULLIF(p.total_sales, 0)),
        2
    ) AS difference_from_portfolio_pct_points
FROM category_exp AS ce
CROSS JOIN portfolio AS p
ORDER BY claim_rate_pct DESC;

/* Q3. Product-level claim risk with minimum exposure threshold */
WITH product_exp AS (
    SELECT
        p.product_id,
        p.product_name,
        c.category_name,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims,
        SUM(s.quantity) AS total_units_sold
    FROM products AS p
    JOIN category AS c
        ON c.category_id = p.category_id
    JOIN sales AS s
        ON s.product_id = p.product_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY p.product_id, p.product_name, c.category_name
),
portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
)
SELECT
    pe.product_id,
    pe.product_name,
    pe.category_name,
    pe.sales_exposure,
    pe.total_units_sold,
    pe.total_claims,
    ROUND(pe.total_claims * 100.0 / NULLIF(pe.sales_exposure, 0), 2) AS claim_rate_pct,
    ROUND(
        (pe.total_claims * 100.0 / NULLIF(pe.sales_exposure, 0))
        - (po.total_claims * 100.0 / NULLIF(po.total_sales, 0)),
        2
    ) AS difference_from_portfolio_pct_points
FROM product_exp AS pe
CROSS JOIN portfolio AS po
WHERE pe.sales_exposure >= 100
ORDER BY claim_rate_pct DESC, sales_exposure DESC
LIMIT 10;

/* Q4. Store-level risk screen */
WITH store_exp AS (
    SELECT
        st.store_id,
        st.store_name,
        st.country,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM stores AS st
    JOIN sales AS s
        ON s.store_id = st.store_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY st.store_id, st.store_name, st.country
),
portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
)
SELECT
    se.store_id,
    se.store_name,
    se.country,
    se.sales_exposure,
    se.total_claims,
    ROUND(se.total_claims * 100.0 / NULLIF(se.sales_exposure, 0), 2) AS claim_rate_pct,
    ROUND(
        (se.total_claims * 100.0 / NULLIF(se.sales_exposure, 0))
        - (po.total_claims * 100.0 / NULLIF(po.total_sales, 0)),
        2
    ) AS difference_from_portfolio_pct_points
FROM store_exp AS se
CROSS JOIN portfolio AS po
WHERE se.sales_exposure >= 100
ORDER BY claim_rate_pct DESC
LIMIT 10;

/* Q5. Country-level market risk comparison */
WITH country_exp AS (
    SELECT
        st.country,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims,
        SUM(s.quantity) AS total_units_sold
    FROM stores AS st
    JOIN sales AS s
        ON s.store_id = st.store_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY st.country
),
portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
)
SELECT
    ce.country,
    ce.sales_exposure,
    ce.total_units_sold,
    ce.total_claims,
    ROUND(ce.total_claims * 100.0 / NULLIF(ce.sales_exposure, 0), 2) AS claim_rate_pct,
    ROUND(
        (ce.total_claims * 100.0 / NULLIF(ce.sales_exposure, 0))
        - (po.total_claims * 100.0 / NULLIF(po.total_sales, 0)),
        2
    ) AS difference_from_portfolio_pct_points
FROM country_exp AS ce
CROSS JOIN portfolio AS po
ORDER BY claim_rate_pct DESC;

/* Q6. Price-segment claim behavior */
WITH price_band AS (
    SELECT
        p.product_id,
        CASE
            WHEN p.price < 500 THEN 'Under 500'
            WHEN p.price < 1000 THEN '500-999'
            WHEN p.price < 1500 THEN '1000-1499'
            ELSE '1500+'
        END AS price_segment,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims,
        SUM(s.quantity) AS total_units_sold
    FROM products AS p
    JOIN sales AS s
        ON s.product_id = p.product_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY p.product_id,
        CASE
            WHEN p.price < 500 THEN 'Under 500'
            WHEN p.price < 1000 THEN '500-999'
            WHEN p.price < 1500 THEN '1000-1499'
            ELSE '1500+'
        END
),
aggregated AS (
    SELECT
        price_segment,
        SUM(sales_exposure) AS total_sales,
        SUM(total_claims) AS total_claims,
        SUM(total_units_sold) AS total_units_sold
    FROM price_band
    GROUP BY price_segment
)
SELECT
    price_segment,
    total_sales,
    total_units_sold,
    total_claims,
    ROUND(total_claims * 100.0 / NULLIF(total_sales, 0), 2) AS claim_rate_pct
FROM aggregated
ORDER BY
    CASE price_segment
        WHEN 'Under 500' THEN 1
        WHEN '500-999' THEN 2
        WHEN '1000-1499' THEN 3
        WHEN '1500+' THEN 4
    END;

/* Q7. Claim timing distribution */
WITH claim_timing AS (
    SELECT
        w.claim_id,
        w.claim_date - s.sale_date AS days_to_claim
    FROM warranty AS w
    JOIN sales AS s
        ON s.sale_id = w.sale_id
)
SELECT
    COUNT(*) AS total_claims,
    ROUND(COUNT(*) FILTER (WHERE days_to_claim <= 30) * 100.0 / NULLIF(COUNT(*), 0), 2) AS within_30_days_pct,
    ROUND(COUNT(*) FILTER (WHERE days_to_claim <= 90) * 100.0 / NULLIF(COUNT(*), 0), 2) AS within_90_days_pct,
    ROUND(COUNT(*) FILTER (WHERE days_to_claim <= 180) * 100.0 / NULLIF(COUNT(*), 0), 2) AS within_180_days_pct,
    ROUND(COUNT(*) FILTER (WHERE days_to_claim <= 365) * 100.0 / NULLIF(COUNT(*), 0), 2) AS within_365_days_pct,
    ROUND(AVG(days_to_claim), 2) AS avg_days_to_claim,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_claim), 2) AS median_days_to_claim
FROM claim_timing
WHERE days_to_claim >= 0;

/* Q8. Product lifecycle risk analysis */
WITH lifecycle AS (
    SELECT
        s.sale_id,
        s.product_id,
        p.product_name,
        s.sale_date,
        p.launch_date,
        CASE
            WHEN s.sale_date < p.launch_date + INTERVAL '6 months' THEN '0-6 Months'
            WHEN s.sale_date < p.launch_date + INTERVAL '12 months' THEN '6-12 Months'
            WHEN s.sale_date < p.launch_date + INTERVAL '18 months' THEN '12-18 Months'
            ELSE '18+ Months'
        END AS lifecycle_stage,
        w.claim_id
    FROM sales AS s
    JOIN products AS p
        ON p.product_id = s.product_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    WHERE s.sale_date >= p.launch_date
),
agg AS (
    SELECT
        lifecycle_stage,
        COUNT(DISTINCT sale_id) AS sales_exposure,
        COUNT(DISTINCT claim_id) AS total_claims
    FROM lifecycle
    GROUP BY lifecycle_stage
)
SELECT
    lifecycle_stage,
    sales_exposure,
    total_claims,
    ROUND(total_claims * 100.0 / NULLIF(sales_exposure, 0), 2) AS claim_rate_pct
FROM agg
ORDER BY
    CASE lifecycle_stage
        WHEN '0-6 Months' THEN 1
        WHEN '6-12 Months' THEN 2
        WHEN '12-18 Months' THEN 3
        WHEN '18+ Months' THEN 4
    END;

/* Q9. Month-over-month and seasonal claim behavior */
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', s.sale_date)::DATE AS month_start,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY DATE_TRUNC('month', s.sale_date)::DATE
),
ranked AS (
    SELECT
        month_start,
        sales_exposure,
        total_claims,
        ROUND(total_claims * 100.0 / NULLIF(sales_exposure, 0), 2) AS claim_rate_pct,
        LAG(ROUND(total_claims * 100.0 / NULLIF(sales_exposure, 0), 2)) OVER (ORDER BY month_start) AS previous_month_claim_rate
    FROM monthly
)
SELECT
    month_start,
    sales_exposure,
    total_claims,
    claim_rate_pct,
    ROUND((claim_rate_pct - previous_month_claim_rate) * 100.0 / NULLIF(previous_month_claim_rate, 0), 2) AS mom_change_pct
FROM ranked
ORDER BY month_start;

/* Q10. Composite risk score for prioritisation */
WITH product_exp AS (
    SELECT
        p.product_id,
        p.product_name,
        COUNT(DISTINCT s.sale_id) AS sales_exposure,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM products AS p
    JOIN sales AS s
        ON s.product_id = p.product_id
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
    GROUP BY p.product_id, p.product_name
),
portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
),
scored AS (
    SELECT
        pe.product_id,
        pe.product_name,
        pe.sales_exposure,
        pe.total_claims,
        ROUND(pe.total_claims * 100.0 / NULLIF(pe.sales_exposure, 0), 2) AS claim_rate_pct,
        ROUND(
            (pe.total_claims * 100.0 / NULLIF(pe.sales_exposure, 0))
            - (po.total_claims * 100.0 / NULLIF(po.total_sales, 0)),
            2
        ) AS difference_from_portfolio_pct_points,
        ROUND(
            (
                ((pe.total_claims * 100.0 / NULLIF(pe.sales_exposure, 0))
                - (po.total_claims * 100.0 / NULLIF(po.total_sales, 0)))
                * SQRT(pe.sales_exposure)
            ),
            2
        ) AS composite_risk_score
    FROM product_exp AS pe
    CROSS JOIN portfolio AS po
    WHERE pe.sales_exposure >= 100
)
SELECT
    product_id,
    product_name,
    sales_exposure,
    total_claims,
    claim_rate_pct,
    difference_from_portfolio_pct_points,
    composite_risk_score
FROM scored
ORDER BY composite_risk_score DESC
LIMIT 10;

/* Q11. Scenario planning: 10%, 20%, and 30% claim growth */
WITH portfolio AS (
    SELECT
        COUNT(DISTINCT s.sale_id) AS total_sales,
        COUNT(DISTINCT w.claim_id) AS total_claims
    FROM sales AS s
    LEFT JOIN warranty AS w
        ON w.sale_id = s.sale_id
)
SELECT
    total_sales,
    total_claims,
    ROUND(total_claims * 1.10, 0) AS claims_under_10pct_growth,
    ROUND(total_claims * 1.20, 0) AS claims_under_20pct_growth,
    ROUND(total_claims * 1.30, 0) AS claims_under_30pct_growth,
    ROUND((total_claims * 1.10 * 100.0) / NULLIF(total_sales, 0), 2) AS claim_rate_10pct_growth,
    ROUND((total_claims * 1.20 * 100.0) / NULLIF(total_sales, 0), 2) AS claim_rate_20pct_growth,
    ROUND((total_claims * 1.30 * 100.0) / NULLIF(total_sales, 0), 2) AS claim_rate_30pct_growth
FROM portfolio;
