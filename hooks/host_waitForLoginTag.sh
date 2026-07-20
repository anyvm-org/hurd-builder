#!/bin/bash
# host-side waitForLoginTag override (called from start_and_wait after
# startVM + openConsole, before the default waitForText fires).
#
# hooks/host_prepareImage.sh already baked SSH access into the qcow2, so we
# poll the slirp hostfwd port on 127.0.0.1:$VM_SSH_PORT until sshd actually
# answers, and never depend on console text matching.
#
# IMPORTANT: do NOT probe with a bare TCP connect (e.g. `echo > /dev/tcp/...`).
# slirp's `hostfwd` makes QEMU listen on the HOST port the moment it starts,
# completing the host-side 3-way handshake well before the guest kernel has
# even POSTed. A bare TCP probe therefore returns "open" immediately and we
# fall through to the real ssh phase against a guest that's nowhere near up.
# Probe with `ssh ... exit` so the test only succeeds when the GUEST sshd
# actually answers.

set -u

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=10
  -o BatchMode=yes
  -p "${VM_SSH_PORT}"
)

# build.py writes the serial log under build/ (exported as VM_WORKDIR);
# fall back to the repo root for a standalone hook run.
SERIAL_LOG="${VM_WORKDIR:+$VM_WORKDIR/}${VM_OS_NAME:-hurd}.serial.log"

_n=0
# 120 iters * (timeout 30 + sleep 10) = up to ~80 min worst case; the Hurd
# boots in well under a minute on KVM, and single-digit minutes even under
# TCG (uniprocessor guest, small userland).
while [ "$_n" -lt 120 ]; do
  if timeout 30 ssh "${SSH_OPTS[@]}" "root@127.0.0.1" exit >/dev/null 2>&1; then
    echo "sshd is answering ssh on 127.0.0.1:${VM_SSH_PORT}"
    break
  fi
  # Every 6 iterations (~1 minute), dump the last lines of the guest serial
  # log (gnumach boots with console=com0, see host_prepareImage.sh) so a
  # stalled boot is diagnosable from the CI log alone.
  if [ $((_n % 6)) -eq 0 ] && [ -f "$SERIAL_LOG" ]; then
    echo "--- serial log tail (iter $_n) ---"
    # -a forces grep to treat the file as text (the serial chardev embeds
    # ANSI / NUL bytes); the tr strips C0 control bytes except CR/LF.
    tail -c 8192 "$SERIAL_LOG" \
      | tr -d '\000\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\034\035\036\037' \
      | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g' \
      | grep -av '^[[:space:]]*$' \
      | tail -10
    echo "--- end serial tail ---"
  fi
  echo "waiting for VM sshd on 127.0.0.1:${VM_SSH_PORT} (iter $_n) ..."
  sleep 10
  _n=$((_n + 1))
done

sleep 5
