#!/usr/bin/env python3
"""DB migration for mywebapp — idempotent."""

import os

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
    conn = pymysql.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        autocommit=True,
    )
    with conn, conn.cursor() as cur:
        cur.execute(SCHEMA)
    print("migrate: ok")


if __name__ == "__main__":
    main()
