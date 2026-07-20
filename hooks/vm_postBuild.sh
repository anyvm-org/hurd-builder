# in-guest postBuild hook (piped to the guest's sh over SSH by build.py).
#
# Keep everything tolerant: build.py runs this over the remote shell with the
# remote shell exiting non-zero on any unhandled error, and one apt hiccup
# should not abort the whole build.
#
# Debian GNU/Hurd uses sysvinit; openssh-server ships enabled in rc2.d, but
# re-affirm it so sshd is guaranteed to survive the reboot build.py does
# right after this hook.

export DEBIAN_FRONTEND=noninteractive

echo "=================== hurd postBuild ===="

echo "--- system identification ---"
uname -a || true
cat /etc/os-release 2>/dev/null || true

echo "--- ensuring ssh starts at boot ---"
update-rc.d ssh defaults 2>/dev/null || update-rc.d ssh enable 2>/dev/null || true

# The pre-installed image ships a "demo" user with an empty password; that is
# fine for a local toy VM but not for an image that anyvm may expose on a
# LAN-visible port. Lock the account (root access is key-based).
usermod -L demo 2>/dev/null || true

echo "hurd postBuild done."

exit 0
