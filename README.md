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
export DB_HOST=127.0.0.1 DB_PORT=3306 \
       DB_USER=mywebapp DB_PASSWORD=<pw> DB_NAME=mywebapp
python3 app/migrate.py
python3 app/main.py        # listens on $APP_HOST:$APP_PORT (defaults 0.0.0.0:5200)
```

> Configuration moved from CLI flags to environment variables in Lab 3 to give compose, systemd, and pytest one shared contract.

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

---

# DevOps Lab 3 — CI/CD

Lab 3 puts a full pipeline on top of the Lab 1 project: lint → test → build → push to GHCR → deploy via a self-hosted runner → verify.

## Pipeline architecture

```
                ┌──────────────────────────────────────────────────────────┐
                │  GitHub-hosted runners (Ubuntu 24.04)                    │
push / tag  ──▶ │  .github/workflows/ci.yml                                │
                │     lint  →  test (MariaDB service)  →  build & push     │
                │                                            │             │
                │                                            ▼             │
                │                                   ghcr.io/maks9m/        │
                │                                   devops_lab_1:<tag>     │
                └────────────────────────────────┬─────────────────────────┘
                                                 │ workflow_run (on success, tags only)
                                                 ▼
                                  ┌──────────────────────────────┐
                                  │  Self-hosted runner VM       │
                                  │  .github/workflows/cd.yml    │
                                  │     ssh → rsync → restart    │
                                  │     systemd → verify.sh      │
                                  └──────────┬───────────────────┘
                                             │ ssh (id_lab3 keypair)
                                             ▼
                                  ┌──────────────────────────────┐
                                  │  Target node VM              │
                                  │  host nginx :80              │
                                  │  ↳ docker compose (systemd)  │
                                  │       app  + mariadb         │
                                  └──────────────────────────────┘
```

## What each workflow does

### `ci.yml` — triggers: `push` to `main`, annotated `v*` tags, `pull_request` to `main`

| Job | Purpose | Notes |
| :---- | :---- | :---- |
| `Lint`  | `flake8` + `yamllint` + `shellcheck` + `hadolint` | Configs: `.flake8`, `.yamllint.yml`, `.hadolint.yaml`. |
| `Test`  | `pytest` against a MariaDB 11 **service container**, coverage gate at 40 % | Uploads `coverage-html` + `coverage-xml` as artifacts on `main` only. |
| `Build & push image` | `docker/build-push-action` builds for `linux/amd64` + `linux/arm64`, pushes to GHCR | Skipped on PRs (only `push`). Tags via `docker/metadata-action`. |

Image tag scheme:

| Trigger | Tags pushed |
| :---- | :---- |
| `push` to `main`     | `latest`, `sha-<full-commit-sha>` |
| annotated `v*` tag   | `stable`, `<tag>` |

### `cd.yml` — triggers: `workflow_run` after `ci` completes, gated on `success` + tag push

Runs on `runs-on: [self-hosted, deploy]`. Steps:

1. Checkout repo at the deployed SHA.
2. Materialise the deploy SSH key from `TARGET_SSH_KEY` secret, add target to `known_hosts`.
3. `rsync` `docker-compose*.yml`, `nginx.conf`, `mywebapp-compose.service`, `target-setup.sh` to the target.
4. SSH-exec: install nginx site, reload nginx, pin `APP_IMAGE_TAG` in `/etc/mywebapp/mywebapp.env`, `systemctl restart mywebapp-compose.service`. The systemd unit invokes `docker compose pull && up -d`.
5. Wait-loop on `GET /` until 200.
6. Run `deploy/verify.sh http://<target>` from the runner.

## Self-hosted runner & target node

Both are Ubuntu 24.04 VMs. On macOS, easiest with Multipass:

```bash
# Target node
multipass launch 24.04 -n target -c 2 -m 2G -d 8G
multipass transfer deploy/target-setup.sh deploy/nginx.conf \
                   deploy/mywebapp-compose.service \
                   docker-compose.yml docker-compose.prod.yml target:/tmp/
multipass exec target -- sudo bash /tmp/target-setup.sh
multipass exec target -- sudo cp /tmp/docker-compose.yml /tmp/docker-compose.prod.yml /opt/mywebapp/

# Self-hosted runner
multipass launch 24.04 -n runner -c 2 -m 4G -d 20G
multipass transfer deploy/runner-setup.sh runner:/tmp/
multipass exec runner -- sudo bash /tmp/runner-setup.sh
# Then register manually (token is one-time, never committed):
#   multipass shell runner
#   cd ~/actions-runner
#   ./config.sh --url <repo-url> --token <PASTE> --labels self-hosted,deploy --unattended
#   sudo ./svc.sh install ubuntu && sudo ./svc.sh start
```

After the runner is up, generate the deploy key on the runner and copy the
public part into the target's `~/.ssh/authorized_keys`, then the **private**
part into the `TARGET_SSH_KEY` secret.

## GitHub Secrets

| Secret | Purpose |
| :---- | :---- |
| `TARGET_HOST`    | IP of the target VM (e.g. `192.168.252.4`). |
| `TARGET_USER`    | SSH user on the target (`ubuntu`). |
| `TARGET_SSH_KEY` | Private key the runner uses to SSH into the target. |

The DB password is **not** in Secrets — `target-setup.sh` generates one with `openssl rand -hex 16` and stores it in `/etc/mywebapp/mywebapp.env` on the target. The GHCR pull uses the built-in `GITHUB_TOKEN` from the build job (the package is public for read).

## Release procedure

```bash
git checkout main && git pull --ff-only
git tag -a v0.1.0 -m "first release"
git push origin v0.1.0       # → CI builds stable+v0.1.0 → CD deploys → verify
```

## Demonstration

| Spec requirement | Evidence |
| :---- | :---- |
| PR merged after all checks pass | [PR #2](https://github.com/Maks9m/DevOps_Lab_1/pull/2) (initial CI/CD), [PR #3](https://github.com/Maks9m/DevOps_Lab_1/pull/3) (green demo), [PR #5](https://github.com/Maks9m/DevOps_Lab_1/pull/5), [PR #6](https://github.com/Maks9m/DevOps_Lab_1/pull/6) |
| PR that **cannot** be merged because checks failed | [PR #4](https://github.com/Maks9m/DevOps_Lab_1/pull/4) — Lint job fails, branch protection blocks merge |
| Successful deploy log + successful verification | [CD run #26433991945](https://github.com/Maks9m/DevOps_Lab_1/actions/runs/26433991945) (tag `v0.1.0`) |
| Successful deploy log + **failed** verification | [CD run #26433748124](https://github.com/Maks9m/DevOps_Lab_1/actions/runs/26433748124) (earlier `v0.1.0` attempt — image pulled and stack started, but `verify.sh` failed on two endpoints) |
| Coverage report | Artifact `coverage-html` on [CI run #26433885478](https://github.com/Maks9m/DevOps_Lab_1/actions/runs/26433885478) |

A consolidated mini-report with screenshots and log excerpts is submitted separately in classroom (GitHub keeps Actions logs for a limited time).
