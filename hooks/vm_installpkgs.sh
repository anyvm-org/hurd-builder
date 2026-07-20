# In-guest install script for hurd (piped into the guest sh by build.py with
# ANYVM_PKGS prepended; runs under set -e).
#
# The pre-installed image's apt lists are a snapshot of the fast-moving
# debian-ports archive, so a plain `apt-get install` can reference package
# versions that no longer exist in the pool. Refresh the indexes first.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y $ANYVM_PKGS
