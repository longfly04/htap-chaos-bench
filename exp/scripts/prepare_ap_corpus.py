#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(r"D:/06_Obsidian/Papers/Projects/htap-chaos-bench/exp/datasets/job/queries/ap")
JOB_SRC = Path(r"/home/sducs/postgresql-dev/benchmarks/JOB-benchmark/job113sql")
COMPLEX_SRC = Path(r"/home/sducs/postgresql-dev/benchmarks/JOB-Complex")
CLASSES_PATH = ROOT.parent / "classes.yaml"

SQL_HEADER = """WITH hot_movies AS (
    SELECT movie_id, epoch, hot_flag
    FROM movie_freshness
    WHERE hot_flag = true AND epoch >= 0
)
"""

from_re = re.compile(r'^(\s*)FROM\s+(.*)$', re.IGNORECASE)
where_re = re.compile(r'^(\s*)WHERE\b(.*)$', re.IGNORECASE)


def rewrite_sql(text: str) -> str:
    lines = text.strip().rstrip(';').splitlines()
    out = []
    inserted = False
    for line in lines:
        if not inserted:
            m = from_re.match(line)
            if m:
                indent, rest = m.groups()
                out.append(f"{indent}FROM hot_movies AS mf,")
                out.append(f"{indent}     {rest}")
                inserted = True
                continue
        m = where_re.match(line)
        if m:
            indent, rest = m.groups()
            out.append(f"{indent}WHERE mf.movie_id = t.id")
            out.append(f"{indent}  AND {rest.strip()}")
            continue
        out.append(line)
    return SQL_HEADER + "\n".join(out) + ";\n"


def collect_sqls(src: Path, prefix: str):
    files = []
    for index, path in enumerate(sorted(src.glob('*.sql')), start=1):
        name = path.name
        if not name[0].isdigit():
            continue
        dst_name = f"{prefix}-q{index:03d}.sql"
        dst = ROOT / dst_name
        dst.write_text(rewrite_sql(path.read_text(encoding='utf-8')), encoding='utf-8')
        files.append(f"queries/ap/{dst_name}")
    return files


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    job_files = collect_sqls(JOB_SRC, 'job113')
    complex_files = collect_sqls(COMPLEX_SRC, 'complex')
    hash_files = list(dict.fromkeys(job_files[::2] + complex_files[::3]))

    classes = {
        'sort-heavy': job_files,
        'hash-heavy': hash_files,
        'mixed': complex_files,
        'freshness-read': [],
    }

    with CLASSES_PATH.open('w', encoding='utf-8') as fh:
        for key, values in classes.items():
            fh.write(f"{key}:\n")
            if values:
                for value in values:
                    fh.write(f"  - {value}\n")
            else:
                fh.write("  []\n")

    print(f"sort-heavy={len(job_files)} mixed={len(complex_files)} hash-heavy={len(hash_files)}")


if __name__ == '__main__':
    main()
