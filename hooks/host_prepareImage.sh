#!/bin/bash
# host-side prepareImage hook (runs in main process env after _prep_vhd_disk
# materialized "${VM_OS_NAME}.qcow2" but BEFORE the VM is started).
#
# The Debian GNU/Hurd pre-installed image ships root with an EMPTY password
# and (per the image README) openssh-server preinstalled, but no key and no
# guaranteed PermitRootLogin. libguestfs cannot inspect a GNU/Hurd guest, so
# instead of virt-customize we attach the qcow2 via qemu-nbd (same pattern as
# blissos-builder/hooks/offline-construct.sh, proven on both GitHub runners
# and WSL) and edit the ext2 root filesystem directly from the Linux host:
#
#   1. bake the build's SSH public key into /root/.ssh/authorized_keys
#   2. append PermitRootLogin/PubkeyAuthentication/AcceptEnv to sshd_config
#   3. set the conventional root password (VM_ROOT_PASSWORD) in /etc/shadow
#   4. generate SSH host keys if the image shipped without them
#   5. best-effort: add console=com0 to the gnumach boot line so kernel boot
#      messages land in the QEMU serial log (CI diagnosability)
#
# After this hook the whole build runs over ssh through the slirp hostfwd
# port; the console is never touched.

set -e

echo "Preparing ${VM_OS_NAME}.qcow2 (Debian GNU/Hurd) via qemu-nbd"

# Generate the build's SSH keypair now so we can inject its public key into
# the image. build.py would otherwise create the same key later; reuse it.
if [ ! -e "$HOME/.ssh/id_rsa" ]; then
  ssh-keygen -f "$HOME/.ssh/id_rsa" -q -N ""
fi
_pub="$(cat "$HOME/.ssh/id_rsa.pub")"

_qcow="${VM_OS_NAME}.qcow2"
NBD=/dev/nbd0
M_ROOT="$(pwd)/mnt-hurd-root"

_cleanup() {
  sudo umount "$M_ROOT" 2>/dev/null || true
  sudo qemu-nbd --disconnect "$NBD" 2>/dev/null || true
}
trap _cleanup EXIT

mkdir -p "$M_ROOT"

sudo modprobe nbd max_part=16
sudo qemu-nbd --disconnect "$NBD" 2>/dev/null || true
sudo qemu-nbd --connect="$NBD" "$_qcow"
sudo partprobe "$NBD" 2>/dev/null || true
sleep 2

# Find the root filesystem: the ext2 partition that contains /hurd (the
# translator directory -- definitive GNU/Hurd marker). The published images
# have the root on a logical partition (p5-style layouts exist), so probe
# every partition instead of hardcoding an index.
_root_part=""
for _p in "$NBD"p*; do
  [ -b "$_p" ] || continue
  _t="$(sudo blkid -o value -s TYPE "$_p" 2>/dev/null || true)"
  case "$_t" in
    ext2|ext3|ext4) ;;
    *) continue ;;
  esac
  if sudo mount -o ro "$_p" "$M_ROOT" 2>/dev/null; then
    if [ -d "$M_ROOT/hurd" ] && [ -d "$M_ROOT/etc" ]; then
      _root_part="$_p"
      sudo umount "$M_ROOT"
      break
    fi
    sudo umount "$M_ROOT"
  fi
done

if [ -z "$_root_part" ]; then
  echo "FATAL: no ext2 partition with /hurd + /etc found on $NBD" >&2
  sudo fdisk -l "$NBD" || true
  exit 1
fi
echo "GNU/Hurd root filesystem: $_root_part"

sudo mount "$_root_part" "$M_ROOT"

# --- 1. authorized_keys -----------------------------------------------------
sudo mkdir -p "$M_ROOT/root/.ssh"
echo "$_pub" | sudo tee -a "$M_ROOT/root/.ssh/authorized_keys" >/dev/null
sudo chown 0:0 "$M_ROOT/root/.ssh" "$M_ROOT/root/.ssh/authorized_keys"
sudo chmod 700 "$M_ROOT/root/.ssh"
sudo chmod 600 "$M_ROOT/root/.ssh/authorized_keys"

# --- 2. sshd_config ---------------------------------------------------------
# Appended lines: the first match wins in sshd_config, but neither option is
# set in the stock file, so our appended values are the active ones.
if [ ! -e "$M_ROOT/etc/ssh/sshd_config" ]; then
  echo "FATAL: /etc/ssh/sshd_config not in the image (openssh-server missing?)" >&2
  echo "The whole build drives the guest over ssh; cannot continue." >&2
  exit 1
fi
sudo tee -a "$M_ROOT/etc/ssh/sshd_config" >/dev/null <<'SSHDCFG'
PermitRootLogin yes
PubkeyAuthentication yes
AcceptEnv *
SSHDCFG

# --- 3. root password -------------------------------------------------------
_hash="$(openssl passwd -6 "${VM_ROOT_PASSWORD:-anyvm.org}")"
sudo python3 - "$_hash" "$M_ROOT/etc/shadow" <<'PYEOF'
import sys
h, path = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines(True)
out = []
for l in lines:
    if l.startswith("root:"):
        f = l.split(":")
        f[1] = h
        l = ":".join(f)
    out.append(l)
open(path, "w").writelines(out)
PYEOF

# --- 4. SSH host keys (only if the image shipped without them) --------------
if ! ls "$M_ROOT"/etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
  echo "No SSH host keys in the image; generating rsa + ed25519"
  rm -f hostkey.rsa hostkey.rsa.pub hostkey.ed25519 hostkey.ed25519.pub
  ssh-keygen -q -t rsa -f hostkey.rsa -N "" -C "root@${VM_OS_NAME}"
  ssh-keygen -q -t ed25519 -f hostkey.ed25519 -N "" -C "root@${VM_OS_NAME}"
  sudo install -m 600 -o 0 -g 0 hostkey.rsa "$M_ROOT/etc/ssh/ssh_host_rsa_key"
  sudo install -m 644 -o 0 -g 0 hostkey.rsa.pub "$M_ROOT/etc/ssh/ssh_host_rsa_key.pub"
  sudo install -m 600 -o 0 -g 0 hostkey.ed25519 "$M_ROOT/etc/ssh/ssh_host_ed25519_key"
  sudo install -m 644 -o 0 -g 0 hostkey.ed25519.pub "$M_ROOT/etc/ssh/ssh_host_ed25519_key.pub"
fi

# --- 5. serial console for CI diagnosability (best-effort) ------------------
# gnumach sends its console to com0 when the boot line carries console=com0;
# QEMU's -serial chardev then captures the whole kernel boot in
# <os>.serial.log, which the wait/enablessh hooks tail on every stall. If the
# grub.cfg layout ever changes this edit is skipped, not fatal.
_grubcfg="$M_ROOT/boot/grub/grub.cfg"
if sudo test -f "$_grubcfg"; then
  sudo python3 - "$_grubcfg" <<'PYEOF' || echo "WARNING: grub console=com0 edit failed; continuing without serial console"
import sys
path = sys.argv[1]
src = open(path).read()
out = []
changed = False
for l in src.splitlines(True):
    s = l.rstrip("\n")
    if ("multiboot" in s and "gnumach" in s and "console=com0" not in s):
        l = s + " console=com0\n"
        changed = True
    out.append(l)
if changed:
    open(path, "w").writelines(out)
    print("grub.cfg: appended console=com0 to the gnumach boot line(s)")
else:
    print("grub.cfg: no gnumach multiboot line found; left untouched")
PYEOF
else
  echo "WARNING: no /boot/grub/grub.cfg on the root fs; skipping console=com0"
fi

# Targeted syncfs of just this mount -- NEVER a bare global `sync` (on WSL the
# /mnt/* drvfs mounts can wedge in request_wait_answer; see blissos notes).
sync -f "$M_ROOT" 2>/dev/null || true
sudo umount "$M_ROOT"
sudo qemu-nbd --disconnect "$NBD"
trap - EXIT

# Make sure qemu can read+write the image on the following steps.
sudo chmod 0666 "$_qcow" 2>/dev/null || true

echo "Image prepared:"
ls -lh "$_qcow"
