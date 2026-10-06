#!/bin/bash
# Rebuild the two out-of-tree kernel modules for the HONOR MagicBook Art 14
# (MRA-XXX, board M1010) after a kernel package update.
#
#   huawei-wmi.ko              HONOR Fn hotkey codes (keyboard backlight etc.)
#   snd-hda-codec-alc269.ko    wakes the sleeping speaker pin pairs (SSID 0x1ee7:0x2060)
#
# Triggered by /etc/pacman.d/hooks/95-honor-modules.hook after kernel updates,
# or run manually:  sudo /usr/local/bin/honor-modules-rebuild.sh
set -euo pipefail

SRC=/var/tmp/honor-modules/linux-$(uname -r | cut -d- -f1-3)
TARBALL=/var/tmp/honor-modules/linux-src.tar.xz
KVER="${1:-$(uname -r)}"
KBASE=$(echo "$KVER" | cut -d- -f1-3)
log(){ printf '\033[1;32m[honor-modules]\033[0m %s\n' "$*"; }
fail(){ printf '\033[1;31m[honor-modules]\033[0m %s\n' "$*" >&2; }

[ "$(id -u)" -eq 0 ] || { fail "run as root"; exit 1; }
command -v curl >/dev/null && command -v bc >/dev/null || { pacman -S --needed --noconfirm curl bc >/dev/null 2>&1 || true; }

mkdir -p "$(dirname "$SRC")"
cd "$(dirname "$SRC")"

if [ ! -d "$SRC" ]; then
  log "fetching kernel source $KBASE"
  curl -sfL -o "$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v${KBASE%%.*}.x/linux-$KBASE.tar.xz"
  tar xf "$TARBALL" "linux-$KBASE"
  rm -f "$TARBALL"
fi

cd "$SRC"
[ -f .config ] || cp "/usr/lib/modules/$KVER/build/.config" .config
printf -- '-3'       > localversion.10-pkgrel
printf -- '-omarchy' > localversion.20-pkgname
[ -f Module.symvers ] || cp "/usr/lib/modules/$KVER/build/Module.symvers" .
make olddefconfig >/dev/null 2>&1
make modules_prepare >/dev/null 2>&1

# 1. huawei-wmi: fetch per running-kernel source, add keymap entries
log "building huawei-wmi.ko"
HW=huawei-wmi.c
curl -sfL -o "$HW" "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/platform/x86/huawei-wmi.c?h=v$KBASE"
python3 - "$HW" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
additions = [
    ("0x283", "KEY_TOUCHPAD_ON",           "HONOR: touchpad lock toggle"),
    ("0x2a3", "KEY_TOUCHPAD_OFF",          None),
    ("0x288", "KEY_CAMERA_ACCESS_TOGGLE",  "HONOR: camera shutter"),
    ("0x2b1", "KEY_KBDILLUMDOWN",          "HONOR: keyboard backlight level"),
    ("0x2b2", "KEY_KBDILLUMDOWN",          None),
    ("0x2b3", "KEY_KBDILLUMUP",            None),
    ("0x2b4", "KEY_KBDILLUMTOGGLE",        None),
    ("0x2a0", "KEY_PROG1",                 "HONOR: performance mode"),
    ("0x2a1", "KEY_PROG1",                 None),
    ("0x2a6", "KEY_PROG1",                 None),
    ("0x2a7", "KEY_REFRESH_RATE_TOGGLE",   "HONOR: refresh rate toggle"),
    ("0x2e0", "KEY_CAMERA_ACCESS_ENABLE",  "HONOR: camera module"),
    ("0x2e1", "KEY_CAMERA_ACCESS_DISABLE", None),
]
ignores = [("0x2e5", "HONOR: EC keyboard-backlight notifications, not key presses"), ("0x2e6", None)]
anchor = "\t{ KE_END,"
if anchor not in src: raise SystemExit("anchor missing")
new = []
for code, key, comment in additions:
    if re.search(r"\b%s\b" % code, src): continue
    if comment: new.append("\t/* %s */\n" % comment)
    new.append("\t{ KE_KEY,    %s, { %s } },\n" % (code, key))
for code, comment in ignores:
    if re.search(r"\b%s\b" % code, src): continue
    if comment: new.append("\t/* %s */\n" % comment)
    new.append("\t{ KE_IGNORE, %s, { KEY_RESERVED } },\n" % code)
if new:
    src = src.replace(anchor, "".join(new) + anchor, 1)
    open(path, "w").write(src)
    print("keymap entries added")
else:
    print("keymap already complete")
PYEOF
cat > Makefile.hw <<'EOF'
obj-m += huawei-wmi.o
EOF
mkdir -p hw-build && cp "$HW" hw-build/huawei-wmi.c && cp Makefile.hw hw-build/Makefile
make -j"$(nproc)" -C "/usr/lib/modules/$KVER/build" M="$PWD/hw-build" modules >/dev/null 2>&1 \
  || fail "huawei-wmi build failed (continuing)"
install -D -m 0644 hw-build/huawei-wmi.ko "/usr/lib/modules/$KVER/updates/huawei-wmi.ko" 2>/dev/null || true

# 2. alc269: apply SSID quirk if missing
log "building snd-hda-codec-alc269.ko"
ALC=sound/hda/codecs/realtek/alc269.c
python3 - "$ALC" <<'PYEOF'
import sys
p = sys.argv[1]
src = open(p).read()
needle = 'SND_PCI_QUIRK(0x1ee7, 0x2081, "HONOR MRB-XXX M1020", ALC256_FIXUP_HONOR_MRB_XXX_M1020_AUDIO),'
add = 'SND_PCI_QUIRK(0x1ee7, 0x2060, "HONOR MRA-XXX M1010", ALC256_FIXUP_HONOR_MRB_XXX_M1020_AUDIO),'
if "0x2060" in src:
    print("alc269 already patched")
elif needle in src:
    open(p, "w").write(src.replace(needle, needle + "\n\t" + add))
    print("alc269 patched")
else:
    print("WARNING: alc269 anchor not found")
PYEOF
make -j"$(nproc)" M=sound/hda/codecs/realtek >/dev/null 2>&1 || fail "alc269 build failed (continuing)"
install -D -m 0644 sound/hda/codecs/realtek/snd-hda-codec-alc269.ko "/usr/lib/modules/$KVER/updates/snd-hda-codec-alc269.ko" 2>/dev/null || true

# 3. depmod so the overlay modules resolve
depmod "$KVER"

# 4. notify the user (best-effort)
TARGET_USER="${TARGET_USER:-SET_YOUR_USERNAME}"
if TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null)"; then
  runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
    omarchy-notification-send --app-name "Honor modules" -g 󰑓 "Kernel modules rebuilt for $KVER" \
    "Backlight keys and 6-speaker audio re-applied" >/dev/null 2>&1 || true
fi

log "done for $KVER"
