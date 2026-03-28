# 🌍 World Layoffs — Data Cleaning + Exploratory Data Analysis (SQL)

> **Tech Layoffs Analysis | 2020–2025**  
> Full pipeline: Raw CSV → Staged & Cleaned → EDA with Window Functions & CTEs  
> **Tool:** MySQL Workbench &nbsp;|&nbsp; **Author:** Prashant

---

## 📌 Project Overview

This project performs end-to-end data cleaning and exploratory analysis on a real-world dataset of global tech layoffs from **2020 to 2025**.

Starting from a raw, messy CSV file, the project walks through every stage of a professional SQL data workflow — from safe data ingestion and duplicate removal to standardization, null handling, and finally, multi-layered EDA using window functions, CTEs, and aggregations.

Every query is annotated with a **Question + Logic** comment block explaining *what* is being done and *why*.

---

## 🗂️ Dataset

| Field | Detail |
|---|---|
| **Source** | Publicly available tech layoffs dataset |
| **Period** | 2020 – 2025 |
| **Key Columns** | Company, Location, Industry, Country, Stage, Total Laid Off, % Laid Off, Funds Raised, Date |

---

## 🛠️ Tech Stack

- **Database:** MySQL
- **Tool:** MySQL Workbench
- **Concepts Used:** CTEs, Window Functions (`ROW_NUMBER`, `DENSE_RANK`, `LAG`, `SUM OVER`), `LOAD DATA INFILE`, `STR_TO_DATE`, Self-Joins, Aggregations

---

## 📋 Project Structure

### Section 1 — Setup & Data Load
- Created `world_layoffs` database and table matching CSV schema
- Used `LOAD DATA INFILE` with `@variable` intercepts and `NULLIF()` to safely handle blank/null values

### Section 2 — Staging Table (Safety Copy)
- Created `layoffs_staging` as a structural clone — raw data never touched
- Dropped non-analytical columns (`SOURCE`, `DATE_ADDED`)

### Section 3 — Removing Duplicates
- Used `ROW_NUMBER() OVER(PARTITION BY ...)` to flag exact duplicates
- Materialized into `layoffs_staging2` to enable `DELETE WHERE ROW_NUM > 1`

### Section 4 — Standardizing Data
- `TRIM()` on `COMPANY`, cleaned `LOCATION` via `REPLACE()` + `SUBSTRING_INDEX()`
- `DATE` converted `VARCHAR` → `DATE` using `STR_TO_DATE()` + `ALTER TABLE`

### Section 5 — Handling NULL & Blank Values
- 703 rows with both key metrics NULL → deleted
- Self-join attempted for missing `INDUSTRY` → no matches → deleted
- Blank `STAGE` strings converted to `NULL`

### Section 6 — Exploratory Data Analysis (EDA)

| # | Question Answered | Technique |
|---|---|---|
| 1 | Max layoff & highest % | `MAX()` |
| 2 | Complete shutdowns (100% laid off) | `WHERE PERCENTAGE_LAID_OFF = 1` |
| 3 | Most funding burned before shutdown | `ORDER BY FUNDS_RAISED DESC` |
| 4 | Top companies all time | `SUM() + GROUP BY` |
| 5 | Industries hit hardest | `GROUP BY INDUSTRY` |
| 6 | Countries with most layoffs | `GROUP BY COUNTRY` |
| 7 | Worst year overall | `YEAR() + GROUP BY` |
| 8 | Month-by-month trend | `SUBSTRING(DATE, 1,7)` |
| 9 | Cumulative rolling total | `SUM() OVER(ORDER BY MONTH)` |
| 10 | Top 5 companies per year | `DENSE_RANK() OVER(PARTITION BY YEAR)` |
| 11 | Stage-wise layoffs + avg % cut | `AVG(PERCENTAGE_LAID_OFF)` |
| 12 | Shutdowns count per year | `COUNT(DISTINCT COMPANY)` |
| 13 | Industries with most shutdowns | Shutdown filter + `GROUP BY` |
| 14 | Highest avg % workforce cut by industry | `AVG() + ORDER BY` |
| 15 | Month-over-month % change | `LAG()` + `NULLIF()` |
| 16 | Top 5 industries per year | `DENSE_RANK() OVER(PARTITION BY YEARS)` |

---

## 💡 Key Insights (From EDA)

### 📌 Finding 1 — Top Companies All Time
- **Amazon leads with 58,024 layoffs** — 35% more than #2 Intel (43,115)
- Entire top 10 is Big Tech — no startup comes close in absolute numbers
- Top 5: Amazon → Intel → Microsoft → Meta → Salesforce

### 📌 Finding 2 — Annual #1 Company (DENSE_RANK)

| Year | #1 Company | Layoffs | Context |
|---|---|---|---|
| 2020 | Uber | 7,525 | COVID crushed travel first |
| 2021 | Bytedance | 3,600 | Quietest year in dataset |
| 2022 | Meta | 11,000 | Big Tech correction begins |
| 2023 | Amazon | 17,260 | Peak year — all top 5 were FAANG-level |
| 2024 | Intel | 15,062 | Semiconductor sector takes the hit |
| 2025 | Intel | 27,058 | Largest single-company figure in entire dataset |

### 📌 Finding 3 — Funding Stage vs Severity
- **Post-IPO:** 5,09,506 total layoffs — but only **16.80% avg** workforce cut
- **Seed stage:** only 2,531 total — but **81.86% avg** workforce cut
- **Insight:** Volume ≠ Severity. When a seed-stage startup cuts, it's essentially shutting down.

---

## 🚀 How to Run

1. Clone this repository
2. Open `world_layoffs_cleaning_eda.sql` in MySQL Workbench
3. Update the `LOAD DATA INFILE` path to your local CSV location
4. Run section by section (`Ctrl+Shift+Enter`)
5. Final cleaned data lives in `layoffs_staging2`

> ⚠️ `SET SQL_SAFE_UPDATES = 0` required before DELETE. Reset to `1` after cleaning.

---

## 📁 Repository Structure

| File | Description |
|---|---|
| `world_layoffs_cleaning_eda.sql` | Full annotated SQL script |
| `README.md` | This file |
| `/screenshots/` | Key query output screenshots |

---

## 👤 Author

**Prashant**  
F&A Executive → Transitioning to Data Analyst | Delhi NCR  
🔗 [LinkedIn](https://www.linkedin.com/in/prashant-dataanalyst) &nbsp;|&nbsp; [GitHub](https://github.com/prashant93118)
