"""Generate  warranty experience outputs from project CSV files.

The analysis uses sales as exposure and warranty claims as observed events.
Results cover portfolio benchmarking, segment comparisons, claim timing,
product lifecycle, seasonality, prioritisation, and scenario testing.
"""

from __future__ import annotations
import math
from pathlib import Path

import pandas as pd

DATA_DIR = Path("dataset")
OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(exist_ok=True, parents=True)


def load_tables() -> dict[str, pd.DataFrame]:
    """Load the source CSV files required for the actuarial analysis."""
    files = {
        "stores": DATA_DIR / "stores.csv",
        "category": DATA_DIR / "category.csv",
        "products": DATA_DIR / "products.csv",
        "sales": DATA_DIR / "sales.csv",
        "warranty": DATA_DIR / "warranty.csv",
    }
    tables = {name: pd.read_csv(path) for name, path in files.items()}
    for name in ("stores", "category", "products"):
        tables[name].columns = [
            column.strip().lower().replace(" ", "_") for column in tables[name].columns
        ]
    return tables


def prepare_master_table(tables: dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Merge the source tables and create features.
    Key fields created here:
    - has_claim: whether the sale had a warranty claim
    - days_to_claim: claim delay in days
    - sale_month: month of sale to support seasonality analysis
    - lifecycle_stage: product age at sale using launch_date
    - price_segment: price bands useful for reviewing product risk by segment
    """
    stores = tables["stores"].copy()
    categories = tables["category"].copy()
    products = tables["products"].copy()
    sales = tables["sales"].copy()
    warranty = tables["warranty"].copy()

    sales["sale_date"] = pd.to_datetime(sales["sale_date"], dayfirst=True)
    products["launch_date"] = pd.to_datetime(products["launch_date"], dayfirst=True)
    warranty["claim_date"] = pd.to_datetime(warranty["claim_date"], dayfirst=True)

    sales_df = sales.merge(stores, on="store_id", how="left")
    sales_df = sales_df.merge(products, on="product_id", how="left")
    sales_df = sales_df.merge(categories, on="category_id", how="left")
    sales_df = sales_df.merge(
        warranty[["claim_id", "sale_id", "claim_date", "repair_status"]],
        on="sale_id",
        how="left",
    )

    # Binary claim indicator.
    sales_df["has_claim"] = sales_df["claim_id"].notna().astype(int)

    # Claim reporting delay; invalid negative values are excluded downstream.
    sales_df["days_to_claim"] = (sales_df["claim_date"] - sales_df["sale_date"]).dt.days

    # Calendar dimensions for trend and seasonality analysis.
    sales_df["sale_year"] = sales_df["sale_date"].dt.year
    sales_df["sale_month"] = sales_df["sale_date"].dt.to_period("M").astype(str)

    # Product age at sale, measured in months.
    sales_df["launch_months_ago"] = (
        (sales_df["sale_date"].dt.year - sales_df["launch_date"].dt.year) * 12
        + (sales_df["sale_date"].dt.month - sales_df["launch_date"].dt.month)
    )

    # Price bands for segment comparison.
    sales_df["price_segment"] = pd.cut(
        sales_df["price"],
        bins=[0, 500, 1000, 1500, math.inf],
        labels=["Under 500", "500-999", "1000-1499", "1500+"],
        right=False,
    )

    # Product lifecycle bands.
    sales_df["lifecycle_stage"] = pd.cut(
        sales_df["launch_months_ago"],
        bins=[-1, 6, 12, 18, math.inf],
        labels=["0-6 Months", "6-12 Months", "12-18 Months", "18+ Months"],
        right=False,
    )

    return sales_df


def portfolio_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Overall claim frequency benchmark and total exposure."""
    return pd.DataFrame(
        {
            "total_sales": [df["sale_id"].nunique()],
            "total_claims": [df["has_claim"].sum()],
            "overall_claim_rate_pct": [df["has_claim"].mean() * 100],
        }
    )


def risk_table(df: pd.DataFrame, group_col: str, min_exposure: int = 100) -> pd.DataFrame:
    """Create a claim-rate table for any grouping column.

    Groups below the exposure threshold are excluded to reduce small-sample noise.
    """
    table = (
        df.groupby(group_col, dropna=False)
        .agg(
            sales_exposure=("sale_id", "nunique"),
            claims=("has_claim", "sum"),
            units_sold=("quantity", "sum"),
        )
        .reset_index()
    )
    table["claim_rate_pct"] = (table["claims"] / table["sales_exposure"]) * 100
    table = table[table["sales_exposure"] >= min_exposure].copy()
    table = table.sort_values(["claim_rate_pct", "sales_exposure"], ascending=[False, False])
    return table


def score_relative_to_portfolio(df: pd.DataFrame, table: pd.DataFrame, group_col: str) -> pd.DataFrame:
    """Add portfolio deviation to a risk table.

    Adds portfolio-relative metrics for risk prioritisation.
    """
    portfolio_rate = df["has_claim"].mean() * 100
    table = table.copy()
    table["difference_from_portfolio_pct_points"] = table["claim_rate_pct"] - portfolio_rate
    table["relative_risk_index"] = (
        table["difference_from_portfolio_pct_points"] * (table["sales_exposure"] ** 0.5)
    )
    table["group_type"] = group_col
    return table.sort_values(["relative_risk_index", "sales_exposure"], ascending=[False, False])


def claim_timing_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Understand claim reporting lag using actuarial timing buckets."""
    claim_rows = df[(df["has_claim"] == 1) & (df["days_to_claim"] >= 0)].copy()
    if claim_rows.empty:
        return pd.DataFrame({
            "total_claims": [0],
            "within_30_days_pct": [0.0],
            "within_90_days_pct": [0.0],
            "within_180_days_pct": [0.0],
            "within_365_days_pct": [0.0],
            "avg_days_to_claim": [0.0],
            "median_days_to_claim": [0.0],
        })

    timing = pd.DataFrame(
        {
            "total_claims": [len(claim_rows)],
            "within_30_days_pct": [((claim_rows["days_to_claim"] <= 30).mean() * 100)],
            "within_90_days_pct": [((claim_rows["days_to_claim"] <= 90).mean() * 100)],
            "within_180_days_pct": [((claim_rows["days_to_claim"] <= 180).mean() * 100)],
            "within_365_days_pct": [((claim_rows["days_to_claim"] <= 365).mean() * 100)],
            "avg_days_to_claim": [claim_rows["days_to_claim"].mean()],
            "median_days_to_claim": [claim_rows["days_to_claim"].median()],
        }
    )
    return timing


def monthly_claim_trends(df: pd.DataFrame) -> pd.DataFrame:
    """Seasonality and monthly claim-rate evolution by month."""
    monthly = (
        df.groupby("sale_month", dropna=False)
        .agg(sales_exposure=("sale_id", "nunique"), claims=("has_claim", "sum"))
        .reset_index()
    )
    monthly["claim_rate_pct"] = (monthly["claims"] / monthly["sales_exposure"]) * 100
    monthly["prev_claim_rate_pct"] = monthly["claim_rate_pct"].shift(1)
    monthly["month_over_month_change_pct"] = (
        (monthly["claim_rate_pct"] - monthly["prev_claim_rate_pct"]) / monthly["prev_claim_rate_pct"]
    ) * 100
    return monthly.sort_values("sale_month").reset_index(drop=True)


def lifecycle_risk(df: pd.DataFrame) -> pd.DataFrame:
    """Assess whether claim behavior changes with product maturity."""
    lifecycle = (
        df[df["lifecycle_stage"].notna()]
        .groupby("lifecycle_stage", dropna=False)
        .agg(sales_exposure=("sale_id", "nunique"), claims=("has_claim", "sum"))
        .reset_index()
    )
    lifecycle["claim_rate_pct"] = (lifecycle["claims"] / lifecycle["sales_exposure"]) * 100
    order = ["0-6 Months", "6-12 Months", "12-18 Months", "18+ Months"]
    lifecycle["order"] = lifecycle["lifecycle_stage"].map({v: i for i, v in enumerate(order)})
    lifecycle = lifecycle.sort_values("order").drop(columns="order").reset_index(drop=True)
    return lifecycle


def stress_test_results(df: pd.DataFrame) -> pd.DataFrame:
    """Estimate claim-rate changes under simple adverse scenarios."""
    base_claims = df["has_claim"].sum()
    base_exposure = df["sale_id"].nunique()
    scenario_growth = [0.10, 0.20, 0.30]
    rows = []
    for pct in scenario_growth:
        adjusted_claims = base_claims * (1 + pct)
        rows.append(
            {
                "scenario_growth_pct": round(pct * 100, 0),
                "adjusted_claims": round(adjusted_claims, 0),
                "new_claim_rate_pct": round((adjusted_claims / base_exposure) * 100, 2),
                "incremental_claims": round(adjusted_claims - base_claims, 0),
            }
        )
    return pd.DataFrame(rows)


def save_outputs(df: pd.DataFrame) -> None:
    """Write portfolio, segment, timing, lifecycle, trend, and scenario outputs."""
    summary = portfolio_summary(df)
    summary.to_csv(OUTPUT_DIR / "actuarial_summary.csv", index=False)

    category_table = score_relative_to_portfolio(df, risk_table(df, "category_name"), "category_name")
    category_table.to_csv(OUTPUT_DIR / "risk_by_category.csv", index=False)

    product_table = score_relative_to_portfolio(df, risk_table(df, "product_name"), "product_name")
    product_table.to_csv(OUTPUT_DIR / "top_risky_products.csv", index=False)

    store_table = score_relative_to_portfolio(df, risk_table(df, "store_name"), "store_name")
    store_table.to_csv(OUTPUT_DIR / "risk_by_store.csv", index=False)

    country_table = score_relative_to_portfolio(df, risk_table(df, "country"), "country")
    country_table.to_csv(OUTPUT_DIR / "risk_by_country.csv", index=False)

    price_table = (
        df.groupby("price_segment", dropna=False)
        .agg(sales_exposure=("sale_id", "nunique"), claims=("has_claim", "sum"))
        .reset_index()
    )
    price_table["claim_rate_pct"] = (price_table["claims"] / price_table["sales_exposure"]) * 100
    price_table = score_relative_to_portfolio(df, price_table, "price_segment")
    price_table.to_csv(OUTPUT_DIR / "risk_by_price_segment.csv", index=False)

    lifecycle = lifecycle_risk(df)
    lifecycle.to_csv(OUTPUT_DIR / "risk_by_lifecycle_stage.csv", index=False)

    monthly = monthly_claim_trends(df)
    monthly.to_csv(OUTPUT_DIR / "monthly_claim_trends.csv", index=False)

    timing = claim_timing_summary(df)
    timing.to_csv(OUTPUT_DIR / "claim_timing.csv", index=False)

    risk_score_summary = (
        product_table[["product_name", "sales_exposure", "claims", "claim_rate_pct", "difference_from_portfolio_pct_points", "relative_risk_index"]]
        .head(10)
        .copy()
    )
    risk_score_summary.to_csv(OUTPUT_DIR / "risk_score_summary.csv", index=False)

    stress = stress_test_results(df)
    stress.to_csv(OUTPUT_DIR / "stress_test_results.csv", index=False)

    print("Saved portfolio and risk analysis outputs to:", OUTPUT_DIR)
    print(summary.to_string(index=False))
    print("\nTop product risk summary:")
    print(risk_score_summary.to_string(index=False))


def main() -> None:
    """Main execution function."""
    tables = load_tables()
    df = prepare_master_table(tables)
    save_outputs(df)


if __name__ == "__main__":
    main()
