import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--templates", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

templates = json.loads(Path(args.templates).read_text(encoding="utf-8")).get("templates", [])
plan = []
for round_id, template in enumerate(templates[:3], start=1):
    plan.append({
        "round": round_id,
        "template_id": template["id"],
        "target": template["drift_target"],
        "js_divergence_target": round(round_id * 0.1, 3),
        "row_update_count": round_id * 100,
    })

Path(args.output).write_text(json.dumps({"rounds": plan}, indent=2), encoding="utf-8")
