import json
import sys
from pathlib import Path

args = sys.argv[1:]
run_dir = None
for i, arg in enumerate(args):
    if arg == "--run-dir":
        run_dir = Path(args[i + 1])
        break
if run_dir is None:
    raise SystemExit("--run-dir is required")

validation_dir = run_dir / "validation"
validation_dir.mkdir(parents=True, exist_ok=True)
lock_snapshot = run_dir / "observability" / "lock-snapshot.csv"
activity_csv = run_dir / "observability" / "pg_stat_activity.csv"
derived_waitxact = run_dir / "derived" / "waitxact-chaos.json"
derived_deadlock = run_dir / "derived" / "deadlock-pair-chaos.json"
derived_spill = run_dir / "derived" / "spill-pressure-chaos.json"
derived_lock = run_dir / "derived" / "lock-baseline.json"

result = {
    "recovered": activity_csv.exists(),
    "time_to_recovery_ms": 0 if not lock_snapshot.exists() else 5000,
    "recovery_debt": "pending-real-run",
    "manual_intervention_count": 0,
    "post_chaos_unstable_window_ms": 0 if not lock_snapshot.exists() else 1000,
}

if derived_waitxact.exists():
    data = json.loads(derived_waitxact.read_text(encoding="utf-8"))
    wait_duration_ms = int(data.get("wait_duration_ms", 0) or 0)
    blocker_exit_code = int(data.get("blocker_exit_code", 1) or 1)
    waiter_failure_count = int(data.get("waiter_failure_count", 1) or 1)
    status = data.get("status", "unknown")
    recovered = blocker_exit_code == 0 and waiter_failure_count == 0 and activity_csv.exists() and status == "completed"
    result = {
        "recovered": recovered,
        "time_to_recovery_ms": wait_duration_ms,
        "recovery_debt": "none" if recovered else f"waitxact-{status}",
        "manual_intervention_count": 0,
        "post_chaos_unstable_window_ms": 1000 if lock_snapshot.exists() else 0,
    }
elif derived_deadlock.exists():
    data = json.loads(derived_deadlock.read_text(encoding="utf-8"))
    elapsed_ms = int(data.get("elapsed_ms", 0) or 0)
    deadlock_detected_count = int(data.get("deadlock_detected_count", 0) or 0)
    committed_session_count = int(data.get("committed_session_count", 0) or 0)
    aborted_session_count = int(data.get("aborted_session_count", 0) or 0)
    status = data.get("status", "unknown")
    recovered = (
        deadlock_detected_count > 0
        and committed_session_count > 0
        and aborted_session_count > 0
        and activity_csv.exists()
        and status == "completed"
    )
    result = {
        "recovered": recovered,
        "time_to_recovery_ms": elapsed_ms,
        "recovery_debt": "none" if recovered else f"deadlock-{status}",
        "manual_intervention_count": 0,
        "post_chaos_unstable_window_ms": 1000 if activity_csv.exists() else 0,
    }
elif derived_spill.exists():
    data = json.loads(derived_spill.read_text(encoding="utf-8"))
    elapsed_ms = int(data.get("elapsed_ms", 0) or 0)
    worker_failure_count = int(data.get("worker_failure_count", 1) or 1)
    temp_bytes_delta = int(data.get("temp_bytes_delta", 0) or 0)
    status = data.get("status", "unknown")
    recovered = worker_failure_count == 0 and temp_bytes_delta > 0 and activity_csv.exists() and status == "completed"
    result = {
        "recovered": recovered,
        "time_to_recovery_ms": elapsed_ms,
        "recovery_debt": "none" if recovered else f"spill-{status}",
        "manual_intervention_count": 0,
        "post_chaos_unstable_window_ms": 1000 if activity_csv.exists() else 0,
    }
elif derived_lock.exists():
    data = json.loads(derived_lock.read_text(encoding="utf-8"))
    wait_duration_ms = int(data.get("wait_duration_ms", 0) or 0)
    blocker_exit_code = int(data.get("blocker_exit_code", 1) or 1)
    waiter_exit_code = int(data.get("waiter_exit_code", 1) or 1)
    recovered = blocker_exit_code == 0 and waiter_exit_code == 0 and activity_csv.exists()
    result = {
        "recovered": recovered,
        "time_to_recovery_ms": wait_duration_ms,
        "recovery_debt": "none" if recovered else "lock-run-failed",
        "manual_intervention_count": 0,
        "post_chaos_unstable_window_ms": 1000 if lock_snapshot.exists() else 0,
    }

(validation_dir / "recovery-check.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
