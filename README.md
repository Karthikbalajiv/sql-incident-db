# Incident Management DB: Normalisation, Complex Queries, Query Optimisation

project for a credit application in **Data in Information Systems**.
Author: Karthik Balaji Viswanathan.

A PostgreSQL 16 project modelled on cloud incident-management data. It takes a flat
ops spreadsheet through normalisation to BCNF, scales it to 1.5M incidents, answers
operational questions with advanced SQL, and measures four query optimisations with
`EXPLAIN (ANALYZE, BUFFERS)`.

| File | Covers |
|---|---|
| `01_unnormalised.sql` | Flat (UNF) source table and its update/insert/delete anomalies |
| `02_schema_3nf.sql` | Functional dependencies, 1NF to BCNF decomposition, DDL with constraints, lossless migration |
| `03_seed.sql` | Deterministic data generation: 1.5M incidents, ~3M responder rows |
| `04_complex_queries.sql` | Multi-table joins, CTEs, DENSE_RANK, LAG, moving-window frames, correlated EXISTS / NOT EXISTS, FILTER, ROLLUP |
| `05_optimisation.sql` | FK indexing, composite-key column order, sargable rewrites, partial indexes |
| `er.dot`, `output/er_diagram.png` | ER diagram (crow's foot) |
| `output/*.txt` | Captured query results and execution plans |

## Results (from `output/05_optimisation_output.txt`)

| Case | Change | Before | After |
|---|---|---|---|
| 1 | Index the unindexed FK `(service_id, opened_at)` | 163.6 ms, Seq Scan | 2.9 ms, Bitmap Index Scan |
| 2 | Index led by `engineer_id` (PK leads with `incident_id`) | 394.5 ms, Seq Scan | 2.3 ms, Index Only Scan |
| 3 | Rewrite `date_trunc(...) = x` as a half-open range | 488.9 ms, Seq Scan | 0.5 ms, Index Only Scan |
| 4 | Partial index on open SEV1/SEV2 incidents (176 kB) | 12.0 ms | 0.4 ms |

## Run it

```bash
createdb credit_lab
psql -d credit_lab -f 01_unnormalised.sql
psql -d credit_lab -f 02_schema_3nf.sql
psql -d credit_lab -f 03_seed.sql          # ~1.5 minutes
psql -d credit_lab -f 04_complex_queries.sql
psql -d credit_lab -f 05_optimisation.sql  # run twice; use the second run's timings
```

Timings vary by machine. Plan shapes, row counts and buffer counts are what show the effect.
