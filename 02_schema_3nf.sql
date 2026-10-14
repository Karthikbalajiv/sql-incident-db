-- =====================================================================
-- 02_schema_3nf.sql
-- Normalised design derived from raw.incident_log_flat.
--
-- Functional dependencies identified in the flat table:
--   FD1 incident_ref        -> opened_at, resolved_at, severity, service_name
--   FD2 severity            -> severity_sla_hrs
--   FD3 service_name        -> service_tier, team_name, region_code
--   FD4 team_name           -> team_manager
--   FD5 team_manager        -> team_manager_email      (person -> email)
--   FD6 region_code         -> region_name, cloud_provider
--   FD7 responder           -> responder_email
--   Multi-valued: incident_ref ->> responders
--
-- 1NF : split the repeating group (responders) into incident_responder.
-- 2NF : incident_responder key is (incident_id, engineer_id); responder
--       email depended on engineer only (partial dependency) -> engineer.
-- 3NF : remove transitive dependencies via service, team, region,
--       severity (FD2..FD6) into their own tables.
-- BCNF: every determinant above is now a candidate key of its table.
-- =====================================================================
DROP SCHEMA IF EXISTS ops CASCADE;
CREATE SCHEMA ops;
SET search_path = ops;

CREATE TABLE region (
    region_code     TEXT PRIMARY KEY,
    region_name     TEXT NOT NULL,
    cloud_provider  TEXT NOT NULL CHECK (cloud_provider IN ('AWS','Azure','GCP'))
);

CREATE TABLE severity (
    severity_code   TEXT PRIMARY KEY CHECK (severity_code IN ('SEV1','SEV2','SEV3','SEV4')),
    sla_hours       INT  NOT NULL CHECK (sla_hours > 0)
);

CREATE TABLE engineer (
    engineer_id     INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name       TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE
);

CREATE TABLE team (
    team_id         INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    team_name       TEXT NOT NULL UNIQUE,
    manager_id      INT  NOT NULL REFERENCES engineer(engineer_id)
);

CREATE TABLE service (
    service_id      INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_name    TEXT NOT NULL UNIQUE,
    tier            TEXT NOT NULL CHECK (tier IN ('gold','silver','bronze')),
    team_id         INT  NOT NULL REFERENCES team(team_id),
    region_code     TEXT NOT NULL REFERENCES region(region_code)
);

CREATE TABLE incident (
    incident_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incident_ref    TEXT   NOT NULL UNIQUE,
    service_id      INT    NOT NULL REFERENCES service(service_id),
    severity_code   TEXT   NOT NULL REFERENCES severity(severity_code),
    opened_at       TIMESTAMP NOT NULL,
    resolved_at     TIMESTAMP,
    CHECK (resolved_at IS NULL OR resolved_at >= opened_at)
);

-- Resolves the M:N between incident and engineer (and the 1NF repeating group)
CREATE TABLE incident_responder (
    incident_id     BIGINT NOT NULL REFERENCES incident(incident_id) ON DELETE CASCADE,
    engineer_id     INT    NOT NULL REFERENCES engineer(engineer_id),
    role            TEXT   NOT NULL CHECK (role IN ('commander','responder','scribe')),
    PRIMARY KEY (incident_id, engineer_id)
);

-- Migration of the four sample flat rows into the normalised model
INSERT INTO region VALUES
 ('ap-southeast-2','Sydney','AWS'),
 ('australiaeast','Sydney (Azure)','Azure'),
 ('australia-southeast1','Sydney (GCP)','GCP');
INSERT INTO severity VALUES ('SEV1',4),('SEV2',12),('SEV3',48),('SEV4',120);

INSERT INTO engineer (full_name, email)
SELECT DISTINCT team_manager, team_manager_email FROM raw.incident_log_flat
UNION
SELECT r.name, r.email
FROM raw.incident_log_flat f
CROSS JOIN LATERAL unnest(string_to_array(f.responders,';'),
                          string_to_array(f.responder_emails,';')) AS r(name,email);

INSERT INTO team (team_name, manager_id)
SELECT DISTINCT f.team_name, e.engineer_id
FROM raw.incident_log_flat f JOIN engineer e ON e.email = f.team_manager_email;

INSERT INTO service (service_name, tier, team_id, region_code)
SELECT DISTINCT f.service_name, f.service_tier, t.team_id, f.region_code
FROM raw.incident_log_flat f JOIN team t ON t.team_name = f.team_name;

INSERT INTO incident (incident_ref, service_id, severity_code, opened_at, resolved_at)
SELECT f.incident_ref, s.service_id, f.severity, f.opened_at, f.resolved_at
FROM raw.incident_log_flat f JOIN service s ON s.service_name = f.service_name;

INSERT INTO incident_responder (incident_id, engineer_id, role)
SELECT i.incident_id, e.engineer_id,
       CASE WHEN r.ord = 1 THEN 'commander' ELSE 'responder' END
FROM raw.incident_log_flat f
JOIN incident i ON i.incident_ref = f.incident_ref
CROSS JOIN LATERAL unnest(string_to_array(f.responder_emails,';')) WITH ORDINALITY AS r(email, ord)
JOIN engineer e ON e.email = r.email;
