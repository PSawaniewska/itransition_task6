# Measures how many fake users per second the SQL functions generate.
# Usage: python benchmark.py "postgresql://user:password@host/dbname"

import sys
import time

import psycopg

BATCHES = 1000
BATCH_SIZE = 10

# length(u::text) makes PostgreSQL compute every column, not just count the rows
QUERY = """
    SELECT sum(length(u::text))
    FROM generate_series(0, %s - 1) AS b
    CROSS JOIN LATERAL faker_users(%s, 42, b, %s) AS u
"""

with psycopg.connect(sys.argv[1]) as conn:
    for locale in ["en_US", "de_DE"]:
        start = time.perf_counter()
        conn.execute(QUERY, (BATCHES, locale, BATCH_SIZE)).fetchone()
        seconds = time.perf_counter() - start
        users = BATCHES * BATCH_SIZE
        print(f"{locale}: {users} users in {seconds:.2f} s = {users / seconds:.0f} users/second")
