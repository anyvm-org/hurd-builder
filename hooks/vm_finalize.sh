# Image-slimming finalize. Runs as the LAST in-guest hook, after postBuild
# and the VM_PRE_INSTALL_PKGS apt installs.
#
# No fstrim here: the Hurd has no fstrim, and the disk sits on IDE (no
# discard anyway). exportOVA's qcow2 conversion re-sparsifies zeros, so just
# drop the apt archive cache.

echo "=== finalize: image cleanup ==="

apt-get clean || true

df -h 2>/dev/null || df || true
echo "=== finalize: image cleanup done ==="
