# Creates the tables, loads the lookup lists and installs the functions.
# Usage: python setup_db.py "postgresql://user:password@host/dbname"

import sys
from pathlib import Path

import psycopg

with psycopg.connect(sys.argv[1], autocommit=True) as conn:
    for file in ["schema.sql", "seed.sql", "functions.sql"]:
        conn.execute(Path(file).read_text(encoding="utf-8"))
        print(f"{file} done")
