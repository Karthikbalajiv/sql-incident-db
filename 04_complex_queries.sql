-- =====================================================================
-- 04_complex_queries.sql
-- Business questions answered against the normalised model.
-- Techniques: multi-table joins, CTEs, window functions (RANK, LAG,
-- moving frames), correlated / NOT EXISTS subqueries, conditional
-- aggregation with FILTER, GROUPING SETS / ROLLUP, HAVING.
-- =====================================================================
SET search_path = ops;

-- Q1. SLA breach rate per team per quarter in 2026
--     (5-table join, conditional aggregation, HAVING)
SELECT t.team_name,
       date_trunc('quarter', i.opened_at)::date               AS quarter,
       count(*)                                               AS incidents,
       count(*) FILTER (WHERE i.resolved_at > i.opened_at + make_interval(hours => sv.sla_hours)
                          OR i.resolved_at IS NULL)           AS breaches,
       round(100.0 * count(*) FILTER (WHERE i.resolved_at > i.opened_at + make_interval(hours => sv.sla_hours)
                          OR i.resolved_at IS NULL) / count(*), 1) AS breach_pct
FROM incident i
JOIN severity sv USING (severity_code)
JOIN service  s  USING (service_id)
JOIN team     t  USING (team_id)
WHERE i.opened_at >= '2026-01-01'
GROUP BY t.team_name, date_trunc('quarter', i.opened_at)
HAVING count(*) > 100
ORDER BY breach_pct DESC
LIMIT 10;

-- Q2. Top 3 slowest services (mean time to resolve) within each team
--     (CTE + DENSE_RANK window partitioned by team)
WITH mttr AS (
    SELECT s.team_id, s.service_name,
           avg(i.resolved_at - i.opened_at) AS mean_ttr,
           count(*)                          AS resolved
    FROM incident i
    JOIN service s USING (service_id)
    WHERE i.resolved_at IS NOT NULL
      AND i.severity_code IN ('SEV1','SEV2')
    GROUP BY s.team_id, s.service_name
), ranked AS (
    SELECT m.*, DENSE_RANK() OVER (PARTITION BY team_id ORDER BY mean_ttr DESC) AS rnk
    FROM mttr m
)
SELECT t.team_name, r.service_name, justify_hours(date_trunc('minute', r.mean_ttr)) AS mean_ttr, r.resolved, r.rnk
FROM ranked r JOIN team t USING (team_id)
WHERE r.rnk <= 3
ORDER BY t.team_name, r.rnk
LIMIT 12;

-- Q3a. Engineers carrying more than 10% above the average SEV1 commander load
--      in Q3 2026 (aggregate compared against a scalar subquery over a CTE)
WITH load AS (
    SELECT ir.engineer_id, count(*) AS sev1_commands
    FROM incident_responder ir
    JOIN incident i USING (incident_id)
    WHERE ir.role = 'commander' AND i.severity_code = 'SEV1'
      AND i.opened_at >= '2026-07-01' AND i.opened_at < '2026-10-01'
    GROUP BY ir.engineer_id
)
SELECT e.full_name, l.sev1_commands,
       round((SELECT avg(sev1_commands) FROM load), 1) AS avg_load
FROM load l JOIN engineer e USING (engineer_id)
WHERE l.sev1_commands > 1.10 * (SELECT avg(sev1_commands) FROM load)
ORDER BY l.sev1_commands DESC
LIMIT 10;

-- Q3b. Gold-tier services with NO SEV1 in the first half of September 2026
--      (anti-join via correlated NOT EXISTS)
SELECT s.service_name, t.team_name, s.region_code
FROM service s
JOIN team t USING (team_id)
WHERE s.tier = 'gold'
  AND NOT EXISTS (
        SELECT 1 FROM incident i
        WHERE i.service_id = s.service_id
          AND i.severity_code = 'SEV1'
          AND i.opened_at >= '2026-09-01' AND i.opened_at < '2026-09-16')
ORDER BY s.service_name;

-- Q4. Month-over-month change in SEV1/SEV2 volume per cloud provider
--     (LAG window function over an aggregated CTE)
WITH monthly AS (
    SELECT r.cloud_provider,
           date_trunc('month', i.opened_at)::date AS month,
           count(*) AS high_sev
    FROM incident i
    JOIN service s USING (service_id)
    JOIN region  r USING (region_code)
    WHERE i.severity_code IN ('SEV1','SEV2')
      AND i.opened_at >= '2026-04-01'
    GROUP BY 1, 2
)
SELECT cloud_provider, month, high_sev,
       high_sev - LAG(high_sev) OVER w                                        AS delta,
       round(100.0 * (high_sev - LAG(high_sev) OVER w) / LAG(high_sev) OVER w, 1) AS pct_change
FROM monthly
WINDOW w AS (PARTITION BY cloud_provider ORDER BY month)
ORDER BY cloud_provider, month;

-- Q5. 7-day moving average of daily SEV1 incidents (window frame), Sep 2026
WITH daily AS (
    SELECT opened_at::date AS day, count(*) AS sev1
    FROM incident
    WHERE severity_code = 'SEV1'
      AND opened_at >= '2026-09-01' AND opened_at < '2026-10-01'
    GROUP BY 1
)
SELECT day, sev1,
       round(avg(sev1) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS moving_avg_7d
FROM daily
ORDER BY day
LIMIT 10;

-- Q6. Incident volume rolled up by provider and tier with subtotals
--     (GROUPING SETS / ROLLUP, GROUPING() to label subtotal rows)
SELECT CASE WHEN GROUPING(r.cloud_provider) = 1 THEN 'ALL PROVIDERS' ELSE r.cloud_provider END AS provider,
       CASE WHEN GROUPING(s.tier) = 1 THEN 'all tiers' ELSE s.tier END AS tier,
       count(*) AS incidents,
       count(*) FILTER (WHERE i.severity_code = 'SEV1') AS sev1
FROM incident i
JOIN service s USING (service_id)
JOIN region  r USING (region_code)
WHERE i.opened_at >= '2026-01-01'
GROUP BY ROLLUP (r.cloud_provider, s.tier)
ORDER BY GROUPING(r.cloud_provider), provider, GROUPING(s.tier), tier;
