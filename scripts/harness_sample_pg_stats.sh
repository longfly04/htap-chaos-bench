#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

RUN_DIR=""
DATABASE="${BENCHMARK_DB_NAME:-postgres}"
INTERVAL_SECONDS="${OBSERVE_SAMPLING_INTERVAL_SECONDS:-5}"
MAX_SAMPLES="0"
PHASE_FILE=""
ADAPTER_ROOT="${ADAPTER_ROOT:-$PROJECT_ROOT/exp/adapters/${SYSTEM:-pg-like}}"
PG_ACTIVITY_ENABLED="${OBSERVE_PG_ACTIVITY_ENABLED:-false}"
PG_ACTIVITY_TIMEOUT_SECONDS="${OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS:-3}"
PG_ACTIVITY_REFRESH_SECONDS="${OBSERVE_PG_ACTIVITY_REFRESH_SECONDS:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --database)
      DATABASE="$2"
      shift 2
      ;;
    --interval-seconds)
      INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --max-samples)
      MAX_SAMPLES="$2"
      shift 2
      ;;
    --phase-file)
      PHASE_FILE="$2"
      shift 2
      ;;
    --adapter-root)
      ADAPTER_ROOT="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"
[[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || fail "--interval-seconds must be an integer"
(( INTERVAL_SECONDS > 0 )) || fail "--interval-seconds must be positive"
[[ "$MAX_SAMPLES" =~ ^[0-9]+$ ]] || fail "--max-samples must be an integer"
[[ "$PG_ACTIVITY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || fail "OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS must be an integer"
[[ "$PG_ACTIVITY_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || fail "OBSERVE_PG_ACTIVITY_REFRESH_SECONDS must be an integer"

TIMELINE_DIR="$RUN_DIR/observability/timeline"
SYSTEM_FILE="$TIMELINE_DIR/system-metrics.csv"
ACTIVITY_FILE="$TIMELINE_DIR/activity-metrics.csv"
STATEMENT_FILE="$TIMELINE_DIR/statement-metrics.csv"
IO_FILE="$TIMELINE_DIR/io-metrics.csv"
WAIT_FILE="$TIMELINE_DIR/wait-metrics.csv"
MEMORY_FILE="$TIMELINE_DIR/memory-metrics.csv"
KCACHE_FILE="$TIMELINE_DIR/kcache-metrics.csv"
PG_ACTIVITY_DIR="$TIMELINE_DIR/pg-activity"
PG_ACTIVITY_MANIFEST_FILE="$TIMELINE_DIR/pg-activity-snapshots.jsonl"
CAPABILITIES_FILE="$TIMELINE_DIR/capabilities.json"
METADATA_FILE="$TIMELINE_DIR/plot-metadata.json"
mkdir -p "$TIMELINE_DIR" "$PG_ACTIVITY_DIR"

current_phase() {
  if [[ -n "$PHASE_FILE" && -f "$PHASE_FILE" ]]; then
    tr -d '\r\n' < "$PHASE_FILE"
    return
  fi
  printf 'mixed'
}

relation_exists() {
  local relname="$1"
  [[ "$(run_psql "$DATABASE" "select to_regclass('$relname') is not null")" == "t" ]]
}

extension_exists() {
  local extname="$1"
  [[ "$(run_psql "$DATABASE" "select exists(select 1 from pg_extension where extname = '$extname')")" == "t" ]]
}

function_exists() {
  local funcname="$1"
  [[ "$(run_psql "$DATABASE" "select exists(select 1 from pg_proc where proname = '$funcname')")" == "t" ]]
}

bool_json() {
  if [[ "$1" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

init_csv() {
  local path="$1"
  local header="$2"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$header" > "$path"
  fi
}

load_adapter_capabilities() {
  ADAPTER_ID=""
  PLAN_CAPTURE=""
  LOCK_OBSERVATION=""
  TEMP_SPILL_METRICS=""
  SHARED_MEMORY_CONTROL=""
  SESSION_MEMORY_CONTROL=""
  PLAN_CAPTURE_FORMAT=""

  local capabilities_script="$ADAPTER_ROOT/capabilities.sh"
  if [[ ! -f "$capabilities_script" ]]; then
    return
  fi
  while IFS='=' read -r key value; do
    case "$key" in
      ADAPTER_ID|PLAN_CAPTURE|LOCK_OBSERVATION|TEMP_SPILL_METRICS|SHARED_MEMORY_CONTROL|SESSION_MEMORY_CONTROL|PLAN_CAPTURE_FORMAT)
        printf -v "$key" '%s' "$value"
        ;;
    esac
  done < <(bash "$capabilities_script")
}

load_adapter_capabilities

PG_STAT_STATEMENTS_AVAILABLE="false"
PG_WAIT_SAMPLING_AVAILABLE="false"
PG_STAT_IO_AVAILABLE="false"
PG_BUFFERCACHE_AVAILABLE="false"
SESSION_MEMORY_VIEW_AVAILABLE="false"
PGMEMINFO_INSTALLED="false"
SYSTEM_STATS_AVAILABLE="false"
PG_STAT_KCACHE_AVAILABLE="false"

if relation_exists 'pg_stat_statements'; then
  PG_STAT_STATEMENTS_AVAILABLE="true"
fi
if relation_exists 'pg_wait_sampling_profile'; then
  PG_WAIT_SAMPLING_AVAILABLE="true"
fi
if relation_exists 'pg_stat_io'; then
  PG_STAT_IO_AVAILABLE="true"
fi
if relation_exists 'pg_buffercache'; then
  PG_BUFFERCACHE_AVAILABLE="true"
fi
if relation_exists 'pg_backend_memory_contexts'; then
  SESSION_MEMORY_VIEW_AVAILABLE="true"
fi
if extension_exists 'pgmeminfo'; then
  PGMEMINFO_INSTALLED="true"
fi
if function_exists 'pg_sys_memory_info' && function_exists 'pg_sys_cpu_memory_by_process'; then
  SYSTEM_STATS_AVAILABLE="true"
fi
if relation_exists 'pg_stat_kcache'; then
  PG_STAT_KCACHE_AVAILABLE="true"
fi

cat > "$CAPABILITIES_FILE" <<EOF
{
  "adapter_id": "${ADAPTER_ID:-}",
  "plan_capture": "${PLAN_CAPTURE:-}",
  "lock_observation": "${LOCK_OBSERVATION:-}",
  "temp_spill_metrics": "${TEMP_SPILL_METRICS:-}",
  "shared_memory_control": "${SHARED_MEMORY_CONTROL:-}",
  "session_memory_control": "${SESSION_MEMORY_CONTROL:-}",
  "plan_capture_format": "${PLAN_CAPTURE_FORMAT:-}",
  "pg_stat_statements_available": $(bool_json "$PG_STAT_STATEMENTS_AVAILABLE"),
  "pg_wait_sampling_profile_available": $(bool_json "$PG_WAIT_SAMPLING_AVAILABLE"),
  "pg_stat_io_available": $(bool_json "$PG_STAT_IO_AVAILABLE"),
  "pg_buffercache_available": $(bool_json "$PG_BUFFERCACHE_AVAILABLE"),
  "pg_backend_memory_contexts_available": $(bool_json "$SESSION_MEMORY_VIEW_AVAILABLE"),
  "pgmeminfo_installed": $(bool_json "$PGMEMINFO_INSTALLED"),
  "system_stats_available": $(bool_json "$SYSTEM_STATS_AVAILABLE"),
  "pg_stat_kcache_available": $(bool_json "$PG_STAT_KCACHE_AVAILABLE"),
  "pg_activity_enabled": $(bool_json "$PG_ACTIVITY_ENABLED"),
  "wait_sampling_observation": "$( [[ "$PG_WAIT_SAMPLING_AVAILABLE" == "true" ]] && printf 'supported' || printf 'unsupported' )",
  "buffer_cache_observation": "$( [[ "$PG_BUFFERCACHE_AVAILABLE" == "true" ]] && printf 'supported' || printf 'unsupported' )",
  "system_memory_observation": "$( [[ "$SYSTEM_STATS_AVAILABLE" == "true" ]] && printf 'supported' || printf 'unsupported' )",
  "session_memory_observation": "$( if [[ "$SYSTEM_STATS_AVAILABLE" == "true" ]]; then printf 'supported'; elif [[ "$SESSION_MEMORY_VIEW_AVAILABLE" == "true" ]]; then printf 'sampler-backend-only'; else printf 'unsupported'; fi )",
  "kcache_observation": "$( [[ "$PG_STAT_KCACHE_AVAILABLE" == "true" ]] && printf 'supported' || printf 'unsupported' )",
  "pg_activity_capture_mode": "best-effort-csv-snapshots"
}
EOF

cat > "$METADATA_FILE" <<EOF
{
  "run_dir": "$RUN_DIR",
  "database": "$DATABASE",
  "interval_seconds": $INTERVAL_SECONDS,
  "metrics_profile": "${OBSERVE_METRICS_PROFILE:-mixed-default}",
  "plot_profile": "${PLOT_PROFILE:-mixed-default}",
  "plot_dpi": ${PLOT_DPI:-300},
  "pg_activity_enabled": $(bool_json "$PG_ACTIVITY_ENABLED"),
  "pg_activity_timeout_seconds": ${PG_ACTIVITY_TIMEOUT_SECONDS:-3},
  "pg_activity_refresh_seconds": ${PG_ACTIVITY_REFRESH_SECONDS:-1},
  "pg_activity_manifest": "observability/timeline/pg-activity-snapshots.jsonl"
}
EOF

init_csv "$SYSTEM_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,datname,xact_commit,xact_rollback,blks_read,blks_hit,tup_returned,tup_fetched,tup_inserted,tup_updated,tup_deleted,temp_files,temp_bytes,deadlocks"
init_csv "$ACTIVITY_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,active_sessions,idle_sessions,idle_in_txn_sessions,waiting_sessions,lock_wait_sessions,io_wait_sessions,lwlock_wait_sessions,blocked_sessions,tp_sessions,ap_sessions,chaos_sessions,longest_xact_age_seconds"
init_csv "$STATEMENT_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,total_calls,total_exec_time_ms,total_rows,shared_blks_hit,shared_blks_read,temp_blks_read,temp_blks_written"
init_csv "$IO_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,reads,read_time_ms,writes,write_time_ms,writebacks,writeback_time_ms,extends,extend_time_ms,fsyncs,fsync_time_ms,hits,evictions,reuses"
init_csv "$WAIT_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,total_wait_samples,lock_wait_samples,lwlock_wait_samples,io_wait_samples,client_wait_samples,ipc_wait_samples,timeout_wait_samples,activity_wait_samples"
init_csv "$MEMORY_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,db_cached_buffers,db_cached_mb,db_dirty_buffers,db_dirty_mb,pinned_backends,avg_usagecount,system_total_mb,system_used_mb,system_free_mb,system_cache_mb,pg_all_backend_mb,pg_client_backend_mb,tp_backend_mb,ap_backend_mb,chaos_backend_mb,other_backend_mb,sampler_backend_total_mb,sampler_backend_used_mb,sampler_backend_free_mb"
init_csv "$KCACHE_FILE" "sample_index,ts_epoch_ms,elapsed_seconds,phase,exec_user_time_seconds,exec_system_time_seconds,exec_reads_bytes,exec_writes_bytes,exec_reads_blks,exec_writes_blks,exec_nvcsws,exec_nivcsws"

append_system_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  local row
  row="$(run_psql "$DATABASE" "select current_database(), coalesce(xact_commit,0), coalesce(xact_rollback,0), coalesce(blks_read,0), coalesce(blks_hit,0), coalesce(tup_returned,0), coalesce(tup_fetched,0), coalesce(tup_inserted,0), coalesce(tup_updated,0), coalesce(tup_deleted,0), coalesce(temp_files,0), coalesce(temp_bytes,0), coalesce(deadlocks,0) from pg_stat_database where datname = current_database()")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r datname xact_commit xact_rollback blks_read blks_hit tup_returned tup_fetched tup_inserted tup_updated tup_deleted temp_files temp_bytes deadlocks <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$datname" "$xact_commit" "$xact_rollback" "$blks_read" "$blks_hit" "$tup_returned" "$tup_fetched" "$tup_inserted" "$tup_updated" "$tup_deleted" "$temp_files" "$temp_bytes" "$deadlocks" >> "$SYSTEM_FILE"
}

append_activity_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  local row
  row="$(run_psql "$DATABASE" "select count(*) filter (where pid <> pg_backend_pid() and state = 'active'), count(*) filter (where pid <> pg_backend_pid() and state = 'idle'), count(*) filter (where pid <> pg_backend_pid() and state = 'idle in transaction'), count(*) filter (where pid <> pg_backend_pid() and wait_event_type is not null), count(*) filter (where pid <> pg_backend_pid() and wait_event_type = 'Lock'), count(*) filter (where pid <> pg_backend_pid() and wait_event_type = 'IO'), count(*) filter (where pid <> pg_backend_pid() and wait_event_type = 'LWLock'), count(*) filter (where pid <> pg_backend_pid() and cardinality(pg_blocking_pids(pid)) > 0), count(*) filter (where pid <> pg_backend_pid() and application_name like 'paper1-jobtp%'), count(*) filter (where pid <> pg_backend_pid() and application_name like 'paper1-ap/%'), count(*) filter (where pid <> pg_backend_pid() and application_name like 'paper1-chaos/%'), coalesce(max(extract(epoch from clock_timestamp() - xact_start)), 0)::bigint from pg_stat_activity where datname = current_database()")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r active_sessions idle_sessions idle_in_txn_sessions waiting_sessions lock_wait_sessions io_wait_sessions lwlock_wait_sessions blocked_sessions tp_sessions ap_sessions chaos_sessions longest_xact_age_seconds <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$active_sessions" "$idle_sessions" "$idle_in_txn_sessions" "$waiting_sessions" "$lock_wait_sessions" "$io_wait_sessions" "$lwlock_wait_sessions" "$blocked_sessions" "$tp_sessions" "$ap_sessions" "$chaos_sessions" "$longest_xact_age_seconds" >> "$ACTIVITY_FILE"
}

append_statement_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  if [[ "$PG_STAT_STATEMENTS_AVAILABLE" != "true" ]]; then
    return 0
  fi
  local row
  row="$(run_psql "$DATABASE" "select coalesce(sum(calls),0), coalesce(sum(total_exec_time),0), coalesce(sum(rows),0), coalesce(sum(shared_blks_hit),0), coalesce(sum(shared_blks_read),0), coalesce(sum(temp_blks_read),0), coalesce(sum(temp_blks_written),0) from pg_stat_statements where dbid = (select oid from pg_database where datname = current_database())")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r total_calls total_exec_time total_rows shared_blks_hit shared_blks_read temp_blks_read temp_blks_written <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$total_calls" "$total_exec_time" "$total_rows" "$shared_blks_hit" "$shared_blks_read" "$temp_blks_read" "$temp_blks_written" >> "$STATEMENT_FILE"
}

append_io_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  if [[ "$PG_STAT_IO_AVAILABLE" != "true" ]]; then
    return 0
  fi
  local row
  row="$(run_psql "$DATABASE" "select coalesce(sum(reads),0), coalesce(sum(read_time),0), coalesce(sum(writes),0), coalesce(sum(write_time),0), coalesce(sum(writebacks),0), coalesce(sum(writeback_time),0), coalesce(sum(extends),0), coalesce(sum(extend_time),0), coalesce(sum(fsyncs),0), coalesce(sum(fsync_time),0), coalesce(sum(hits),0), coalesce(sum(evictions),0), coalesce(sum(reuses),0) from pg_stat_io")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r reads read_time writes write_time writebacks writeback_time extends extend_time fsyncs fsync_time hits evictions reuses <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$reads" "$read_time" "$writes" "$write_time" "$writebacks" "$writeback_time" "$extends" "$extend_time" "$fsyncs" "$fsync_time" "$hits" "$evictions" "$reuses" >> "$IO_FILE"
}

append_wait_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  if [[ "$PG_WAIT_SAMPLING_AVAILABLE" != "true" ]]; then
    return 0
  fi
  local row
  row="$(run_psql "$DATABASE" "select coalesce(sum(count),0), coalesce(sum(count) filter (where event_type = 'Lock'),0), coalesce(sum(count) filter (where event_type = 'LWLock' or event_type like 'LWLock%'),0), coalesce(sum(count) filter (where event_type = 'IO'),0), coalesce(sum(count) filter (where event_type = 'Client'),0), coalesce(sum(count) filter (where event_type = 'IPC'),0), coalesce(sum(count) filter (where event_type = 'Timeout'),0), coalesce(sum(count) filter (where event_type = 'Activity'),0) from pg_wait_sampling_profile")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r total_wait_samples lock_wait_samples lwlock_wait_samples io_wait_samples client_wait_samples ipc_wait_samples timeout_wait_samples activity_wait_samples <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$total_wait_samples" "$lock_wait_samples" "$lwlock_wait_samples" "$io_wait_samples" "$client_wait_samples" "$ipc_wait_samples" "$timeout_wait_samples" "$activity_wait_samples" >> "$WAIT_FILE"
}

append_kcache_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  if [[ "$PG_STAT_KCACHE_AVAILABLE" != "true" ]]; then
    return 0
  fi
  local row
  row="$(run_psql "$DATABASE" "select round(coalesce(sum(exec_user_time),0)::numeric, 6), round(coalesce(sum(exec_system_time),0)::numeric, 6), coalesce(sum(exec_reads),0), coalesce(sum(exec_writes),0), coalesce(sum(exec_reads_blks),0), coalesce(sum(exec_writes_blks),0), coalesce(sum(exec_nvcsws),0), coalesce(sum(exec_nivcsws),0) from pg_stat_kcache where datname = current_database()")"
  [[ -n "$row" ]] || return 0
  IFS='|' read -r exec_user_time_seconds exec_system_time_seconds exec_reads_bytes exec_writes_bytes exec_reads_blks exec_writes_blks exec_nvcsws exec_nivcsws <<< "$row"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$exec_user_time_seconds" "$exec_system_time_seconds" "$exec_reads_bytes" "$exec_writes_bytes" "$exec_reads_blks" "$exec_writes_blks" "$exec_nvcsws" "$exec_nivcsws" >> "$KCACHE_FILE"
}

append_memory_sample() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"
  local db_cached_buffers="0"
  local db_cached_mb="0"
  local db_dirty_buffers="0"
  local db_dirty_mb="0"
  local pinned_backends="0"
  local avg_usagecount="0"
  local system_total_mb="0"
  local system_used_mb="0"
  local system_free_mb="0"
  local system_cache_mb="0"
  local pg_all_backend_mb="0"
  local pg_client_backend_mb="0"
  local tp_backend_mb="0"
  local ap_backend_mb="0"
  local chaos_backend_mb="0"
  local other_backend_mb="0"
  local sampler_backend_total_mb="0"
  local sampler_backend_used_mb="0"
  local sampler_backend_free_mb="0"
  local row

  if [[ "$PG_BUFFERCACHE_AVAILABLE" == "true" ]]; then
    row="$(run_psql "$DATABASE" "with current_db as (select oid as db_oid from pg_database where datname = current_database()) select count(*) filter (where reldatabase in (0, (select db_oid from current_db))), round((count(*) filter (where reldatabase in (0, (select db_oid from current_db))) * current_setting('block_size')::bigint)::numeric / 1048576, 3), count(*) filter (where reldatabase in (0, (select db_oid from current_db)) and isdirty), round((count(*) filter (where reldatabase in (0, (select db_oid from current_db)) and isdirty) * current_setting('block_size')::bigint)::numeric / 1048576, 3), coalesce(sum(pinning_backends),0), round(coalesce(avg(usagecount),0)::numeric, 3) from pg_buffercache")"
    if [[ -n "$row" ]]; then
      IFS='|' read -r db_cached_buffers db_cached_mb db_dirty_buffers db_dirty_mb pinned_backends avg_usagecount <<< "$row"
    fi
  fi

  if [[ "$SYSTEM_STATS_AVAILABLE" == "true" ]]; then
    row="$(run_psql "$DATABASE" "with system_memory as (select round(coalesce(total_memory,0)::numeric / 1048576, 3) as system_total_mb, round(coalesce(used_memory,0)::numeric / 1048576, 3) as system_used_mb, round(coalesce(free_memory,0)::numeric / 1048576, 3) as system_free_mb, round(coalesce(cache_total,0)::numeric / 1048576, 3) as system_cache_mb from pg_sys_memory_info()), backend_memory as (select round(coalesce(sum(p.memory_bytes),0)::numeric / 1048576, 3) as pg_all_backend_mb, round(coalesce(sum(p.memory_bytes) filter (where a.backend_type = 'client backend'),0)::numeric / 1048576, 3) as pg_client_backend_mb, round(coalesce(sum(p.memory_bytes) filter (where coalesce(a.application_name,'') like 'paper1-jobtp%'),0)::numeric / 1048576, 3) as tp_backend_mb, round(coalesce(sum(p.memory_bytes) filter (where coalesce(a.application_name,'') like 'paper1-ap/%'),0)::numeric / 1048576, 3) as ap_backend_mb, round(coalesce(sum(p.memory_bytes) filter (where coalesce(a.application_name,'') like 'paper1-chaos/%'),0)::numeric / 1048576, 3) as chaos_backend_mb, round(coalesce(sum(p.memory_bytes) filter (where coalesce(a.application_name,'') not like 'paper1-jobtp%' and coalesce(a.application_name,'') not like 'paper1-ap/%' and coalesce(a.application_name,'') not like 'paper1-chaos/%'),0)::numeric / 1048576, 3) as other_backend_mb from pg_stat_activity a join pg_sys_cpu_memory_by_process() p on p.pid = a.pid where a.pid <> pg_backend_pid()) select system_total_mb, system_used_mb, system_free_mb, system_cache_mb, pg_all_backend_mb, pg_client_backend_mb, tp_backend_mb, ap_backend_mb, chaos_backend_mb, other_backend_mb from system_memory cross join backend_memory")"
    if [[ -n "$row" ]]; then
      IFS='|' read -r system_total_mb system_used_mb system_free_mb system_cache_mb pg_all_backend_mb pg_client_backend_mb tp_backend_mb ap_backend_mb chaos_backend_mb other_backend_mb <<< "$row"
    fi
  fi

  if [[ "$SESSION_MEMORY_VIEW_AVAILABLE" == "true" ]]; then
    row="$(run_psql "$DATABASE" "select round(coalesce(sum(total_bytes),0)::numeric / 1048576, 3), round(coalesce(sum(used_bytes),0)::numeric / 1048576, 3), round(coalesce(sum(free_bytes),0)::numeric / 1048576, 3) from pg_backend_memory_contexts")"
    if [[ -n "$row" ]]; then
      IFS='|' read -r sampler_backend_total_mb sampler_backend_used_mb sampler_backend_free_mb <<< "$row"
    fi
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$db_cached_buffers" "$db_cached_mb" "$db_dirty_buffers" "$db_dirty_mb" "$pinned_backends" "$avg_usagecount" "$system_total_mb" "$system_used_mb" "$system_free_mb" "$system_cache_mb" "$pg_all_backend_mb" "$pg_client_backend_mb" "$tp_backend_mb" "$ap_backend_mb" "$chaos_backend_mb" "$other_backend_mb" "$sampler_backend_total_mb" "$sampler_backend_used_mb" "$sampler_backend_free_mb" >> "$MEMORY_FILE"
}

append_pg_activity_snapshot() {
  local sample_index="$1"
  local ts_epoch_ms="$2"
  local elapsed_seconds="$3"
  local phase="$4"

  capture_pg_activity_timeline_snapshot "$RUN_DIR" "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "" "$DATABASE" "${DB_SUPERUSER:-postgres}" "${DB_SUPERUSER_PASSWORD:-postgres}"
}

RUNNING=true
trap 'RUNNING=false' TERM INT

started_epoch_ms="$(date +%s%3N)"
sample_index=0
while [[ "$RUNNING" == "true" ]]; do
  now_epoch_ms="$(date +%s%3N)"
  elapsed_seconds="$(${PYTHON_BIN:-python} - "$started_epoch_ms" "$now_epoch_ms" <<'PY'
import sys
start = int(sys.argv[1])
now = int(sys.argv[2])
print(f"{max(now - start, 0) / 1000.0:.3f}")
PY
)"
  phase="$(current_phase)"
  append_system_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_activity_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_statement_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_io_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_wait_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_kcache_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_memory_sample "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  append_pg_activity_snapshot "$sample_index" "$now_epoch_ms" "$elapsed_seconds" "$phase" || true
  sample_index=$((sample_index + 1))
  if (( MAX_SAMPLES > 0 && sample_index >= MAX_SAMPLES )); then
    break
  fi
  sleep "$INTERVAL_SECONDS"
done
