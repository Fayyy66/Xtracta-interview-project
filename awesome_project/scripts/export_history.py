#!/usr/bin/env python3

import csv
import io
import subprocess
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
DB_SCRIPT = PROJECT_DIR / "db.sh"
TABLES = ("_migration_history", "_migration_history_log")


def fetch_table(table: str) -> list[list[str]]:
    mysql_command = (
        'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" '
        "--batch --raw --default-character-set=utf8mb4 awesome_db "
        f'-e "SELECT * FROM {table} ORDER BY id;"'
    )
    result = subprocess.run(
        [str(DB_SCRIPT), "exec", "-T", "dev-db", "sh", "-c", mysql_command],
        cwd=PROJECT_DIR,
        check=True,
        capture_output=True,
        text=True,
    )
    return list(csv.reader(io.StringIO(result.stdout), delimiter="\t"))


def export_table(table: str) -> None:
    rows = fetch_table(table)
    if not rows:
        raise RuntimeError(f"MySQL returned no header for {table}")

    output_path = PROJECT_DIR / f"{table}.csv"
    with output_path.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.writer(output_file, lineterminator="\n")
        writer.writerows(rows)

    print(f"Exported {len(rows) - 1} data row(s) to {output_path.name}")


def main() -> None:
    for table in TABLES:
        export_table(table)


if __name__ == "__main__":
    main()
