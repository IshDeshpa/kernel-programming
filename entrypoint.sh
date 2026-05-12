#!/usr/bin/env bash
# entrypoint.sh – injected into the container by the Dockerfile.
# Populates /root/.ssh/authorized_keys from the SSH_PUBKEY env var,
# then starts sshd in the foreground (PID 1 equivalent via exec).
set -euo pipefail

# ── SSH key injection ─────────────────────────────────────────────────────────
if [[ -z "${SSH_PUBKEY:-}" ]]; then
    echo "[entrypoint] WARNING: SSH_PUBKEY env var is empty — key-based login will not work." >&2
else
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "${SSH_PUBKEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[entrypoint] SSH public key installed for root."
fi

# ── Optional: set root password if SSH_PASSWORD is provided ──────────────────
if [[ -n "${SSH_PASSWORD:-}" ]]; then
    echo "root:${SSH_PASSWORD}" | chpasswd
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    echo "[entrypoint] Password auth enabled for root."
fi

# ── Ensure /run/sshd exists (tmpfs may not persist) ──────────────────────────
mkdir -p /run/sshd

# ── Shell environment for SSH sessions ───────────────────────────────────────
cat > /root/.bash_profile <<'PROFILE'
# Start in the mounted workspace
[[ -d /workspace ]] && cd /workspace
 
# Source .bashrc if present
[[ -f ~/.bashrc ]] && source ~/.bashrc
 
export PS1='\[\e[32m\][lkp2e]\[\e[0m\] \[\e[33m\]\w\[\e[0m\] \$ '
export PATH="/usr/local/bin:${PATH}"
PROFILE
 
echo "[entrypoint] Starting sshd on port 22 ..."
exec /usr/sbin/sshd -D -e "$@"
