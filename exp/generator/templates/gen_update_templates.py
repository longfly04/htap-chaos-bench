import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--graph", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

graph = json.loads(Path(args.graph).read_text(encoding="utf-8"))
templates = []
for index, node in enumerate(graph.get("nodes", []), start=1):
    table = node["id"]
    templates.append({
        "id": f"upd_t{index:03d}",
        "table": table,
        "sql": f"update {table} set id = id where id = :id;",
        "drift_target": table,
    })

Path(args.output).write_text(json.dumps({"templates": templates}, indent=2), encoding="utf-8")
