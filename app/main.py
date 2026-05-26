#!/usr/bin/env python3
"""Task Tracker — KPI DevOps Lab 1 (V3=2)."""

import os
import socket
from html import escape
from wsgiref.simple_server import WSGIRequestHandler, WSGIServer

import pymysql
from flask import Flask, abort, jsonify, request


def _env_config():
    """Build runtime config from environment variables with sane defaults.

    Defaults are deliberately non-functional placeholders so that `import main`
    never crashes (needed for pytest and for `flask` CLI introspection); any
    real call that touches the DB will surface the misconfiguration loudly.
    """
    return {
        "APP_HOST": os.environ.get("APP_HOST", "0.0.0.0"),
        "APP_PORT": int(os.environ.get("APP_PORT", "5200")),
        "DB_HOST": os.environ.get("DB_HOST", "localhost"),
        "DB_PORT": int(os.environ.get("DB_PORT", "3306")),
        "DB_USER": os.environ.get("DB_USER", "mywebapp"),
        "DB_PASSWORD": os.environ.get("DB_PASSWORD", ""),
        "DB_NAME": os.environ.get("DB_NAME", "mywebapp"),
    }


INDEX_HTML = """<!doctype html><html><body>
<h1>mywebapp — Task Tracker</h1>
<table border=1>
<tr><th>Method</th><th>Path</th><th>Description</th></tr>
<tr><td>GET</td><td>/tasks</td><td>List all tasks</td></tr>
<tr><td>POST</td><td>/tasks</td><td>Create task (body: {title})</td></tr>
<tr><td>POST</td><td>/tasks/&lt;id&gt;/done</td><td>Mark task as done</td></tr>
</table></body></html>"""


def create_app(config=None):
    """Application factory. `config` overrides any env-derived value."""
    app = Flask(__name__)
    app.config.update(_env_config())
    if config:
        app.config.update(config)

    def db_connect():
        return pymysql.connect(
            host=app.config["DB_HOST"],
            port=app.config["DB_PORT"],
            user=app.config["DB_USER"],
            password=app.config["DB_PASSWORD"],
            database=app.config["DB_NAME"],
            autocommit=True,
            cursorclass=pymysql.cursors.DictCursor,
        )

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

    return app


# Module-level app for `flask run` / WSGI servers / production container.
app = create_app()


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
        app.run(host=app.config["APP_HOST"], port=app.config["APP_PORT"])
