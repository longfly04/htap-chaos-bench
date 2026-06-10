import argparse
import json
import random
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--graph", required=True)
parser.add_argument("--seed", type=int, required=True)
parser.add_argument("--steps", type=int, default=4)
parser.add_argument("--output", required=True)
args = parser.parse_args()

graph = json.loads(Path(args.graph).read_text(encoding="utf-8"))
adj = defaultdict(list)
for edge in graph.get("edges", []):
    adj[edge["source"]].append(edge["target"])
    adj[edge["target"]].append(edge["source"])

nodes = [node["id"] for node in graph.get("nodes", [])]
random.seed(args.seed)
walk = []
if nodes:
    current = random.choice(nodes)
    walk.append(current)
    for _ in range(max(0, args.steps - 1)):
        neighbors = adj.get(current) or nodes
        current = random.choice(neighbors)
        walk.append(current)

Path(args.output).write_text(json.dumps({"seed": args.seed, "steps": args.steps, "walk": walk}, indent=2), encoding="utf-8")
