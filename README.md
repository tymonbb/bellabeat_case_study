# Bellabeat Case Study: How Fitbit Users Engage with Their Devices

Product analytics case study on public Fitbit tracker data (35 users,
March–May 2016). The goal is to identify usage and engagement patterns
that can inform marketing strategy for Bellabeat, a maker of wellness
devices for women.

> **Status:** in progress. Data audit, cleaning and star-schema data model
> in BigQuery complete; analysis in Python under way.

## Approach

Rather than following the course template step by step, the project is
built around hypotheses about how people actually use their devices:
engagement over time, overnight wear, daily activity rhythm, the link
between sedentary time and sleep, and which features users adopt.

## Data

FitBit Fitness Tracker Data (Mobius, Kaggle, CC0), two export periods:
12 Mar – 11 Apr 2016 and 12 Apr – 12 May 2016.
Raw files are not stored in this repository (617 MB). To reproduce:
download the dataset from Kaggle and unzip each period into
`data/raw/period_1` and `data/raw/period_2`.

- How the raw data was loaded: [`sql/00_load_raw.md`](sql/00_load_raw.md)
- Data quality issues and decisions: [`docs/data_quality_log.md`](docs/data_quality_log.md)

## Tools

Google BigQuery (SQL), Python (pandas, statsmodels), Power BI (DAX), Git

## Repository structure

    sql/          BigQuery scripts: load, audit, cleaning, data model
    docs/         data quality log and methodology notes
    notebooks/    Python analysis
    dashboard/    Power BI report and screenshots