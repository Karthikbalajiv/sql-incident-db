-- =====================================================================
-- 05_optimisation.sql
-- Query optimisation case studies. Each case: run EXPLAIN (ANALYZE,
-- BUFFERS) BEFORE, apply ONE change, ANALYZE, run AFTER, compare plans.
-- Re-runnable: indexes created here are dropped first.
-- =====================================================================
SET search_path = ops;
SET max_parallel_workers_per_gather = 0;   -- single-process plans, easier to compare
DROP INDEX IF EXISTS ix_incident_service_opened, ix_responder_engineer,
                     ix_incident_opened, ix_incident_open_queue;

-- ---------------------------------------------------------------------
-- CASE 1: Foreign key without an index
-- PostgreSQL does NOT index FK columns automatically. "All incidents for
-- one service in Q3 2026" must therefore scan all 1.5M rows.
-- Fix: composite B-tree (service_id, opened_at) - equality column first,
-- range column second, so both predicates are satisfied by the index.
-- ---------------------------------------------------------------------
\echo '=== CASE 1 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT incident_ref, severity_code, opened_at, resolved_at
FROM incident
WHERE service_id = 42
  AND opened_at >= '2026-07-01' AND opened_at < '2026-10-01';

CREATE INDEX ix_incident_service_opened ON incident (service_id, opened_at);
ANALYZE incident;

\echo '=== CASE 1 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT incident_ref, severity_code, opened_at, resolved_at
FROM incident
WHERE service_id = 42
  AND opened_at >= '2026-07-01' AND opened_at < '2026-10-01';

-- ---------------------------------------------------------------------
-- CASE 2: Composite primary key column order
-- PK (incident_id, engineer_id) serves lookups by incident, but a B-tree
-- cannot seek on its second column alone, so "workload for engineer 17"
-- scans ~3M rows. Fix: a second index led by engineer_id.
-- ---------------------------------------------------------------------
\echo '=== CASE 2 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT ir.role, count(*)
FROM incident_responder ir
WHERE ir.engineer_id = 17
GROUP BY ir.role;

CREATE INDEX ix_responder_engineer ON incident_responder (engineer_id, role);
ANALYZE incident_responder;

\echo '=== CASE 2 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT ir.role, count(*)
FROM incident_responder ir
WHERE ir.engineer_id = 17
GROUP BY ir.role;

-- ---------------------------------------------------------------------
-- CASE 3: Non-sargable predicate
-- Wrapping the column in a function (date_trunc) hides it from any index
-- on opened_at. Rewriting as a half-open range makes it sargable.
-- ---------------------------------------------------------------------
CREATE INDEX ix_incident_opened ON incident (opened_at);
ANALYZE incident;

\echo '=== CASE 3 BEFORE (function on column, index exists but unusable) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM incident
WHERE date_trunc('day', opened_at) = '2026-09-15';

\echo '=== CASE 3 AFTER (same result, sargable range) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM incident
WHERE opened_at >= '2026-09-15' AND opened_at < '2026-09-16';

-- ---------------------------------------------------------------------
-- CASE 4: Partial index for a hot, selective subset
-- The on-call dashboard only ever asks for OPEN SEV1/SEV2 incidents
-- (~0.5% of rows). A partial index covers exactly that subset and is a
-- fraction of the size of a full index.
-- ---------------------------------------------------------------------
\echo '=== CASE 4 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.incident_ref, i.severity_code, i.opened_at, s.service_name
FROM incident i JOIN service s USING (service_id)
WHERE i.resolved_at IS NULL AND i.severity_code IN ('SEV1','SEV2')
ORDER BY i.opened_at DESC
LIMIT 50;

CREATE INDEX ix_incident_open_queue ON incident (opened_at DESC)
    WHERE resolved_at IS NULL AND severity_code IN ('SEV1','SEV2');
ANALYZE incident;

\echo '=== CASE 4 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.incident_ref, i.severity_code, i.opened_at, s.service_name
FROM incident i JOIN service s USING (service_id)
WHERE i.resolved_at IS NULL AND i.severity_code IN ('SEV1','SEV2')
ORDER BY i.opened_at DESC
LIMIT 50;

\echo '=== Index sizes ==='
SELECT indexrelname AS index, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'ops' AND relname IN ('incident','incident_responder')
ORDER BY pg_relation_size(indexrelid) DESC;
