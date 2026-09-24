# External Analysis for the Retail Warranty Dataset

## 1. What this analysis focuses on
The project treats sales transactions as exposure and warranty claims as observed events. It then compares different groups against the broader portfolio benchmark to identify areas with unusually high claim experience.

The scope is descriptive risk analysis rather than pricing, reserving, or causal inference. It addresses:

- Which products show the highest claim experience?
- Which categories are riskier than the portfolio average?
- Which stores or countries need operational follow-up?
- Are claims concentrated early in the product life cycle?
- Do high-price products behave differently from lower-price products?
- How do seasonal patterns affect claim experience?
- What happens under a moderate adverse scenario if claims rise by 10% to 30%?

## 2. Analytical approach

The analysis adds the following actuarial-style techniques:

- Exposure-aware comparisons
- Minimum exposure thresholds for credible analysis
- Portfolio benchmarking
- Relative risk scoring
- Lifecycle analysis
- Claim timing analysis
- Month-over-month interpretation
- Stress testing for adverse scenarios


## 3. Included SQL analysis

The SQL file contains 11 queries covering:

1. Overall portfolio claim rate
2. Category-level claim experience
3. Product-level claim experience with minimum exposure threshold
4. Store-level risk screen
5. Country-level market comparison
6. Price-band claim behavior
7. Warranty claim timing distribution
8. Product lifecycle risk by maturity stage
9. Month-over-month claim rate movement
10. Composite product prioritisation score
11. Stress test for claim growth scenarios

The queries produce exposure-adjusted metrics intended for portfolio review and risk monitoring.

## 4. Included Python analysis

The Python script reads the CSVs and produces risk tables and summary outputs in the `outputs/` folder. It includes:

- portfolio baseline summary
- category, product, store, and country claim-rate comparisons
- relative risk scoring vs. the portfolio average
- claim timing buckets
- lifecycle-stage analysis
- monthly claim trends
- simple adverse scenario testing

Outputs generated are:

- `actuarial_summary.csv`
- `risk_by_category.csv`
- `top_risky_products.csv`
- `risk_by_store.csv`
- `risk_by_country.csv`
- `risk_by_price_segment.csv`
- `risk_by_lifecycle_stage.csv`
- `monthly_claim_trends.csv`
- `claim_timing.csv`
- `risk_score_summary.csv`
- `stress_test_results.csv`

## 5. Data assumptions

This project is built around three main assumptions:

- Each sale is an exposure unit.
- Each warranty claim is an observed claim event linked to a sale.
- The project is an experience-analysis exercise, not a final actuarial pricing or reserving model.

The dataset does not provide actual repair cost, paid losses, or reserve development data. That means this project focuses on claim frequency, exposure, and relative risk rather than severity or reserve estimation.

## 6. SQL execution

With PostgreSQL configured and the source CSVs stored in `dataset/`, run:

```bash
psql -U your_username -d apple_retail -f actuarial_risk_queries.sql
```

## 7. Python execution

From the analysis directory:

```bash
pip install pandas
python actuarial_internship_analysis.py
```

This will generate outputs in the `outputs/` directory.
