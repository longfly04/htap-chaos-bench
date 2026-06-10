DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bench') THEN
    CREATE ROLE bench LOGIN PASSWORD 'bench_123' SUPERUSER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exporter') THEN
    CREATE ROLE exporter LOGIN PASSWORD 'exporter_123';
  END IF;
END
$$;

GRANT pg_read_all_stats TO exporter;
GRANT pg_monitor TO exporter;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
