import argparse
import json
from pathlib import Path


def parse_env(path: Path):
    result = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key] = value
    return result


parser = argparse.ArgumentParser()
parser.add_argument("--dataset-root", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

root = Path(args.dataset_root)
stats_dir = root / "stats"
metadata = parse_env(root / "metadata" / "dataset.env")
files = sorted(str(p.relative_to(root)) for p in stats_dir.rglob("*") if p.is_file()) if stats_dir.exists() else []
output = {
    "dataset_root": str(root),
    "dataset_id": metadata.get("DATASET_ID", root.name),
    "snapshot_id": metadata.get("SNAPSHOT_ID", "unknown"),
    "stats_dir_exists": stats_dir.exists(),
    "stats_files": files,
}
Path(args.output).write_text(json.dumps(output, indent=2), encoding="utf-8")
