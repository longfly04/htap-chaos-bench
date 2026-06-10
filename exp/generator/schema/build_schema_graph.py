import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

TABLE_RE = re.compile(r"\b(?:from|join)\s+([a-zA-Z_][\w\.]+)", re.IGNORECASE)


def normalize(name: str) -> str:
    return name.split(".")[-1].strip('"')


parser = argparse.ArgumentParser()
parser.add_argument("--query-root", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

root = Path(args.query_root)
node_counter = Counter()
edge_counter = Counter()
query_index = {}
for sql_file in sorted(root.rglob("*.sql")):
    text = sql_file.read_text(encoding="utf-8")
    tables = [normalize(m.group(1)) for m in TABLE_RE.finditer(text)]
    unique_tables = []
    for table in tables:
        if table not in unique_tables:
            unique_tables.append(table)
    for table in unique_tables:
        node_counter[table] += 1
    for i in range(len(unique_tables)):
        for j in range(i + 1, len(unique_tables)):
            edge = tuple(sorted((unique_tables[i], unique_tables[j])))
            edge_counter[edge] += 1
    query_index[str(sql_file)] = unique_tables

graph = {
    "nodes": [{"id": node, "weight": weight} for node, weight in sorted(node_counter.items())],
    "edges": [
        {"source": a, "target": b, "weight": weight}
        for (a, b), weight in sorted(edge_counter.items())
    ],
    "query_index": query_index,
}
Path(args.output).write_text(json.dumps(graph, indent=2), encoding="utf-8")
