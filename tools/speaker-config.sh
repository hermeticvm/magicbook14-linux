#!/bin/bash
# Switch speaker-pair configuration for the characterization suite.
#   speaker-config.sh D   fixup active, all pairs on (default state)
#   speaker-config.sh C   fixup active, 0x1a bass pair SOLO (mute others)
#   speaker-config.sh B   fixup active, 0x14 pair SOLO
#   speaker-config.sh A   stock module: only 0x1b pair (audio blinks ~15 s)
# Requires root (module swap for A; amixer for B/C/D).
set -euo pipefail
CFG=$1
KVER=$(uname -r)
OV="/usr/lib/modules/$KVER/updates/snd-hda-codec-alc269.ko"

unmute_all(){ amixer -c 0 sset "Speaker" on >/dev/null 2>&1 || true; amixer -c 0 sset "Bass Speaker" on >/dev/null 2>&1 || true; }

case $CFG in
  D) unmute_all; echo "config D: all pairs on";;
  C) unmute_all; amixer -c 0 sset "Speaker" off >/dev/null 2>&1 || true; echo "config C: bass pair (0x1a) solo";;
  B) unmute_all; amixer -c 0 sset "Bass Speaker" off >/dev/null 2>&1 || true; echo "config B: 0x14 pair solo (Speaker on, Bass off)";;
  A)
    # stock module: swap overlay out, rebind codec, then restore overlay on disk
    systemctl --user stop pipewire pipewire.socket pipewire-pulse.socket pipewire-pulse wireplumber 2>/dev/null || true
    echo "0000:00:1f.3" > /sys/bus/pci/drivers/sof-audio-pci-intel-mtl/unbind
    sleep 1
    rmmod snd_hda_codec_alc269 snd_hda_codec_realtek_lib 2>/dev/null || true
    mv "$OV" /var/tmp/alc269-stash.ko
    depmod "$KVER"
    echo "0000:00:1f.3" > /sys/bus/pci/drivers/sof-audio-pci-intel-mtl/bind
    sleep 3
    mv /var/tmp/alc269-stash.ko "$OV"
    depmod "$KVER"
    systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true
    sleep 2
    echo "config A: stock module, 0x1b pair only (fixup restored on disk)"
    ;;
  *) echo "usage: speaker-config.sh A|B|C|D" >&2; exit 1;;
esac
