import argparse
import json
import random
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--select-templates", required=True)
parser.add_argument("--update-templates", required=True)
parser.add_argument("--seed", type=int, required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

select_templates = json.loads(Path(args.select_templates).read_text(encoding="utf-8")).get("templates", [])
update_templates = json.loads(Path(args.update_templates).read_text(encoding="utf-8")).get("templates", [])
random.seed(args.seed)
scenario = {
    "seed": args.seed,
    "tp_templates": random.sample(update_templates, min(1, len(update_templates))),
    "ap_templates": random.sample(select_templates, min(2, len(select_templates))),
    "overlap": "tp-first",
    "budget_tier": "moderate",
    "chaos_mode": "none",
}
Path(args.output).write_text(json.dumps(scenario, indent=2), encoding="utf-8")
