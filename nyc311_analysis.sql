-- NYC 311 SERVICE REQUESTS ANALYSIS (September 2026)
-- Source: NYC Open Data

-- PART 1: Create database and staging table.
-- The staging table holds the raw CSV data (14 of the 44 columns).


 create database nyc311_project;
 use nyc311_project;


CREATE TABLE stg_311 (
  unique_key      BIGINT,
  created_raw     VARCHAR(30),
  closed_raw      VARCHAR(30),
  agency          VARCHAR(20),
  agency_name     VARCHAR(200),
  problem         VARCHAR(200),
  problem_detail  VARCHAR(200),
  location_type   VARCHAR(100),
  incident_zip    VARCHAR(20),
  city            VARCHAR(100),
  status          VARCHAR(50),
  community_board VARCHAR(50),
  borough         VARCHAR(50),
  channel         VARCHAR(30)
);

-- PART 2: Import the CSV with LOAD DATA (needs local_infile enabled).
-- Keeps 14 useful columns, skips the other 30, and turns blanks into NULLs.

set global local_infile = 1;

LOAD DATA LOCAL INFILE 'C:/Users/vaish/Documents/DATA ANALYTICS/personal projects/311_Service_Requests_from_2020_to_Present_20261115.csv'
INTO TABLE stg_311
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@c1,@c2,@c3,@c4,@c5,@c6,@c7,@c8,@c9,@c10,@c11,@c12,@c13,@c14,@c15,@c16,@c17,@c18,@c19,@c20,@c21,@c22,@c23,@c24,@c25,@c26,@c27,@c28,@c29,@c30,@c31,@c32,@c33,@c34,@c35,@c36,@c37,@c38,@c39,@c40,@c41,@c42,@c43,@c44)
SET
  unique_key      = NULLIF(@c1,''),
  created_raw     = NULLIF(@c2,''),
  closed_raw      = NULLIF(@c3,''),
  agency          = NULLIF(@c4,''),
  agency_name     = NULLIF(@c5,''),
  problem         = NULLIF(@c6,''),
  problem_detail  = NULLIF(@c7,''),
  location_type   = NULLIF(@c9,''),
  incident_zip    = NULLIF(@c10,''),
  city            = NULLIF(@c18,''),
  status          = NULLIF(@c21,''),
  community_board = NULLIF(@c25,''),
  borough         = NULLIF(@c29,''),
  channel         = NULLIF(@c32,'');

-- PART 3: Check the import. Results: 313,249 rows, 1 Sep to 30 Sep 2026,
-- 0 duplicates, 18,773 missing closed dates (requests still open).

SELECT COUNT(*) AS total_rows,
       MIN(STR_TO_DATE(created_raw,'%m/%d/%Y %r')) AS first_date,
       MAX(STR_TO_DATE(created_raw,'%m/%d/%Y %r')) AS last_date
FROM stg_311;


SELECT COUNT(*) - COUNT(DISTINCT unique_key) AS duplicate_rows,
       SUM(created_raw IS NULL) AS missing_created,
       SUM(closed_raw IS NULL)  AS missing_closed,
       SUM(agency IS NULL)      AS missing_agency,
       SUM(problem IS NULL)     AS missing_problem,
       SUM(borough IS NULL)     AS missing_borough
FROM stg_311;


-- PART 4: Clean the data into a tidy table.
-- Converts text dates to real dates, makes text UPPER case so values match,
-- and fills blanks with labels.


CREATE TABLE requests_clean AS
SELECT
  unique_key,
  STR_TO_DATE(created_raw,'%m/%d/%Y %r') AS created_at,
  STR_TO_DATE(closed_raw, '%m/%d/%Y %r') AS closed_at,
  UPPER(TRIM(agency))                                  AS agency_code,
  TRIM(agency_name)                                    AS agency_name,
  UPPER(TRIM(problem))                                 AS problem,
  UPPER(COALESCE(TRIM(problem_detail),'UNSPECIFIED'))  AS problem_detail,
  UPPER(COALESCE(TRIM(borough),'UNSPECIFIED'))         AS borough,
  UPPER(COALESCE(TRIM(city),'UNKNOWN'))                AS city,
  COALESCE(TRIM(incident_zip),'UNKNOWN')               AS incident_zip,
  UPPER(COALESCE(TRIM(community_board),'UNSPECIFIED')) AS community_board,
  UPPER(COALESCE(TRIM(channel),'UNKNOWN'))             AS channel,
  TRIM(status)                                         AS status
FROM stg_311
WHERE unique_key IS NOT NULL
  AND created_raw IS NOT NULL
  AND agency IS NOT NULL
  AND problem IS NOT NULL;

-- Quality check: expect 313249 rows and 18773 still open.
SELECT COUNT(*) AS rows_after_cleaning,
       SUM(closed_at < created_at) AS closed_before_created,
       SUM(closed_at IS NULL) AS still_open
FROM requests_clean;


-- PART 5: Split the data into related tables (star schema):
-- 1 fact table (requests) + 3 dimension tables (agency, complaint, location).
CREATE TABLE dim_agency (
  agency_id   INT AUTO_INCREMENT PRIMARY KEY,
  agency_code VARCHAR(20),
  agency_name VARCHAR(200)
);
INSERT INTO dim_agency (agency_code, agency_name)
SELECT agency_code, MIN(agency_name) FROM requests_clean GROUP BY agency_code;

CREATE TABLE dim_complaint (
  complaint_id   INT AUTO_INCREMENT PRIMARY KEY,
  problem        VARCHAR(200),
  problem_detail VARCHAR(200)
);
INSERT INTO dim_complaint (problem, problem_detail)
SELECT DISTINCT problem, problem_detail FROM requests_clean;
ALTER TABLE dim_complaint ADD INDEX idx_complaint (problem, problem_detail);

CREATE TABLE dim_location (
  location_id     INT AUTO_INCREMENT PRIMARY KEY,
  borough         VARCHAR(50),
  city            VARCHAR(100),
  incident_zip    VARCHAR(20),
  community_board VARCHAR(50)
);
INSERT INTO dim_location (borough, city, incident_zip, community_board)
SELECT DISTINCT borough, city, incident_zip, community_board FROM requests_clean;
ALTER TABLE dim_location ADD INDEX idx_location (borough, city, incident_zip, community_board);

-- Fact table: one row per request. resolution_hours is blank for open
-- requests and for rows where closed date is before created date.
CREATE TABLE fact_requests (
  unique_key       BIGINT PRIMARY KEY,
  created_at       DATETIME,
  closed_at        DATETIME,
  agency_id        INT,
  complaint_id     INT,
  location_id      INT,
  channel          VARCHAR(30),
  status           VARCHAR(50),
  resolution_hours DECIMAL(10,2),
  FOREIGN KEY (agency_id)    REFERENCES dim_agency(agency_id),
  FOREIGN KEY (complaint_id) REFERENCES dim_complaint(complaint_id),
  FOREIGN KEY (location_id)  REFERENCES dim_location(location_id)
);

INSERT INTO fact_requests
SELECT r.unique_key, r.created_at, r.closed_at,
       a.agency_id, c.complaint_id, l.location_id,
       r.channel, r.status,
       CASE WHEN r.closed_at >= r.created_at
            THEN ROUND(TIMESTAMPDIFF(SECOND, r.created_at, r.closed_at)/3600, 2)
       END
FROM requests_clean r
JOIN dim_agency    a ON a.agency_code = r.agency_code
JOIN dim_complaint c ON c.problem = r.problem AND c.problem_detail = r.problem_detail
JOIN dim_location  l ON l.borough = r.borough AND l.city = r.city
                    AND l.incident_zip = r.incident_zip
                    AND l.community_board = r.community_board;

ALTER TABLE fact_requests ADD INDEX idx_created (created_at);

-- Check: must equal rows_after_cleaning from Part 4.
SELECT COUNT(*) AS fact_rows FROM fact_requests;


-- Q1. How big is the dataset, and how well are requests resolved?
SELECT COUNT(*) AS total_requests,
       MIN(created_at) AS first_request,
       MAX(created_at) AS last_request,
       SUM(closed_at IS NULL) AS still_open,
       ROUND(100*SUM(closed_at IS NULL)/COUNT(*),1) AS pct_still_open,
       ROUND(AVG(resolution_hours),1) AS avg_resolution_hours
FROM fact_requests;

-- Q2. What are the top 10 complaint types and their share of all requests?
SELECT c.problem,
       COUNT(*) AS requests,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_share
FROM fact_requests f
JOIN dim_complaint c ON c.complaint_id = f.complaint_id
GROUP BY c.problem
ORDER BY requests DESC
LIMIT 10;


-- Q3. Which agencies handle the most requests, and how fast do they resolve them?
SELECT a.agency_code,
       COUNT(*) AS requests,
       ROUND(AVG(f.resolution_hours),1) AS avg_hours,
       ROUND(100*SUM(f.resolution_hours <= 24)/COUNT(f.resolution_hours),1) AS pct_closed_within_24h,
       ROUND(100*SUM(f.closed_at IS NULL)/COUNT(*),1) AS pct_still_open
FROM fact_requests f
JOIN dim_agency a ON a.agency_id = f.agency_id
GROUP BY a.agency_code
HAVING COUNT(*) >= 500
ORDER BY requests DESC;


-- Q4. Which complaint types take the longest to resolve?
SELECT c.problem, a.agency_code,
       COUNT(*) AS requests,
       ROUND(AVG(f.resolution_hours),1) AS avg_hours
FROM fact_requests f
JOIN dim_complaint c ON c.complaint_id = f.complaint_id
JOIN dim_agency a ON a.agency_id = f.agency_id
GROUP BY c.problem, a.agency_code
HAVING COUNT(f.resolution_hours) >= 300
ORDER BY avg_hours DESC
LIMIT 10;


-- Q5. Which boroughs have the slowest resolution?
SELECT l.borough,
       COUNT(*) AS requests,
       ROUND(AVG(f.resolution_hours),1) AS avg_hours,
       ROUND(100*SUM(f.closed_at IS NULL)/COUNT(*),1) AS pct_still_open
FROM fact_requests f
JOIN dim_location l ON l.location_id = f.location_id
WHERE l.borough <> 'UNSPECIFIED'
GROUP BY l.borough
ORDER BY avg_hours DESC;


-- Q6. What does the daily trend look like? (LAG + 7-day moving average)
-- 1 Sep and 30 Sep are excluded because the file starts at 8:38 PM on 1 Sep
-- and ends at 8:30 PM on 30 Sep, so those two days are incomplete.
WITH daily AS (
  SELECT DATE(created_at) AS day, COUNT(*) AS requests
  FROM fact_requests
  WHERE created_at >= '2026-09-02' AND created_at < '2026-09-30'
  GROUP BY DATE(created_at)
)
SELECT day, requests,
       requests - LAG(requests) OVER (ORDER BY day) AS change_vs_prev_day,
       ROUND(AVG(requests) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),0) AS moving_avg_7d
FROM daily
ORDER BY day;


-- Q7. At what hour of the day do most requests come in?
SELECT HOUR(created_at) AS hour_of_day,
       COUNT(*) AS requests,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_of_total
FROM fact_requests
GROUP BY HOUR(created_at)
ORDER BY requests DESC;


-- Q8. What are the top 3 complaint types for each agency? (CTE + RANK)
WITH agency_complaints AS (
  SELECT a.agency_code, c.problem,
         COUNT(*) AS requests,
         RANK() OVER (PARTITION BY a.agency_code ORDER BY COUNT(*) DESC) AS rnk
  FROM fact_requests f
  JOIN dim_agency a ON a.agency_id = f.agency_id
  JOIN dim_complaint c ON c.complaint_id = f.complaint_id
  GROUP BY a.agency_code, c.problem
)
SELECT agency_code, problem, requests, rnk
FROM agency_complaints
WHERE rnk <= 3
ORDER BY agency_code, rnk;


-- Q9. Which channel do people use, and does it affect resolution time?
SELECT channel,
       COUNT(*) AS requests,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_share,
       ROUND(AVG(resolution_hours),1) AS avg_hours
FROM fact_requests
GROUP BY channel
ORDER BY requests DESC;