#!/bin/bash
# Build and install the HID-BPF fixup that keeps the FocalTech FTSC1000
# touchscreen (I2C HID 2808:5662) from exporting a phantom KEY_MICMUTE input
# device. Root cause, measurements and ruled-out alternatives: docs/touch.md
# in the magicbook14-linux repository; source in /usr/local/src/.
#
#   honor-hid-bpf-rebuild.sh            build, install, apply now, verify
#   honor-hid-bpf-rebuild.sh reapply    boot path, no build, no-op when fixed
#
# `reapply` exists because the udev attach races the hid-generic ->
# hid-multitouch handover at boot: the kernel recomputes a BPF-fixed report
# descriptor only when the program is registered on a device that has not
# been reprobed yet, and the handover sets HID_STAT_REPROBED first. Detach
# and re-attach after the device has settled, and the fixup takes.
#
# Nothing here needs repeating after a kernel update: the object is CO-RE
# and libbpf relocates it against the running kernel's BTF.
set -uo pipefail

SRC=/usr/local/src/honor-ftsc1000-micmute.bpf.c
OBJ_NAME=honor-ftsc1000-micmute.bpf.o
OBJ=/etc/udev-hid-bpf/$OBJ_NAME
HID_ID=2808:5662
REAPPLY_SERVICE=honor-hid-bpf-reapply.service
WORK="$(mktemp -d /var/tmp/honor-hidbpf.XXXXXX)"

trap 'rm -rf "$WORK"' EXIT
log(){ printf '\033[1;32m[honor-hidbpf]\033[0m %s\n' "$*"; }
fail(){ printf '\033[1;31m[honor-hidbpf]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "run as root"

phantom_present() {
    local n
    for n in /sys/class/input/input*/name; do
        [ -e "$n" ] || continue
        case "$(cat "$n" 2>/dev/null)" in *"$HID_ID"*UNKNOWN*) return 0 ;; esac
    done
    return 1
}

touch_alive() {
    local n
    for n in /sys/class/input/input*/name; do
        [ -e "$n" ] || continue
        case "$(cat "$n" 2>/dev/null)" in *"$HID_ID"*) return 0 ;; esac
    done
    return 1
}

apply_live() {
    local dev i
    for dev in /sys/bus/hid/devices/*":$HID_ID."*; do
        [ -e "$dev" ] || continue
        log "applying to ${dev##*/}"
        udev-hid-bpf remove "$dev" >/dev/null 2>&1 || true
        sleep 1
        udev-hid-bpf add "$dev" "$OBJ" >/dev/null 2>&1 || true
    done
    for i in $(seq 10); do
        phantom_present || { log "phantom KEY_MICMUTE device is gone"; return 0; }
        sleep 1
    done
    fail "phantom device still present after re-attach; see docs/touch.md"
}

if [ "${1:-}" != reapply ]; then
    MISSING=()
    for t in curl clang bpftool udev-hid-bpf udevadm; do
        command -v "$t" >/dev/null || MISSING+=("$t")
    done
    if (( ${#MISSING[@]} )); then
        # bpftool ships in the `bpf` package; the tool and package names match otherwise.
        PKGS=()
        for t in "${MISSING[@]}"; do [ "$t" = bpftool ] && PKGS+=(bpf) || PKGS+=("$t"); done
        log "installing build deps: ${PKGS[*]}"
        pacman -S --needed --noconfirm "${PKGS[@]}" >/dev/null || fail "pacman could not install: ${PKGS[*]}"
    fi
    for t in curl clang bpftool udev-hid-bpf udevadm; do
        command -v "$t" >/dev/null || fail "missing tool after install: $t"
    done

    [ -r /sys/kernel/btf/vmlinux ] || fail "/sys/kernel/btf/vmlinux missing (CONFIG_DEBUG_INFO_BTF)"

    KTAG="v$(uname -r | cut -d- -f1 | cut -d. -f1-2)"
    log "kernel $(uname -r), headers $KTAG"
    for h in hid_bpf.h hid_bpf_helpers.h hid_report_descriptor_helpers.h; do
        curl -sfL -o "$WORK/$h" \
            "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/hid/bpf/progs/$h?h=$KTAG" \
            || fail "could not fetch $h for $KTAG"
    done
    bpftool btf dump file /sys/kernel/btf/vmlinux format c > "$WORK/vmlinux.h"

    log "building $OBJ_NAME"
    cp "$SRC" "$WORK/"
    clang -O2 -g -target bpf -mcpu=v3 -D__TARGET_ARCH_x86 \
          -I"$WORK" -Wno-missing-declarations \
          -c "$WORK/honor-ftsc1000-micmute.bpf.c" -o "$WORK/$OBJ_NAME" \
        || fail "build failed"
    udev-hid-bpf inspect "$WORK/$OBJ_NAME" >/dev/null \
        || fail "udev-hid-bpf does not recognise the object"

    log "installing $OBJ"
    udev-hid-bpf install --force "$WORK/$OBJ_NAME" >/dev/null || fail "udev-hid-bpf install failed"
    udevadm control --reload
    systemctl daemon-reload
    systemctl enable "$REAPPLY_SERVICE" >/dev/null 2>&1 \
        || log "could not enable $REAPPLY_SERVICE"
fi

[ -f "$OBJ" ] || fail "$OBJ missing; run without arguments first"

if touch_alive; then
    apply_live
else
    log "no $HID_ID on the bus; the udev rule will attach it"
fi

touch_alive || fail "touchscreen input device did not come back"
log "touchscreen reports normally, phantom device suppressed"