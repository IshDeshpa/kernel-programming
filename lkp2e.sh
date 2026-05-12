#!/usr/bin/env bash
# =============================================================================
# lkp2e.sh – Build, run, and manage the Linux Kernel Programming 2E container.
#
# Usage:
#   ./lkp2e.sh [command]
#
# Commands:
#   run       Build image if missing, start container  (default)
#   build     (Re)build the image
#   rebuild   Force-rebuild image then start container
#   ssh       SSH into the running container
#   shell     Attach a bash shell via docker exec (no SSH needed)
#   stop      Stop and remove the container
#   status    Show running container info
#   logs      Tail container logs (sshd output)
#   help      Print this message
#
# Environment overrides:
#   IMAGE_NAME       (default: lkp2e)
#   CONTAINER_NAME   (default: lkp2e-dev)
#   HOST_SSH_PORT    (default: 2222)
#   WORKSPACE_DIR    (default: current directory)
#   KERNEL_VER       (default: output of uname -r)
# =============================================================================

set -euo pipefail

# ── Configurable defaults (override via environment) ─────────────────────────
IMAGE_NAME="${IMAGE_NAME:-lkp2e}"
CONTAINER_NAME="${CONTAINER_NAME:-lkp2e-dev}"
HOST_SSH_PORT="${HOST_SSH_PORT:-2222}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
KERNEL_VER="${KERNEL_VER:-generic}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"

# Local dir that stores the generated SSH keypair (gitignore this)
SSH_DIR="${WORKSPACE_DIR}/.lkp2e"
SSH_KEY="${SSH_DIR}/id_lkp2e"

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

log()  { echo -e "${GREEN}[lkp2e]${NC} $*"; }
info() { echo -e "${BLUE}[lkp2e]${NC} $*"; }
warn() { echo -e "${YELLOW}[lkp2e] WARN:${NC} $*"; }
die()  { echo -e "${RED}[lkp2e] ERROR:${NC} $*" >&2; exit 1; }
hr()   { echo -e "${BOLD}────────────────────────────────────────────────────${NC}"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
check_deps() {
    command -v docker    &>/dev/null || die "docker not found. Install Docker and retry."
    command -v ssh       &>/dev/null || die "ssh client not found."
    command -v ssh-keygen &>/dev/null || die "ssh-keygen not found."
    docker info &>/dev/null          || die "Docker daemon is not running (or no permission)."
}

# ── SSH key management ────────────────────────────────────────────────────────
setup_ssh_keys() {
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"

    # Add to .gitignore so the private key doesn't get committed
    local gitignore="${WORKSPACE_DIR}/.gitignore"
    if [[ -f "${gitignore}" ]] && ! grep -qF '.lkp2e/' "${gitignore}"; then
        echo '.lkp2e/' >> "${gitignore}"
        log "Added .lkp2e/ to .gitignore"
    fi

    if [[ ! -f "${SSH_KEY}" ]]; then
        log "Generating ED25519 SSH keypair → ${SSH_KEY}"
        ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "lkp2e-docker-$(date +%Y%m%d)"
        log "Public key: $(cat "${SSH_KEY}.pub")"
    else
        log "Using existing SSH keypair at ${SSH_KEY}"
    fi
}

read_pubkey() {
    [[ -f "${SSH_KEY}.pub" ]] || die "Public key not found at ${SSH_KEY}.pub — run: $0 build"
    cat "${SSH_KEY}.pub"
}

# ── Build ─────────────────────────────────────────────────────────────────────
build_image() {
    [[ -f "${DOCKERFILE}" ]] || \
        die "Dockerfile not found at '${DOCKERFILE}'. Run from the same directory or set DOCKERFILE=."

    hr
    log "Building image '${IMAGE_NAME}'"
    info "  Dockerfile : ${DOCKERFILE}"
    info "  KERNEL_VER : ${KERNEL_VER}"
    hr

    docker build \
        --build-arg KERNEL_VER="${KERNEL_VER}" \
        --tag  "${IMAGE_NAME}" \
        --file "${DOCKERFILE}" \
        "$(dirname "${DOCKERFILE}")"

    log "Image '${IMAGE_NAME}' built successfully."
}

image_exists() {
    docker image inspect "${IMAGE_NAME}" &>/dev/null
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_container() {
    # Remove any stale container with the same name
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Removing stale container '${CONTAINER_NAME}' ..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null
    fi

    # Check the host port is free
    if ss -tlnp 2>/dev/null | grep -q ":${HOST_SSH_PORT} " || \
       lsof -iTCP:"${HOST_SSH_PORT}" -sTCP:LISTEN &>/dev/null 2>&1; then
        warn "Port ${HOST_SSH_PORT} is already in use on the host."
        warn "Set HOST_SSH_PORT=<other> to use a different port."
    fi

    local pubkey
    pubkey=$(read_pubkey)

    hr
    log "Starting container '${CONTAINER_NAME}'"
    info "  Workspace  : ${WORKSPACE_DIR} → /workspace"
    info "  SSH port   : localhost:${HOST_SSH_PORT} → container:22"
    info "  Kernel mods: /lib/modules mounted read-only"
    hr

    docker run \
        --detach \
        --name "${CONTAINER_NAME}" \
        \
        `# Capabilities needed for kernel/BPF/perf/kmod work` \
        --privileged \
        --cap-add SYS_PTRACE \
        --cap-add SYS_ADMIN \
        --cap-add NET_ADMIN \
        --security-opt seccomp=unconfined \
        --security-opt apparmor=unconfined \
        \
        `# Volume mounts` \
        --volume "${WORKSPACE_DIR}:/workspace" \
        --volume /lib/modules:/lib/modules:ro \
        --volume /sys/kernel/debug:/sys/kernel/debug \
        --volume "${HOME}/.config/nvim:/root/.config/nvim:ro" \
        --volume "${HOME}/.local/share/nvim:/root/.local/share/nvim" \
        `# Network` \
        --publish "${HOST_SSH_PORT}:22" \
        \
        `# SSH key injection (read by entrypoint.sh)` \
        --env "SSH_PUBKEY=${pubkey}" \
        \
        `# Keep TERM sane inside the container` \
        --env TERM="${TERM:-xterm-256color}" \
        \
        "${IMAGE_NAME}" >/dev/null

    log "Container started. Waiting for sshd ..."
    local retries=20
    until docker exec "${CONTAINER_NAME}" pgrep -x sshd &>/dev/null; do
        sleep 1
        (( retries-- )) || die "sshd did not start within 20 s. Check: docker logs ${CONTAINER_NAME}"
    done

    print_connect_info
}

# ── Print connection help ─────────────────────────────────────────────────────
print_connect_info() {
    local ssh_cmd="ssh -p ${HOST_SSH_PORT} -i ${SSH_KEY} \
-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost"
    hr
    log "Ready!  Connect with:"
    echo
    echo -e "  ${BOLD}SSH:${NC}   ${BLUE}${ssh_cmd}${NC}"
    echo -e "  ${BOLD}Shell:${NC} ${BLUE}./lkp2e.sh shell${NC}  (docker exec, no SSH)"
    echo -e "  ${BOLD}Logs:${NC}  ${BLUE}./lkp2e.sh logs${NC}"
    echo -e "  ${BOLD}Stop:${NC}  ${BLUE}./lkp2e.sh stop${NC}"
    echo
    echo -e "  Your workspace is mounted at ${BOLD}/workspace${NC} inside the container."
    hr
}

# ── SSH connect ───────────────────────────────────────────────────────────────
ssh_connect() {
    container_must_be_running
    [[ -f "${SSH_KEY}" ]] || die "SSH key not found at ${SSH_KEY}. Run: $0 run"
    exec ssh \
        -p "${HOST_SSH_PORT}" \
        -i "${SSH_KEY}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=30 \
        root@localhost
}

# ── Shell (exec) ──────────────────────────────────────────────────────────────
shell_exec() {
    container_must_be_running
    exec docker exec -it "${CONTAINER_NAME}" bash
}

# ── Stop ──────────────────────────────────────────────────────────────────────
stop_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Stopping and removing container '${CONTAINER_NAME}' ..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null
        log "Done."
    else
        warn "Container '${CONTAINER_NAME}' is not running."
    fi
}

# ── Status ────────────────────────────────────────────────────────────────────
show_status() {
    hr
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Container '${CONTAINER_NAME}' is ${GREEN}running${NC}."
        echo
        docker ps \
            --filter "name=^${CONTAINER_NAME}$" \
            --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        echo
        print_connect_info
    else
        warn "Container '${CONTAINER_NAME}' is ${RED}not running${NC}."
    fi
    hr
}

# ── Logs ──────────────────────────────────────────────────────────────────────
show_logs() {
    container_must_be_running
    docker logs -f "${CONTAINER_NAME}"
}

# ── Guard helpers ─────────────────────────────────────────────────────────────
container_must_be_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" || \
        die "Container '${CONTAINER_NAME}' is not running. Start it with: $0 run"
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    sed -n '/^# Usage/,/^# ====/p' "$0" | grep -v '^# ====' | sed 's/^# \?//'
    echo
    echo "Current settings:"
    echo "  IMAGE_NAME     = ${IMAGE_NAME}"
    echo "  CONTAINER_NAME = ${CONTAINER_NAME}"
    echo "  HOST_SSH_PORT  = ${HOST_SSH_PORT}"
    echo "  WORKSPACE_DIR  = ${WORKSPACE_DIR}"
    echo "  KERNEL_VER     = ${KERNEL_VER}"
    echo "  DOCKERFILE     = ${DOCKERFILE}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_deps

CMD="${1:-run}"
case "${CMD}" in
    run)
        setup_ssh_keys
        image_exists || build_image
        run_container
        ;;
    build)
        setup_ssh_keys
        build_image
        ;;
    rebuild)
        setup_ssh_keys
        build_image
        run_container
        ;;
    ssh)
        ssh_connect
        ;;
    shell)
        shell_exec
        ;;
    stop)
        stop_container
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        warn "Unknown command: '${CMD}'"
        echo
        usage
        exit 1
        ;;
esac
