#!/bin/bash
# host-side enablessh hook -- runs after _gen_enablessh_local() has written
# the enablessh.local script. The image already has the build's public key
# baked into root's authorized_keys (see host_prepareImage.sh), so we connect
# over the slirp hostfwd port and push enablessh.local to re-affirm sshd
# config and re-add the key.
#
# When this hook runs, host_waitForLoginTag has already gated on a real ssh
# handshake, so this loop is mostly a belt-and-suspenders guard for the gap
# between the gate ssh and this one.

set -u

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=30
  -p "${VM_SSH_PORT}"
)

SERIAL_LOG="${VM_OS_NAME:-hurd}.serial.log"

_n=0
while ! timeout 60 ssh "${SSH_OPTS[@]}" "root@127.0.0.1" exit >/dev/null 2>&1; do
  # Dump a serial-log tail every 6 iters (~1 min) so we can see what the
  # guest is doing instead of staring at opaque "waiting" lines.
  if [ $((_n % 6)) -eq 0 ] && [ -f "$SERIAL_LOG" ]; then
    echo "--- serial log tail (iter $_n) ---"
    # See host_waitForLoginTag.sh for why we strip C0 controls and pass -a
    # to grep.
    tail -c 8192 "$SERIAL_LOG" \
      | tr -d '\000\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\034\035\036\037' \
      | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g' \
      | grep -av '^[[:space:]]*$' \
      | tail -10
    echo "--- end serial tail ---"
  fi
  echo "waiting for sshd on 127.0.0.1:${VM_SSH_PORT} (iter $_n) ..."
  sleep 10
  _n=$((_n + 1))
  if [ "$_n" -gt 60 ]; then
    echo "sshd did not come up in time, continuing anyway"
    break
  fi
done

echo "Pushing enablessh.local to root@127.0.0.1:${VM_SSH_PORT}"
timeout 120 ssh "${SSH_OPTS[@]}" "root@127.0.0.1" sh <enablessh.local || true

# give sshd a moment to settle
sleep 5
