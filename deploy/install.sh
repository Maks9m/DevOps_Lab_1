#!/usr/bin/env bash
# mywebapp — single-entry deployment script for KPI DevOps Lab 1.
# Run as root from the repository root:   sudo bash deploy/install.sh
set -euo pipefail # -e: abort on first error;  -u: error on undefined var;  -o pipefail: catch errors mid-pipe

if [[ $EUID -ne 0 ]]; then
    echo "Must run as root (use sudo)." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"


echo "==> [1/9] Installing packages"
export DEBIAN_FRONTEND=noninteractive # prevent apt from asking interactive questions
apt-get update
apt-get install -y nginx mariadb-server python3 python3-flask python3-pymysql

echo "==> [2/9] Creating users"
id app      &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin app
id student  &>/dev/null || useradd -m -s /bin/bash -G sudo student
if ! id teacher &>/dev/null; then
    useradd -m -s /bin/bash -G sudo teacher
    echo "teacher:${DEFAULT_PASSWORD}" | chpasswd
    chage -d 0 teacher
fi
if ! id operator &>/dev/null; then
    getent group operator >/dev/null || groupadd operator
    useradd -m -s /bin/bash -g operator operator
    echo "operator:${DEFAULT_PASSWORD}" | chpasswd
    chage -d 0 operator
fi

echo "==> [3/9] Configuring database"
systemctl enable --now mariadb
# Sanity check: MariaDB must bind only to localhost.
if ! grep -Eq '^\s*bind-address\s*=\s*127\.0\.0\.1' /etc/mysql/mariadb.conf.d/50-server.cnf; then
    echo "MariaDB is not bound to 127.0.0.1 — refusing to continue." >&2
    exit 1
fi

DB_PASSWORD_FILE=/etc/mywebapp/db_password
install -d -m 0750 -o root -g root /etc/mywebapp
if [[ -f "$DB_PASSWORD_FILE" ]]; then
    DB_PASSWORD="$(cat "$DB_PASSWORD_FILE")"
else
    DB_PASSWORD="$(openssl rand -hex 16)"
    echo -n "$DB_PASSWORD" > "$DB_PASSWORD_FILE"
    chmod 0600 "$DB_PASSWORD_FILE"
fi

mariadb <<SQL
CREATE DATABASE IF NOT EXISTS mywebapp;
CREATE USER IF NOT EXISTS 'mywebapp'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'mywebapp'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON mywebapp.* TO 'mywebapp'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> [4/9] Installing application files"
install -d -o app -g app -m 0755 /opt/mywebapp
install -o app -g app -m 0644 app/main.py    /opt/mywebapp/main.py
install -o app -g app -m 0644 app/migrate.py /opt/mywebapp/migrate.py

echo "==> [5/9] Writing app environment file"
cat > /etc/mywebapp/mywebapp.env <<EOF
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=mywebapp
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=mywebapp
EOF
chown root:app /etc/mywebapp/mywebapp.env
chmod 0640 /etc/mywebapp/mywebapp.env

echo "==> [6/9] Installing systemd unit"
install -m 0644 deploy/mywebapp.service /etc/systemd/system/mywebapp.service
systemctl daemon-reload
systemctl enable --now mywebapp

echo "==> [7/9] Configuring nginx"
install -m 0644 deploy/nginx.conf /etc/nginx/sites-available/mywebapp
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> [8/9] Installing sudoers for operator"
install -m 0440 -o root -g root deploy/sudoers.d-operator /etc/sudoers.d/operator
visudo -cf /etc/sudoers.d/operator

echo "==> [9/9] Creating gradebook and locking default user"
echo 16 > /home/student/gradebook
chown student:student /home/student/gradebook

if id ubuntu &>/dev/null; then
    usermod -L ubuntu
fi

echo "==> Done. Try:  curl -s http://127.0.0.1/  |  systemctl status mywebapp"
