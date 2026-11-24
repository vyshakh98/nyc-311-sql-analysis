# NYC 311 Service Requests: SQL Analysis (September 2026)

## Problem
NYC 311 is the city's non-emergency complaint line. This project analyzes 313,249 service requests from September 2026 to find which complaint types are most common, which agencies resolve requests slowest, and when demand peaks, so the city can allocate resources better.

## Dataset
NYC Open Data, "311 Service Requests from 2020 to Present". I filtered one month (1 to 30 September 2026) and exported 313,249 rows (44 columns).

## Tools
MySQL 8, MySQL Workbench

## What I did
- Loaded the raw CSV into a MySQL staging table with `LOAD DATA`, keeping the 14 columns needed
- Checked data quality: 0 duplicate requests, 18,773 requests with no closed date (still open), 210 requests with a closed date before the created date
- Cleaned the data: converted text to datetime, standardized text, handled NULLs
- Designed a star schema: 1 fact table and 3 dimension tables (agency, complaint, location)
- Wrote 9 analytical queries using joins, CTEs, and window functions (`RANK`, `LAG`, moving averages)

## Key findings
1. Illegal Parking was the top complaint (16.5% of all requests). Noise complaints together added another 15.8%.
2. NYPD handled 47% of all requests and closed 99.4% within 24 hours. HPD handled 17% but closed only 4.8% within 24 hours (average 255.6 hours).
3. Food Establishment complaints (DOHMH) were the slowest to resolve, averaging 1,277.8 hours (about 53 days).
4. Manhattan had the longest average resolution time (119.8 hours), versus 90.3 hours in Queens.
5. Requests peak between 9 AM and noon (18.2% of all requests), with 11 AM the busiest hour, and fall to about 1% per hour overnight.
6. 6.0% of requests were still open when the data was pulled, including 78% of TLC and 46.5% of DPR requests.
7. Online was the most used channel (54.3%), and mobile requests closed fastest (27.3 hours vs 144.4 for phone).

## Recommendations
- Review the inspection process for DOHMH food establishment and smoking/vaping complaints, which take 41 to 53 days to close on average.
- Check HPD's inspection capacity for unsanitary condition and plumbing complaints, since few close within 24 hours despite high volume.
- Schedule more intake and response staff from 9 AM to noon and on Mondays, and review the open backlogs at TLC and DPR.

## Limitations
- This analysis covers one month, so it can't show seasonal patterns.
- Agencies define "closed" differently (for example, NYPD closes when officers respond, HPD after an inspection), so resolution times are not a like-for-like measure of performance.
- Averages exclude requests still open, so true delays are likely longer than shown.
- 210 requests with a closed date before the created date were excluded from resolution-time averages.
- Borough and channel differences may reflect the mix of complaint types, not performance.

## Files
- `nyc311_analysis.sql`: full SQL script (setup, import, cleaning, star schema, 9 queries)
- `results/`: screenshots of query results
