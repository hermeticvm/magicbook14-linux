#!/bin/bash
# Deferred runner: pacman hooks run inside the transaction lock, and our
# rebuild runs pacman itself (for curl/bc deps), which would deadlock. So
# this script just schedules the real work for one minute later, outside
# the lock, via systemd-run.
if [ "$(id -u)" -eq 0 ]; then
  systemd-run --unit=honor-modules-rebuild --on-active=60 \
    /usr/local/bin/honor-modules-rebuild.sh >/dev/null 2>&1
  echo "scheduled honor-modules-rebuild in 60s"
fi
