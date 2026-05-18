#!/usr/bin/env python3
"""DB migration for mywebapp — idempotent."""

import argparse

import pymysql


SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--db-host", required=True)
    p.add_argument("--db-port", type=int, required=True)
    p.add_argument("--db-user", required=True)
    p.add_argument("--db-password", required=True)
    p.add_argument("--db-name", required=True)
    a = p.parse_args()

    conn = pymysql.connect(
        host=a.db_host, port=a.db_port,
        user=a.db_user, password=a.db_password,
        database=a.db_name, autocommit=True,
    )
    with conn, conn.cursor() as cur:
        cur.execute(SCHEMA)
    print("migrate: ok")


if __name__ == "__main__":
    main()
