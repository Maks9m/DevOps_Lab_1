# DevOps Lab 1 — mywebapp (Task Tracker)

A small web platform on a single VM with fully automated deployment. nginx accepts public traffic and reverse-proxies business endpoints to a Flask app, which stores data in MariaDB.

## Individual variant

Gradebook number: **N = 16**

| Parameter | Formula | Value | Implication |
| :---- | :---- | :---- | :---- |
| V2 | `(16 % 2) + 1` | **1** | MariaDB, configured via command-line arguments |
| V3 | `(16 % 3) + 1` | **2** | Task Tracker — task tracking service |
| V5 | `(16 % 5) + 1` | **2** | App listens on port `5200` |

## Architecture

```
client → nginx :80 → flask 127.0.0.1:5200 → mariadb 127.0.0.1:3306
```

- nginx listens on `0.0.0.0:80` and externally exposes only the root and business endpoints.
- The Flask app listens only on `127.0.0.1:5200`.
- MariaDB is bound to `127.0.0.1:3306` (`bind-address = 127.0.0.1`).

## Web application

### Purpose

Task Tracker — a simple service for storing tasks. A task object: `id`, `title`, `status`, `created_at`.

### API

| Method | Path | Description | Accept | Request body |
| :---- | :---- | :---- | :---- | :---- |
| GET  | `/`                  | HTML page listing endpoints | `text/html` | — |
| GET  | `/health/alive`      | Health check (always 200 `OK`) | — | — |
| GET  | `/health/ready`      | 200 `OK` if DB connection is up, 500 otherwise | — | — |
| GET  | `/tasks`             | List all tasks | `application/json` or `text/html` | — |
| POST | `/tasks`             | Create a task | `application/json` | `{"title": "..."}` |
| POST | `/tasks/<id>/done`   | Mark a task as done | — | — |

`GET /tasks` returns JSON or an HTML table depending on the `Accept` header. The root endpoint accepts `text/html` only.

The health endpoints are reachable **only locally** — nginx returns 404 for them externally. They are intended for systemd and local checks.

### Local run (for development)

```bash
sudo apt-get install -y python3-flask python3-pymysql mariadb-server
python3 app/migrate.py --db-host=127.0.0.1 --db-port=3306 \
  --db-user=mywebapp --db-password=<pw> --db-name=mywebapp
python3 app/main.py --host=127.0.0.1 --port=5200 \
  --db-host=127.0.0.1 --db-port=3306 \
  --db-user=mywebapp --db-password=<pw> --db-name=mywebapp
```

## Run with Docker Compose

A `docker-compose.yml` at the repository root orchestrates the three services (MariaDB, Flask app, nginx) plus a one-shot `migrate` job. All services run on a dedicated bridge network `lab_net` (not the default network), and DB data persists in the named volume `mariadb_data` — it survives `docker compose down`, container removal, and host reboot.

### Prerequisites

Docker Desktop (or Docker Engine) with `docker compose` v2.

### Start

```bash
cp .env.example .env
# edit .env and set real passwords
docker compose up -d --build
docker compose ps                  # mariadb/app/nginx Up; migrate Exited (0)
```

Only nginx is exposed to the host (port 80). The app and the database are reachable only inside `lab_net`.

### Smoke test

```bash
curl -s -H 'Accept: application/json' http://localhost/tasks
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"title":"buy milk"}' http://localhost/tasks
curl -s -H 'Accept: application/json' http://localhost/tasks   # contains "buy milk"
curl -s -X POST http://localhost/tasks/1/done
```

### Persistence check

```bash
# create a task, then:
docker compose down
docker compose up -d
curl -s -H 'Accept: application/json' http://localhost/tasks   # task still present
```

Inspect the on-disk volume:

```bash
docker volume inspect devops_lab_1_mariadb_data
```

To wipe data, use `docker compose down -v` (drops the volume) — otherwise the volume persists across `down`/`up`, container deletion, Docker restart, and host reboot.

### Layout

- `app/Dockerfile` — Python 3.13-slim, layer-friendly (deps before code), non-root user `appuser`.
- `app/.dockerignore` — keeps the build context tight.
- `deploy/nginx.docker.conf` — container variant of the nginx config (`proxy_pass http://app:5200` via Docker DNS instead of `127.0.0.1:5200`). The bare-metal `deploy/nginx.conf` is unchanged.

## Deployment

### Image and resources

- **Image:** Ubuntu Server 24.04 LTS (official) — https://ubuntu.com/download/server
- **VM resources:** 1 vCPU, 1 GB RAM, 5 GB disk.
- **Special OS-install settings:** none (default minimal install).

### Using Multipass

```bash
multipass launch 24.04 --name mywebapp --cpus 1 --memory 1G --disk 5G
multipass transfer -r ./DevOps_Lab_1 mywebapp:/home/ubuntu/DevOps_Lab_1
multipass shell mywebapp
```

Login: `multipass shell mywebapp` (default user `ubuntu`, SSH key managed by Multipass).

Alternative: `sudo apt-get install -y git && git clone <repo-url>` inside the VM.

### Running the automation

From the repository root on the VM:

```bash
cd ~/DevOps_Lab_1
sudo bash deploy/install.sh
```

The script is idempotent — re-running it is safe. It performs nine steps (package install, user creation, DB setup, app file copy, env file write, systemd unit install, nginx config, sudoers install, gradebook creation + locking the `ubuntu` user).

## System users

| User | Default password | Privileges |
| :---- | :---- | :---- |
| `student`  | (not set — use `sudo passwd student`) | full sudo |
| `teacher`  | `12345678` *(must change on first login)* | full sudo |
| `operator` | `12345678` *(must change on first login)* | restricted sudo: `systemctl start/stop/restart/status mywebapp`, `systemctl reload nginx` |
| `app`      | — (system user, no shell) | minimal — only what's needed to run the app |

> After `install.sh` runs, the Multipass default `ubuntu` user has its password locked (`usermod -L`), but its SSH key is intentionally left in place so the host can keep managing the VM via Multipass. This still satisfies the spec, since password login is disabled.

## Testing

All commands are run inside the VM unless noted.

```bash
# Service status
sudo systemctl status mywebapp --no-pager
sudo journalctl -u mywebapp --no-pager -n 30

# Health (direct, local only)
curl -i http://127.0.0.1:5200/health/alive   # 200 OK
curl -i http://127.0.0.1:5200/health/ready   # 200 OK

# Through nginx — JSON
curl -s -H 'Accept: application/json' http://127.0.0.1/tasks
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"title":"buy milk"}' http://127.0.0.1/tasks
curl -s -X POST http://127.0.0.1/tasks/1/done

# Through nginx — HTML
curl -s -H 'Accept: text/html' http://127.0.0.1/tasks

# Health must be hidden externally
curl -i http://127.0.0.1/health/alive        # 404

# From the host (replace IP with the one shown by `multipass list`)
curl -s http://192.168.252.2/tasks -H 'Accept: application/json'

# DB isolation
ss -tlnp | grep 3306                          # 127.0.0.1:3306 (NOT 0.0.0.0)

# operator privileges (log in as operator, after first-login password change):
su - operator
sudo -n systemctl restart mywebapp            # OK
sudo -n systemctl reload nginx                # OK
sudo -n systemctl restart nginx               # DENIED
sudo -n cat /etc/shadow                       # DENIED

# Gradebook (needs sudo because /home/student is mode 0750)
sudo cat /home/student/gradebook              # → 16

# Locked default user
sudo passwd -S ubuntu                          # status 'L'
```
