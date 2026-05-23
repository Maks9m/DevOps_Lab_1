#!/usr/bin/env bash
# runner-setup.sh — prepare a Ubuntu 24.04 VM as a GitHub self-hosted runner.
#
# Run once as root on the runner VM:
#     sudo bash runner-setup.sh
#
# This installs all the OS-level dependencies and downloads the actions-runner
# tarball, but does NOT register the runner with GitHub — that requires a fresh
# token from the GitHub UI and is performed manually by the operator. The token
# MUST NOT be committed to the repo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Must run as root (use sudo)." >&2
    exit 1
fi

RUNNER_USER="${RUNNER_USER:-ubuntu}"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"
RUNNER_VERSION="${RUNNER_VERSION:-2.319.1}"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64) RUNNER_ARCH="x64" ;;
    arm64) RUNNER_ARCH="arm64" ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac
RUNNER_TARBALL="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TARBALL}"

echo "==> [1/4] Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg jq openssh-client rsync \
    git libicu74 lsb-release

echo "==> [2/4] Installing Docker CLI (for any container ops on the runner)"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
fi
# shellcheck source=/dev/null
. /etc/os-release
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends docker-ce-cli

echo "==> [3/4] Downloading actions-runner v${RUNNER_VERSION}"
install -d -o "${RUNNER_USER}" -g "${RUNNER_USER}" -m 0755 "${RUNNER_DIR}"
if [[ ! -f "${RUNNER_DIR}/run.sh" ]]; then
    sudo -u "${RUNNER_USER}" bash -c "
        cd '${RUNNER_DIR}' &&
        curl -fsSL -o '${RUNNER_TARBALL}' '${RUNNER_URL}' &&
        tar -xzf '${RUNNER_TARBALL}' &&
        rm '${RUNNER_TARBALL}'
    "
fi

echo "==> [4/4] Done."
cat <<EOF

  Runner downloaded to ${RUNNER_DIR}.

  Finish registration MANUALLY:
    1. In GitHub: Settings -> Actions -> Runners -> 'New self-hosted runner'.
       Copy the generated token (one-time, short-lived).
    2. On this VM:
         su - ${RUNNER_USER}
         cd ${RUNNER_DIR}
         ./config.sh --url https://github.com/<owner>/<repo> \\
                     --token <PASTE_TOKEN_HERE> \\
                     --labels self-hosted,deploy \\
                     --unattended
    3. Install as a service:
         sudo ./svc.sh install
         sudo ./svc.sh start

  Then generate the deploy SSH key for the target VM:
         su - ${RUNNER_USER} -c 'ssh-keygen -t ed25519 -f ~/.ssh/id_lab3 -N ""'
         su - ${RUNNER_USER} -c 'cat ~/.ssh/id_lab3.pub'     # copy to target's authorized_keys
         su - ${RUNNER_USER} -c 'cat ~/.ssh/id_lab3'         # paste into TARGET_SSH_KEY secret

EOF
