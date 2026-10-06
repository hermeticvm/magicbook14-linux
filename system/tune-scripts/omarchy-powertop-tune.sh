#!/bin/bash
# Safe powertop tunables for HONOR MagicBook Art 14 (MRA-XXX), selected by
# measurement 2026-10-05. Runtime PM lets idle PCI devices park, which is what
# lets the Meteor Lake package reach deeper states. No daemons, no EPP changes.
set -u

# NMI watchdog off
echo 0 > /proc/sys/kernel/nmi_watchdog 2>/dev/null

# Runtime PM: idle PCI devices park
for d in \
  0000:00:04.0 0000:00:0a.0 0000:00:00.0 0000:00:14.3 \
  0000:00:1f.0 0000:00:14.2 0000:00:08.0 0000:00:12.0 \
  0000:00:1f.5 0000:01:00.0; do
  echo auto > "/sys/bus/pci/devices/$d/power/control" 2>/dev/null
done

# Audio codec PM (snd_hda_intel module param, set via modprobe.d at load)
# WiFi power save
iw dev wlp0s20f3 set power_save on 2>/dev/null
