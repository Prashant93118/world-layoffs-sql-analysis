-- ============================================================
--  WORLD LAYOFFS — DATA CLEANING + EDA
--  Author  : Prashant
--  Project : Tech Layoffs Analysis (2020–2025)
--  Style   : Every query annotated with Question + Logic
-- ============================================================


-- ============================================================
--  SECTION 1 — SETUP & DATA LOAD
-- ============================================================

-- Q: Where do we keep the raw data so we can start working with it?
-- Logic: Create a dedicated database and table that mirrors the
--        exact structure of the CSV file. Using VARCHAR for date
--        and numeric columns intentionally — we'll fix types after
--        cleaning so LOAD DATA INFILE doesn't reject dirty values.
Use world_layoffs;

CREATE TABLE layoffs (
    company             VARCHAR(100),
    location            VARCHAR(100),
    total_laid_off      INT,
    date                VARCHAR(20),
    percentage_laid_off DECIMAL(5,2),
    industry            VARCHAR(50),
    source              VARCHAR(1000),
    stage               VARCHAR(50),
    funds_raised        INT,
    country             VARCHAR(100),
    date_added          VARCHAR(20)
);


-- Q: How do we import the CSV while safely handling blank/null values?
-- Logic: Load the file using user-defined variables (@col) so we
--        can intercept each value and convert empty strings to NULL
--        using NULLIF(). This prevents "incorrect integer value" errors
--        for numeric columns that have blank cells in the CSV.
LOAD DATA INFILE 'C:/Users/prashant/OneDrive/Desktop/Layoffs_Data/layoffs.csv'
INTO TABLE layoffs
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(company, location, @total_laid_off, @date, @percentage_laid_off, industry, source, stage, @funds_raised, country, @date_added)
SET
    total_laid_off      = NULLIF(@total_laid_off, ''),
    percentage_laid_off = NULLIF(@percentage_laid_off, ''),
    funds_raised        = NULLIF(@funds_raised, ''),
    date                = NULLIF(@date, ''),
    date_added          = NULLIF(@date_added, '');


-- Q: Did the data load correctly? Let me do a quick sanity check.
-- Logic: A simple SELECT * to visually verify row count, column names,
--        and that NULLs appear where blanks existed in the CSV.
SELECT * FROM LAYOFFS;


-- ============================================================
--  SECTION 2 — CREATE A STAGING TABLE (SAFETY COPY)
-- ============================================================

-- Q: How do we protect the raw data before we start modifying anything?
-- Logic: Best practice in data cleaning — never work on the original.
--        LIKE creates an identical empty table structure without copying rows.
CREATE TABLE LAYOFFS_STAGING
LIKE LAYOFFS;

-- Q: Now how do we populate the staging table with all the original data?
-- Logic: INSERT INTO ... SELECT * copies every row from LAYOFFS into
--        LAYOFFS_STAGING. Original table stays untouched.
INSERT LAYOFFS_STAGING
SELECT * 
FROM LAYOFFS;

-- Q: Do we need the SOURCE and DATE_ADDED columns for our analysis?
-- Logic: SOURCE is a URL reference (not useful for aggregations/EDA).
--        DATE_ADDED is metadata about when the record was scraped — not
--        meaningful for business analysis. Dropping keeps the table lean.
ALTER TABLE LAYOFFS_STAGING
DROP COLUMN SOURCE,
DROP COLUMN DATE_ADDED;


-- ============================================================
--  SECTION 3 — REMOVING DUPLICATES
-- ============================================================

-- Q: How do we identify rows that are exact duplicates across all key columns?
-- Logic: ROW_NUMBER() with PARTITION BY all business-relevant columns assigns
--        row number 1 to the first occurrence and 2+ to duplicates.
--        Any row where ROW_NUM > 1 is a duplicate.
SELECT *,
ROW_NUMBER() OVER(
PARTITION BY COMPANY, LOCATION, TOTAL_LAID_OFF, `DATE`, PERCENTAGE_LAID_OFF,
INDUSTRY, STAGE, COUNTRY) AS ROW_NUM
FROM LAYOFFS_STAGING;


-- Q: How many actual duplicate records exist in our dataset?
-- Logic: Wrapping the ROW_NUMBER logic inside a CTE lets us filter
--        on the computed ROW_NUM column (you can't use window functions
--        directly in a WHERE clause). Result = rows to be deleted.
WITH DUPLICATE_CTE AS
(
    SELECT *,
    ROW_NUMBER() OVER(
    PARTITION BY COMPANY, LOCATION, TOTAL_LAID_OFF, `DATE`, PERCENTAGE_LAID_OFF,
    INDUSTRY, STAGE, COUNTRY) AS ROW_NUM
    FROM LAYOFFS_STAGING
)
SELECT * FROM DUPLICATE_CTE
WHERE ROW_NUM > 1;


-- Q: Why create a third table (layoffs_staging2) instead of deleting directly?
-- Logic: MySQL doesn't allow DELETE on a CTE directly. The workaround is to
--        materialize the ROW_NUM column into a new physical table so we can
--        run DELETE WHERE ROW_NUM > 1 straightforwardly.
CREATE TABLE `layoffs_staging2` (
  `company`             VARCHAR(100) DEFAULT NULL,
  `location`            VARCHAR(100) DEFAULT NULL,
  `total_laid_off`      INT DEFAULT NULL,
  `date`                VARCHAR(20) DEFAULT NULL,
  `percentage_laid_off` DECIMAL(5,2) DEFAULT NULL,
  `industry`            VARCHAR(50) DEFAULT NULL,
  `stage`               VARCHAR(50) DEFAULT NULL,
  `funds_raised`        INT DEFAULT NULL,
  `country`             VARCHAR(100) DEFAULT NULL,
  `row_num`             INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Q: How do we populate staging2 with the ROW_NUM column included?
-- Logic: INSERT INTO ... SELECT with ROW_NUMBER() assigns duplicate
--        markers as a real column we can later filter and delete on.
INSERT INTO LAYOFFS_STAGING2
SELECT *,
ROW_NUMBER() OVER(
PARTITION BY COMPANY, LOCATION, TOTAL_LAID_OFF, `DATE`, PERCENTAGE_LAID_OFF,
INDUSTRY, STAGE, COUNTRY) AS ROW_NUM
FROM LAYOFFS_STAGING;


-- Q: Let's verify — which rows are flagged as duplicates before we delete?
-- Logic: One final check before DELETE to confirm we're removing the right rows.
--        ROW_NUM > 1 means second or later occurrence of the same combination.
SELECT * FROM LAYOFFS_STAGING2
WHERE ROW_NUM > 1;


-- Q: Now that we've confirmed, how do we actually remove the duplicate rows?
-- Logic: DELETE WHERE ROW_NUM > 1 removes only the extra copies, keeping
--        exactly one record per unique business event.
--        SET SQL_SAFE_UPDATES = 0 is needed to allow DELETE without a key filter.
SET SQL_SAFE_UPDATES = 0;

DELETE 
FROM LAYOFFS_STAGING2
WHERE ROW_NUM > 1;


-- ============================================================
--  SECTION 4 — STANDARDIZING DATA
-- ============================================================

-- Q: Do any company names have leading or trailing whitespace?
-- Logic: TRIM() removes invisible spaces that would cause "Amazon" and
--        " Amazon" to be counted as two different companies in aggregations.
--        SELECT first to preview the change before UPDATE.
SELECT COMPANY, TRIM(COMPANY)
FROM LAYOFFS_STAGING2;

-- Q: How do we apply the trim fix permanently to all company names?
-- Logic: UPDATE with SET COMPANY = TRIM(COMPANY) overwrites the column
--        in-place for all rows. Safe because TRIM on already-clean text is a no-op.
UPDATE LAYOFFS_STAGING2
SET COMPANY = TRIM(COMPANY);


-- Q: Are there any inconsistencies or unexpected values in the INDUSTRY column?
-- Logic: DISTINCT + ORDER BY 1 gives a sorted alphabetical list —
--        easy to spot typos, variations (e.g., "Crypto" vs "Crypto Currency"),
--        or unwanted NULL/blank values.
SELECT DISTINCT INDUSTRY
FROM LAYOFFS_STAGING2
ORDER BY 1;


-- Q: Does the LOCATION column have any formatting issues worth fixing?
-- Logic: Some locations were tagged with ", Non-U.S." appended by the data source.
--        This makes GROUP BY location unreliable since "London, Non-U.S." and
--        "London" would be treated as different values.
SELECT DISTINCT LOCATION
FROM LAYOFFS_STAGING2
ORDER BY 1;

-- Q: How do we remove the ", Non-U.S." suffix from affected location values?
-- Logic: REPLACE() finds the exact substring ", Non-U.S." and replaces it with
--        empty string. WHERE LIKE filter limits updates to only rows that need it.
UPDATE layoffs_staging2
SET location = REPLACE(location, ', Non-U.S.', '')
WHERE location LIKE '%, Non-U.S.%';


-- Q: After removing Non-U.S., some locations still have extra comma-separated text.
--    How do we extract just the primary city name?
-- Logic: SUBSTRING_INDEX(str, ', ', 1) returns everything before the first comma,
--        effectively keeping only the first city/region name in composite values.
UPDATE layoffs_staging2
SET location = SUBSTRING_INDEX(location, ', ', 1)
WHERE location LIKE '%, %';


-- Q: Does the COUNTRY column have any trailing spaces or inconsistencies?
-- Logic: Comparing COUNTRY with TRIM(COUNTRY) side-by-side lets us spot
--        any invisible whitespace differences before deciding if an UPDATE is needed.
SELECT DISTINCT COUNTRY, TRIM(COUNTRY)
FROM LAYOFFS_STAGING2;


-- Q: How do we verify the date format before converting it?
-- Logic: STR_TO_DATE() preview alongside the raw DATE column lets us confirm
--        '%m/%d/%Y' is the correct format mask. If output shows NULL for any row,
--        the format is wrong — catch the issue before committing the UPDATE.
SELECT `DATE`,
STR_TO_DATE(`DATE`, '%m/%d/%Y')
FROM LAYOFFS_STAGING2;

-- Q: How do we convert the DATE column from a text string to an actual date?
-- Logic: STR_TO_DATE() parses the string and returns a proper DATE value.
--        Stored back as VARCHAR for now — the data type change comes next.
UPDATE LAYOFFS_STAGING2
SET `DATE` = STR_TO_DATE(`DATE`, '%m/%d/%Y');

-- Q: The values look like dates now — but why change the column data type?
-- Logic: Even though STR_TO_DATE() formatted the values correctly,
--        the column is still VARCHAR. ALTER TABLE MODIFY COLUMN changes
--        the actual data type to DATE, enabling YEAR(), MONTH(),
--        date arithmetic, and proper ordering in queries.
ALTER TABLE LAYOFFS_STAGING2
MODIFY COLUMN `DATE` DATE;


-- ============================================================
--  SECTION 5 — HANDLING NULL & BLANK VALUES
-- ============================================================

-- Q: How many rows are completely missing both layoff metrics?
-- Logic: Rows where both TOTAL_LAID_OFF and PERCENTAGE_LAID_OFF are NULL
--        have no usable quantitative data. We'll decide whether to drop them
--        after checking if we can fill them from another source. (Result: 703 rows)
SELECT *
FROM LAYOFFS_STAGING2
WHERE TOTAL_LAID_OFF IS NULL
AND PERCENTAGE_LAID_OFF IS NULL;


-- Q: Are there any rows where INDUSTRY is missing or blank?
-- Logic: Two separate conditions (IS NULL and = '') because MySQL can store
--        genuinely empty strings alongside NULLs — checking only one would
--        miss the other. These rows may be fixable via a self-join.
SELECT *
FROM LAYOFFS_STAGING2
WHERE INDUSTRY = ''
OR INDUSTRY IS NULL;


-- Q: Can we fill missing INDUSTRY values using data from the same company
--    appearing elsewhere in the dataset with a valid INDUSTRY?
-- Logic: Self-join on COMPANY + LOCATION pairs t1 (missing industry) with
--        t2 (has industry). If a match exists, we can copy t2.INDUSTRY into t1.
--        After investigation — no usable matches found, so these rows remain NULL.
SELECT *
FROM LAYOFFS_STAGING2 t1
JOIN LAYOFFS_STAGING2 t2
    ON t1.COMPANY = t2.COMPANY
    AND t1.LOCATION = t2.LOCATION
WHERE (t1.INDUSTRY IS NULL OR t1.INDUSTRY = '')
AND t2.INDUSTRY IS NOT NULL;


-- Q: Since INDUSTRY can't be recovered, what do we do with those rows?
-- Logic: Without INDUSTRY, these rows are useless for industry-level analysis.
--        DELETE removes them cleanly rather than leaving partial data that
--        could skew aggregations.
DELETE FROM LAYOFFS_STAGING2
WHERE INDUSTRY IS NULL
OR INDUSTRY = '';


-- Q: Does the STAGE column have any blank strings that should be NULL instead?
-- Logic: Blank strings are not the same as NULL in MySQL — they appear in
--        COUNT() and GROUP BY. Converting '' to NULL ensures consistent treatment
--        and makes IS NULL checks reliable.
SELECT *
FROM LAYOFFS_STAGING2
WHERE STAGE = '';

UPDATE layoffs_staging2
SET STAGE = NULL
WHERE STAGE = '';


-- Q: Should we keep rows where both layoff count and percentage are NULL?
-- Logic: These rows cannot contribute to any quantitative analysis. They are
--        essentially empty records for the key metrics of this project.
--        Deleting them reduces noise without losing meaningful information.
DELETE
FROM LAYOFFS_STAGING2
WHERE TOTAL_LAID_OFF IS NULL
AND PERCENTAGE_LAID_OFF IS NULL;


-- Q: We're done cleaning — do we still need the ROW_NUM helper column?
-- Logic: ROW_NUM was only needed to identify and delete duplicates.
--        Dropping it keeps the schema clean and matches the expected
--        column structure for EDA queries downstream.
ALTER TABLE LAYOFFS_STAGING2
DROP COLUMN ROW_NUM;


-- Final check: What does our cleaned dataset look like?
SELECT * FROM LAYOFFS_STAGING2;




-- ============================================================
--  SECTION 6 — EXPLORATORY DATA ANALYSIS (EDA)
-- ============================================================

-- Q: What is the maximum single-event layoff count and
--    the highest percentage laid off recorded?
-- Logic: MAX() on both metric columns gives us the extreme ceiling of
--        the dataset — useful to understand the worst-case data points
--        before diving into grouped analysis.
SELECT MAX(TOTAL_LAID_OFF), MAX(PERCENTAGE_LAID_OFF)
FROM LAYOFFS_STAGING2;


-- Q: Which companies went completely under (laid off 100% of staff)?
--    And how large were those layoffs in absolute numbers?
-- Logic: PERCENTAGE_LAID_OFF = 1 means a complete shutdown.
--        ORDER BY TOTAL_LAID_OFF DESC surfaces the biggest collapses first
--        so we can identify which shutdowns had the largest workforce impact.
SELECT *
FROM LAYOFFS_STAGING2
WHERE PERCENTAGE_LAID_OFF = 1
ORDER BY TOTAL_LAID_OFF DESC;


-- Q: Among companies that fully shut down, which ones had raised the most funding?
-- Logic: ORDER BY FUNDS_RAISED DESC reveals companies that burned through
--        the most investor capital before closing — a key insight about
--        funding efficiency and startup risk.
SELECT *
FROM LAYOFFS_STAGING2
WHERE PERCENTAGE_LAID_OFF = 1
ORDER BY FUNDS_RAISED DESC;


-- Q: Which companies had the highest total layoffs across the entire dataset?
-- Logic: SUM() + GROUP BY COMPANY aggregates all layoff events per company
--        over the full time period. ORDER BY DESC surfaces the largest employers
--        that cut the most jobs.
SELECT COMPANY, SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
GROUP BY COMPANY
ORDER BY 2 DESC;


-- Q: Which industries suffered the most job losses overall?
-- Logic: SUM() + GROUP BY INDUSTRY tells us which sectors were hit hardest
--        in aggregate — helpful for understanding macro economic impact by domain.
SELECT INDUSTRY, SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
GROUP BY INDUSTRY
ORDER BY 2 DESC;


-- Q: Which countries experienced the most layoffs in this dataset?
-- Logic: Geographic aggregation reveals whether this is a global trend
--        or concentrated in specific markets (spoiler: likely US-heavy
--        since most data is from tech-heavy Western companies).
SELECT COUNTRY, SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
GROUP BY COUNTRY
ORDER BY 2 DESC;


-- Q: Which year had the highest number of total layoffs?
-- Logic: YEAR(`DATE`) extracts just the year from the DATE column.
--        ORDER BY 2 DESC shows the worst year on top — useful for
--        identifying macro economic turning points (e.g., post-pandemic correction).
SELECT YEAR(`DATE`), SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
GROUP BY YEAR(`DATE`)
ORDER BY 2 DESC;


-- Q: How did layoffs trend month by month across the entire dataset?
-- Logic: SUBSTRING(`DATE`, 1, 7) extracts YYYY-MM format — grouping by
--        calendar month (not just year) shows seasonality and spikes.
--        IS NOT NULL filter removes rows where date parsing failed.
SELECT SUBSTRING(`DATE`, 1,7) AS `MONTH`, SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
WHERE SUBSTRING(`DATE`, 1,7) IS NOT NULL
GROUP BY `MONTH`
ORDER BY 1 ASC;


-- Q: What is the cumulative (rolling) total of layoffs month over month?
-- Logic: Using a CTE to first compute monthly totals, then SUM() OVER(ORDER BY MONTH)
--        as a window function builds a running total. This shows the compounding
--        scale of layoffs — more impactful than individual monthly snapshots alone.
WITH ROLLING_TOTAL AS
(
    SELECT SUBSTRING(`DATE`, 1,7) AS `MONTH`, SUM(TOTAL_LAID_OFF) AS TOTAL_LAID_OFF
    FROM LAYOFFS_STAGING2
    WHERE SUBSTRING(`DATE`, 1,7) IS NOT NULL
    GROUP BY `MONTH`
    ORDER BY 1 ASC
)
SELECT `MONTH`, TOTAL_LAID_OFF,
SUM(TOTAL_LAID_OFF) OVER(ORDER BY `MONTH`) AS ROLLING_TOTAL
FROM ROLLING_TOTAL;


-- Q: Which companies had the highest layoffs in each specific year?
-- Logic: Grouping by COMPANY + YEAR gives per-company annual totals.
--        This is the foundation for the ranking query below — ORDER BY 3 DESC
--        shows the absolute leaders across all years at a glance.
SELECT COMPANY, YEAR(`DATE`), SUM(TOTAL_LAID_OFF)
FROM LAYOFFS_STAGING2
GROUP BY COMPANY, YEAR(`DATE`)
ORDER BY 3 DESC;


-- Q: Who were the Top 5 companies by layoffs for each individual year?
-- Logic: First CTE (COMPANY_YEAR) builds per-company per-year totals.
--        Second CTE (COMPANY_YEAR_RANK) applies DENSE_RANK() partitioned by YEAR
--        so ranking resets every year. Final filter WHERE RANKING <= 5 gives
--        us the annual leaderboard — great for spotting which giants cut the most
--        each year (e.g., Amazon in 2023 vs Meta in 2022)
WITH COMPANY_YEAR (COMPANY, YEARS, TOTAL_LAID_OFF) AS	
(														
    SELECT COMPANY, YEAR(`DATE`), SUM(TOTAL_LAID_OFF)	
    FROM LAYOFFS_STAGING2								
    GROUP BY COMPANY, YEAR(`DATE`)						
),														
COMPANY_YEAR_RANK AS
(
    SELECT *,
    DENSE_RANK() OVER(PARTITION BY YEARS ORDER BY TOTAL_LAID_OFF DESC) AS RANKING
    FROM COMPANY_YEAR
    WHERE YEARS IS NOT NULL
)
SELECT *
FROM COMPANY_YEAR_RANK
WHERE RANKING <= 5;


-- Q: Which funding stage (Seed, Series A, Post-IPO, etc.) had the most layoffs,
--    and what was the average percentage laid off at each stage?
-- Logic: SUM(TOTAL_LAID_OFF) shows absolute volume of job cuts per stage.
--        AVG(PERCENTAGE_LAID_OFF)*100 gives a normalized "severity" metric.
--        Together they answer: were early-stage startups more likely to cut
--        a bigger chunk of their team vs. late-stage/Post-IPO companies?
SELECT STAGE,										
SUM(TOTAL_LAID_OFF) AS TOTAL_LAID_OFF,				
ROUND(AVG(PERCENTAGE_LAID_OFF)*100, 2) AS AVG_PERCENTAGE	
FROM LAYOFFS_STAGING2									
WHERE STAGE IS NOT NULL										
GROUP BY STAGE												
ORDER BY TOTAL_LAID_OFF DESC;


-- Q: How many unique companies shut down completely (100% layoff) in each year?
-- Logic: COUNT(DISTINCT COMPANY) WHERE PERCENTAGE_LAID_OFF = 1 counts only
--        total shutdowns. GROUP BY YEAR shows if closures accelerated over time —
--        useful for understanding the intensity of startup failures year-on-year.
SELECT
    YEAR(`DATE`) AS `YEAR`,
    COUNT(DISTINCT COMPANY) AS SHUTDOWN_COUNT
FROM LAYOFFS_STAGING2
WHERE PERCENTAGE_LAID_OFF = 1.00
GROUP BY YEAR(`DATE`)
ORDER BY `YEAR` ASC;


-- Q: Which industries saw the most complete company shutdowns?
-- Logic: Filtering WHERE PERCENTAGE_LAID_OFF = 1 isolates only companies that
--        fully closed. GROUP BY INDUSTRY + COUNT(DISTINCT COMPANY) tells us
--        which sectors had the highest mortality rate — not just layoffs, but
--        full collapses. (Expected: Consumer, Retail, and early-stage tech.)
SELECT INDUSTRY,
COUNT(DISTINCT COMPANY) AS SHUTDOWN_COUNT
FROM LAYOFFS_STAGING2
WHERE PERCENTAGE_LAID_OFF = 1.00
GROUP BY INDUSTRY
ORDER BY SHUTDOWN_COUNT DESC;


-- Q: On average, which industries cut the highest PROPORTION of their workforce?
-- Logic: AVG(PERCENTAGE_LAID_OFF)*100 measures severity, not volume.
--        An industry with few but massive layoffs might score lower here
--        than one where most companies cut 40–60% of their teams. This gives
--        a different (and more nuanced) view than the total-count queries above.
SELECT INDUSTRY,
ROUND(AVG(PERCENTAGE_LAID_OFF)*100, 2) AS AVG_LAID_OFF
FROM LAYOFFS_STAGING2
WHERE INDUSTRY IS NOT NULL
GROUP BY INDUSTRY
ORDER BY AVG_LAID_OFF DESC;


-- Q: How did month-over-month layoff change look across the dataset?
--    Were there specific months with sharp spikes or drops?
-- Logic: First CTE computes monthly totals. Second CTE uses LAG() to pull
--        the previous month's value alongside the current one.
--        The formula (current - previous) / previous * 100 gives MoM% change.
--        NULLIF(prev, 0) prevents division-by-zero for the first month row.
--        This is a more advanced metric — shows acceleration/deceleration of layoffs.
WITH ROLLING_TOTAL AS
(
    SELECT SUBSTRING(`DATE`, 1,7) AS `MONTH`,
    SUM(TOTAL_LAID_OFF) AS TOTAL_LAID_OFF
    FROM LAYOFFS_STAGING2
    WHERE SUBSTRING(`DATE`, 1,7) IS NOT NULL
    GROUP BY `MONTH`
    ORDER BY 1 ASC
),
MOM_CALC AS
(
    SELECT
        `MONTH`,
        TOTAL_LAID_OFF,
        LAG(TOTAL_LAID_OFF) OVER(ORDER BY `MONTH`) AS PREV_MONTH,
        ROUND(
            (TOTAL_LAID_OFF - LAG(TOTAL_LAID_OFF) OVER(ORDER BY `MONTH`))
            / NULLIF(LAG(TOTAL_LAID_OFF) OVER(ORDER BY `MONTH`), 0) * 100
        , 2) AS MOM_CHANGE_PCT
    FROM ROLLING_TOTAL
)
SELECT * FROM MOM_CALC;


-- Q: Which industry dominated layoffs in each specific year (Top 5 per year)?
-- Logic: Mirrors the company ranking query but at the INDUSTRY level.
--        First CTE aggregates total layoffs by industry + year.
--        DENSE_RANK() partitioned by YEARS re-ranks each year independently.
--        WHERE RANKING <= 5 shows which sectors led layoffs annually —
--        helping identify whether specific industries worsened over time
--        (e.g., did Retail dominate 2020 while Tech dominated 2022-23?).
WITH INDUSTRY_YEAR (INDUSTRY, YEARS, TOTAL_LAID_OFF) AS
(
    SELECT INDUSTRY, YEAR(`DATE`), SUM(TOTAL_LAID_OFF)
    FROM LAYOFFS_STAGING2
    WHERE INDUSTRY IS NOT NULL
    GROUP BY INDUSTRY, YEAR(`DATE`)
),
INDUSTRY_YEAR_RANK AS
(
    SELECT *,
    DENSE_RANK() OVER(PARTITION BY YEARS ORDER BY TOTAL_LAID_OFF DESC) AS RANKING
    FROM INDUSTRY_YEAR
    WHERE YEARS IS NOT NULL
)
SELECT * FROM INDUSTRY_YEAR_RANK
WHERE RANKING <= 5;