"""Route-level tests for mywebapp."""


def test_index_html(client):
    r = client.get("/", headers={"Accept": "text/html"})
    assert r.status_code == 200
    assert b"Task Tracker" in r.data


def test_index_rejects_non_html(client):
    r = client.get("/", headers={"Accept": "application/json"})
    assert r.status_code == 406


def test_alive(client):
    r = client.get("/health/alive")
    assert r.status_code == 200
    assert r.data == b"OK"


def test_ready(client):
    r = client.get("/health/ready")
    assert r.status_code == 200
    assert r.data == b"OK"


def test_list_tasks_empty_json(client):
    r = client.get("/tasks", headers={"Accept": "application/json"})
    assert r.status_code == 200
    assert r.get_json() == []


def test_list_tasks_empty_html(client):
    r = client.get("/tasks", headers={"Accept": "text/html"})
    assert r.status_code == 200
    assert b"<h1>Tasks</h1>" in r.data


def test_create_task_success(client):
    r = client.post("/tasks", json={"title": "buy milk"})
    assert r.status_code == 201
    body = r.get_json()
    assert body["title"] == "buy milk"
    assert body["status"] == "pending"
    assert isinstance(body["id"], int)

    # And it shows up in the list.
    r = client.get("/tasks", headers={"Accept": "application/json"})
    items = r.get_json()
    assert len(items) == 1
    assert items[0]["title"] == "buy milk"


def test_create_task_missing_title(client):
    r = client.post("/tasks", json={})
    assert r.status_code == 400
    assert r.get_json() == {"error": "title is required"}


def test_create_task_blank_title(client):
    r = client.post("/tasks", json={"title": "   "})
    assert r.status_code == 400


def test_mark_done_success(client):
    created = client.post("/tasks", json={"title": "write tests"}).get_json()
    r = client.post(f"/tasks/{created['id']}/done")
    assert r.status_code == 200
    assert r.get_json() == {"id": created["id"], "status": "done"}

    listed = client.get("/tasks", headers={"Accept": "application/json"}).get_json()
    assert listed[0]["status"] == "done"


def test_mark_done_not_found(client):
    r = client.post("/tasks/99999/done")
    assert r.status_code == 404
