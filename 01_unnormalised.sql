-- =====================================================================
-- 01_unnormalised.sql
-- Starting point: a flat "incident tracker" export, the kind of sheet
-- ops teams keep before anyone designs a schema. Deliberately UNF.
-- =====================================================================
DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;

CREATE TABLE raw.incident_log_flat (
    incident_ref      TEXT,      -- e.g. INC-1001
    opened_at         TIMESTAMP,
    severity          TEXT,      -- 'SEV1'..'SEV4'
    severity_sla_hrs  INT,       -- depends on severity, not on the incident
    service_name      TEXT,
    service_tier      TEXT,      -- depends on service
    team_name         TEXT,      -- owning team of the service
    team_manager      TEXT,      -- depends on team
    team_manager_email TEXT,     -- depends on manager
    cloud_provider    TEXT,      -- depends on service
    region_code       TEXT,      -- depends on service
    region_name       TEXT,      -- depends on region_code
    responders        TEXT,      -- repeating group: 'alice;bob;carol'
    responder_emails  TEXT,      -- repeating group in parallel
    resolved_at       TIMESTAMP
);

INSERT INTO raw.incident_log_flat VALUES
('INC-1001','2026-03-02 09:10','SEV1',4,'payments-api','gold','Platform','Priya Nair','priya.nair@example.org','AWS','ap-southeast-2','Sydney','alice;bob','alice@example.org;bob@example.org','2026-03-02 11:40'),
('INC-1002','2026-03-03 14:00','SEV3',48,'payments-api','gold','Platform','Priya Nair','priya.nair@example.org','AWS','ap-southeast-2','Sydney','carol','carol@example.org','2026-03-04 10:00'),
('INC-1003','2026-03-05 22:15','SEV2',12,'auth-service','gold','Identity','Tom Hale','tom.hale@example.org','Azure','australiaeast','Sydney (Azure)','bob;dave','bob@example.org;dave@example.org','2026-03-06 03:00'),
('INC-1004','2026-03-07 08:30','SEV4',120,'reporting-etl','bronze','Data','Mei Lin','mei.lin@example.org','GCP','australia-southeast1','Sydney (GCP)','erin','erin@example.org',NULL);

-- Anomalies this design causes (demonstrated in the report):
--  * Update anomaly : Priya's email is stored on every Platform incident row.
--  * Insert anomaly : cannot record a new team/service until it has an incident.
--  * Delete anomaly : deleting INC-1004 loses the fact that Mei Lin manages Data.
--  * 1NF violation  : responders / responder_emails are multi-valued strings.
