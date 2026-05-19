#!/usr/bin/env python3
"""Task Tracker — KPI DevOps Lab 1 (V3=2)."""

import argparse
import os
import socket
from html import escape
from wsgiref.simple_server import WSGIRequestHandler, WSGIServer

import pymysql
from flask import Flask, abort, jsonify, request


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=5200)
    p.add_argument("--db-host", required=True)
    p.add_argument("--db-port", type=int, required=True)
    p.add_argument("--db-user", required=True)
    p.add_argument("--db-password", required=True)
    p.add_argument("--db-name", required=True)
    return p.parse_args()


ARGS = parse_args()
app = Flask(__name__)


def db_connect():
    return pymysql.connect(
        host=ARGS.db_host,
        port=ARGS.db_port,
        user=ARGS.db_user,
        password=ARGS.db_password,
        database=ARGS.db_name,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


INDEX_HTML = """<!doctype html><html><body>
<h1>mywebapp — Task Tracker</h1>
<table border=1>
<tr><th>Method</th><th>Path</th><th>Description</th></tr>
<tr><td>GET</td><td>/tasks</td><td>List all tasks</td></tr>
<tr><td>POST</td><td>/tasks</td><td>Create task (body: {title})</td></tr>
<tr><td>POST</td><td>/tasks/&lt;id&gt;/done</td><td>Mark task as done</td></tr>
</table></body></html>"""


@app.route("/", methods=["GET"])
def index():
    if request.accept_mimetypes.best_match(["text/html"]) != "text/html":
        abort(406)
    return INDEX_HTML


@app.route("/health/alive", methods=["GET"])
def alive():
    return "OK"


@app.route("/health/ready", methods=["GET"])
def ready():
    try:
        conn = db_connect()
        conn.ping(reconnect=False)
        conn.close()
        return "OK"
    except Exception as e:
        return f"DB not ready: {e}", 500


@app.route("/tasks", methods=["GET"])
def list_tasks():
    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, title, status, created_at FROM tasks ORDER BY id")
            rows = cur.fetchall()
    for r in rows:
        r["created_at"] = r["created_at"].isoformat() if r["created_at"] else None

    if request.accept_mimetypes.best_match(["application/json", "text/html"]) == "application/json":
        return jsonify(rows)

    body = "".join(
        f"<tr><td>{r['id']}</td><td>{escape(r['title'])}</td>"
        f"<td>{r['status']}</td><td>{r['created_at']}</td></tr>"
        for r in rows
    )
    return (
        "<!doctype html><html><body><h1>Tasks</h1><table border=1>"
        "<tr><th>ID</th><th>Title</th><th>Status</th><th>Created</th></tr>"
        f"{body}</table></body></html>"
    )


@app.route("/tasks", methods=["POST"])
def create_task():
    data = request.get_json(silent=True) or request.form
    title = (data.get("title") or "").strip()
    if not title:
        return jsonify({"error": "title is required"}), 400
    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO tasks (title, status) VALUES (%s, 'pending')", (title,))
            new_id = cur.lastrowid
    return jsonify({"id": new_id, "title": title, "status": "pending"}), 201


@app.route("/tasks/<int:task_id>/done", methods=["POST"])
def mark_done(task_id):
    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE tasks SET status='done' WHERE id=%s", (task_id,))
            if cur.rowcount == 0:
                return jsonify({"error": "not found"}), 404
    return jsonify({"id": task_id, "status": "done"})


def serve_socket_activated():
    """Run on the inherited socket from systemd (FD 3 = SD_LISTEN_FDS_START)."""
    server = WSGIServer(("", 0), WSGIRequestHandler, bind_and_activate=False)
    server.socket = socket.socket(fileno=3, family=socket.AF_INET, type=socket.SOCK_STREAM)
    server.server_address = server.socket.getsockname()
    server.set_app(app)
    server.serve_forever()


if __name__ == "__main__":
    if os.environ.get("LISTEN_FDS"):
        serve_socket_activated()
    else:
        app.run(host=ARGS.host, port=ARGS.port)
