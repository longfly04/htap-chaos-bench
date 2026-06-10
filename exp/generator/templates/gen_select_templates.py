import argparse
import json
import re
from pathlib import Path

TABLE_RE = re.compile(r"\b(?:from|join)\s+([a-zA-Z_][\w\.]+)", re.IGNORECASE)


def normalize(name: str) -> str:
    return name.split(".")[-1].strip('"')


parser = argparse.ArgumentParser()
parser.add_argument("--query-root", required=True)
parser.add_argument("--graph", required=True)
parser.add_argument("--seed", type=int, required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

root = Path(args.query_root)
templates = []
for index, sql_file in enumerate(sorted(root.rglob("*.sql")), start=1):
    text = sql_file.read_text(encoding="utf-8")
    tables = []
    for match in TABLE_RE.finditer(text):
        table = normalize(match.group(1))
        if table not in tables:
            tables.append(table)
    ap_class = sql_file.stem.split("-")[0]
    templates.append({
        "id": f"sel_t{index:03d}",
        "query_file": str(sql_file),
        "ap_class": ap_class,
        "tables": tables,
        "join_count": max(0, len(tables) - 1),
        "selectivity_bucket": "medium",
    })

Path(args.output).write_text(json.dumps({"seed": args.seed, "templates": templates}, indent=2), encoding="utf-8")
