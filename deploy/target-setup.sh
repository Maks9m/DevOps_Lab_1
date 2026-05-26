#!/usr/bin/env bash
# target-setup.sh — bootstrap the Lab 3 target node (Ubuntu 24.04).
#
# Run once as root on the freshly-launched VM:
#     sudo bash target-setup.sh
#
# Idempotent — safe to re-run. The CD job re-invokes it after every deploy to
# keep system config (nginx, systemd unit) in sync with the repo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Must run as root (use sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/6] Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg nginx

echo "==> [2/6] Installing Docker (official repo)"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
fi
# shellcheck source=/dev/null
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "==> [3/6] Creating app directory and env file"
install -d -m 0755 /opt/mywebapp
install -d -m 0750 /etc/mywebapp

if [[ ! -f /etc/mywebapp/mywebapp.env ]]; then
    DB_PASSWORD="$(openssl rand -hex 16)"
    cat > /etc/mywebapp/mywebapp.env <<EOF
# Auto-generated on first run. Do NOT commit.
MARIADB_ROOT_PASSWORD=$(openssl rand -hex 16)
MARIADB_DATABASE=mywebapp
MARIADB_USER=mywebapp
MARIADB_PASSWORD=${DB_PASSWORD}
APP_IMAGE_TAG=stable
EOF
    chmod 0640 /etc/mywebapp/mywebapp.env
fi
ln -sf /etc/mywebapp/mywebapp.env /opt/mywebapp/.env

echo "==> [4/6] Configuring nginx (host)"
install -m 0644 "${SCRIPT_DIR}/nginx.conf" /etc/nginx/sites-available/mywebapp
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> [5/6] Installing systemd unit for the compose stack"
install -m 0644 "${SCRIPT_DIR}/mywebapp-compose.service" \
    /etc/systemd/system/mywebapp-compose.service
systemctl daemon-reload
systemctl enable mywebapp-compose.service

echo "==> [6/6] Done."
echo "Next: the CD job will copy docker-compose*.yml into /opt/mywebapp/ and"
echo "      'systemctl restart mywebapp-compose.service' to bring the stack up."
