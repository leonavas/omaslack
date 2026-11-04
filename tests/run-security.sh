#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# No network, home/session sockets, real accounts, writable checkout or build.
# Scratch is an ephemeral 64 MiB tmpfs; all generated fixtures disappear.
exec timeout 60s bwrap --unshare-all --die-with-parent --new-session --clearenv \
  --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib /lib64 \
  --ro-bind /etc/ld.so.cache /etc/ld.so.cache --ro-bind /etc/fonts /etc/fonts \
  --proc /proc --remount-ro /proc \
  --ro-bind /dev/null /dev/null --ro-bind /dev/urandom /dev/urandom --ro-bind /dev/random /dev/random \
  --size 67108864 --tmpfs /scratch --symlink /scratch/tmp /tmp \
  --dir /repo --ro-bind "$repo_dir/lib" /repo/lib --ro-bind "$repo_dir/core" /repo/core \
  --ro-bind "$repo_dir/ui" /repo/ui --ro-bind "$repo_dir/login" /repo/login \
  --ro-bind "$repo_dir/Service.qml" /repo/Service.qml --ro-bind "$repo_dir/tests" /repo/tests \
  --setenv PATH /usr/bin:/bin --setenv HOME /scratch/home --setenv TMPDIR /scratch/tmp \
  --setenv XDG_RUNTIME_DIR /scratch/run --setenv XDG_CONFIG_HOME /scratch/config \
  --setenv XDG_CACHE_HOME /scratch/cache --setenv QT_QPA_PLATFORM offscreen \
  --setenv QSG_RHI_BACKEND software --setenv QT_QUICK_BACKEND software \
  --setenv QML_DISABLE_DISK_CACHE 1 --setenv PYTHONDONTWRITEBYTECODE 1 \
  --setenv QT_FORCE_STDERR_LOGGING 1 \
  --chdir /scratch \
  /usr/bin/prlimit --as=2147483648 --cpu=30 --nproc=256 --nofile=128 --fsize=16777216 -- \
  /bin/sh -c 'mkdir -m 700 /scratch/home /scratch/tmp /scratch/run /scratch/config /scratch/cache; exec python3 -I -B /repo/tests/security_regression.py'
