-- =====================================================================
-- 03_seed.sql
-- Scales the normalised model up to realistic volume so that query
-- plans and optimisation effects are measurable.
--   ~250 engineers, 25 teams, 400 services, 1,500,000 incidents,
--   ~3.4M responder assignments. Deterministic via setseed().
-- =====================================================================
SET search_path = ops;
SELECT setseed(0.42);

INSERT INTO region VALUES
 ('us-east-1','N. Virginia','AWS'),
 ('eu-west-1','Ireland','AWS'),
 ('southeastasia','Singapore (Azure)','Azure'),
 ('us-central1','Iowa (GCP)','GCP')
ON CONFLICT DO NOTHING;

INSERT INTO engineer (full_name, email)
SELECT 'Engineer ' || g, 'eng' || g || '@example.org'
FROM generate_series(1, 245) g;

INSERT INTO team (team_name, manager_id)
SELECT 'Team ' || g, (SELECT engineer_id FROM engineer ORDER BY engineer_id OFFSET g LIMIT 1)
FROM generate_series(1, 22) g;

INSERT INTO service (service_name, tier, team_id, region_code)
SELECT 'svc-' || g,
       (ARRAY['gold','silver','silver','bronze','bronze'])[1 + floor(random()*5)::int],
       (SELECT team_id FROM team ORDER BY team_id OFFSET (g % (SELECT count(*) FROM team)) LIMIT 1),
       (ARRAY['ap-southeast-2','australiaeast','australia-southeast1',
              'us-east-1','eu-west-1','southeastasia','us-central1'])[1 + floor(random()*7)::int]
FROM generate_series(1, 397) g;

-- 1.5M incidents across 2024-01-01 .. 2026-09-30, skewed toward lower severity
INSERT INTO incident (incident_ref, service_id, severity_code, opened_at, resolved_at)
SELECT 'INC-' || (100000 + g),
       1 + floor(random() * 400)::int,
       sev,
       opened,
       CASE WHEN random() < 0.03 THEN NULL     -- ~3% still open
            ELSE opened + make_interval(mins => (random() * sla * 60 * 1.6)::int)
       END
FROM (
    SELECT g,
           CASE WHEN r < 0.04 THEN 'SEV1' WHEN r < 0.16 THEN 'SEV2'
                WHEN r < 0.55 THEN 'SEV3' ELSE 'SEV4' END AS sev,
           CASE WHEN r < 0.04 THEN 4 WHEN r < 0.16 THEN 12
                WHEN r < 0.55 THEN 48 ELSE 120 END        AS sla,
           timestamp '2024-01-01' + random() * (timestamp '2026-09-30' - timestamp '2024-01-01') AS opened
    FROM (SELECT g, random() AS r FROM generate_series(1, 1500000) g) x
) y;

-- 1 commander + 0-3 responders per incident
INSERT INTO incident_responder (incident_id, engineer_id, role)
SELECT DISTINCT ON (incident_id, engineer_id) incident_id, engineer_id, role
FROM (
    SELECT i.incident_id,
           1 + floor(random() * 250)::int AS engineer_id,
           CASE WHEN k = 0 THEN 'commander' ELSE 'responder' END AS role
    FROM incident i
    CROSS JOIN LATERAL generate_series(0, floor(random()*4)::int) k
    WHERE i.incident_id > 4
) z
ORDER BY incident_id, engineer_id, role;

ANALYZE;
