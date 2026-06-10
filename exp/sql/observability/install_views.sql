DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_buffercache') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_buffercache';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pgmeminfo') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pgmeminfo';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'system_stats') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS system_stats';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_wait_sampling')
     AND coalesce(current_setting('shared_preload_libraries', true), '') ~ '(^|,)[[:space:]]*pg_wait_sampling[[:space:]]*(,|$)' THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_wait_sampling';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_kcache')
     AND coalesce(current_setting('shared_preload_libraries', true), '') ~ '(^|,)[[:space:]]*pg_stat_kcache[[:space:]]*(,|$)' THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_stat_kcache';
  END IF;
END $$;

select 1;
