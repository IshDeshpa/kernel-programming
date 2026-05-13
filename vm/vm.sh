#!/bin/bash
set -e

BASE_IMAGE="ubuntu-22.04-base.img"
DISK="ubuntu-22.04.qcow2"
SEED_ISO="seed.iso"
DISK_SIZE="20G"

# ── 1. Download base cloud image ──────────────────────────────────────────────
if [ ! -f "$BASE_IMAGE" ]; then
  echo "[*] Downloading Ubuntu 22.04 cloud image..."
  wget -O "$BASE_IMAGE" \
    https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

# ── 2. Create a qcow2 disk backed by the base image ───────────────────────────
if [ ! -f "$DISK" ]; then
  echo "[*] Creating $DISK_SIZE qcow2 disk..."
  qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$DISK" "$DISK_SIZE"
fi

# ── 3. Build cloud-init seed ISO (sets user + password + SSH) ─────────────────
if [ ! -f "$SEED_ISO" ]; then
  echo "[*] Creating cloud-init seed ISO..."
  # Use cloud-localds if available, otherwise genisoimage/mkisofs
  genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
    seed/user-data seed/meta-data
fi

# ── 4. Boot ───────────────────────────────────────────────────────────────────
echo "[*] Starting VM... (login: ubuntu / ubuntu)"
echo "    SSH: ssh ubuntu@localhost -p 2222"
echo "    Quit: Ctrl-A X"
echo ""

qemu-system-x86_64 \
  -m 2G \
  -smp 2 \
  -drive file="$DISK",format=qcow2,if=virtio,cache=writeback \
  -drive file="$SEED_ISO",format=raw,media=cdrom,readonly=on \
  -net nic,model=virtio \
  -net user,hostfwd=tcp::2222-:22 \
  -nographic
