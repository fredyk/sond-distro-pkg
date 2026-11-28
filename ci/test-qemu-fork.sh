#!/bin/bash
# Shape checks for the qemu and edk2-ovmf fork recipes: what incus 7.6 needs to start a q35 UEFI
# VM. qemu-system-x86_64 and qemu-img, static against musl, x86_64 KVM only, without spice
# (incus 7.6 probes query-spice and leaves the spice sections out when qemu lacks it) and the
# source lane; OVMF under the names
# internal/server/instance/drivers/edk2/driver_edk2.go searches in /usr/share/OVMF.
# Offline: no network, no build.
#
# usage: ci/test-qemu-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
has() { grep -qE -- "$2" "$1" && ok "$3" || bad "$3"; }

# Read on 2026-11-26 with git ls-remote: qemu v11.1.3 and edk2-stable202608 (peeled commits).
QEMU_UPSTREAM=github.com/qemu/qemu@005c61c0ef6f6ae615283440b4bb7be51b2c6ddd
EDK2_UPSTREAM=github.com/tianocore/edk2@2970e5699ba6267f3384ffab20f96647578aebc8

base_log=$(mktemp)
exit() {
	[ "${_sourcing:-}" = 1 ] || builtin exit "${1:-0}"
}
_sourcing=1
# shellcheck source=/dev/null
source "$here/test-fork-workflows.sh" >"$base_log" 2>&1 || true
unset _sourcing
check qemu qemu 11.1.3 "$QEMU_UPSTREAM" copyleft
check edk2-ovmf edk2-ovmf 2026.08 "$EDK2_UPSTREAM"

q=$here/forks/qemu-sond.yml
if [ -f "$q" ]; then
	has "$q" '^          license: GPL-2.0-only AND LGPL-2.1-or-later AND MIT AND BSD-3-Clause$' "qemu: licence"
	has "$q" '--static' "qemu: configured --static"
	has "$q" '--target-list=x86_64-softmmu ' "qemu: one target, x86_64-softmmu"
	has "$q" '--enable-kvm --disable-tcg' "qemu: KVM only"
	has "$q" '--disable-slirp' "qemu: no slirp"
	has "$q" '--disable-spice' "qemu: configured --disable-spice"
	grep -qE -- '--enable-spice' "$q" && bad "qemu: never --enable-spice" || ok "qemu: never --enable-spice"
	deps=$(awk '/^          depends: \|$/{f=1; next} f && /^          [a-z-]+:/{f=0} f' "$q")
	printf '%s\n' "$deps" | grep -qiE 'spice' && bad "qemu: no spice in depends" || ok "qemu: no spice in depends"
	grep -q 'vgabios-qxl.bin' "$q" && bad "qemu: no qxl VGA ROM (qxl is spice-only)" || ok "qemu: no qxl VGA ROM (qxl is spice-only)"
	for d in glib pixman zlib; do
		printf '%s\n' "$deps" | grep -qE "^ +$d " && ok "qemu: depends on $d" || bad "qemu: depends on $d"
	done
	# The pins of the sibling fork packages, no placeholders (TODO) allowed: linux-headers comes
	# from toolchain/common.sh; glib 2.86.5, pcre2 10.49, pixman 0.46.4 and zlib 1.3.2 from the
	# versions the sibling recipes publish. pkg-config --static of glib-2.0.pc pulls
	# -lpcre2-8 through Requires.private (all the meson, prefer_static: the qemu's configure
	# adds -Dprefer_static=true for --static), so pcre2 must be in the sysroot.
	for p in 'linux-headers 6\.12\.77' 'glib 2\.86\.5' 'pcre2 10\.49' 'pixman 0\.46\.4' 'zlib 1\.3\.2'; do
		printf '%s\n' "$deps" | grep -qE "^ +$p$" && ok "qemu: depends $p" || bad "qemu: depends $p"
	done
	grep -q 'TODO' "$q" && bad "qemu: no TODO pin left in the recipe" || ok "qemu: no TODO pin left in the recipe"
	has "$q" 'install -D -m 0755 build/qemu-system-x86_64 "\$SOND_PAYLOAD/bin/qemu-system-x86_64"' "qemu: ships bin/qemu-system-x86_64"
	has "$q" 'install -D -m 0755 build/qemu-img "\$SOND_PAYLOAD/bin/qemu-img"' "qemu: ships bin/qemu-img"
	has "$q" 'bios-256k.bin' "qemu: ships bios-256k.bin (security.csm VMs)"
	# incus 7.6 looks for the CSM firmware as /usr/share/seabios/bios-256k.bin.
	has "$q" '"\$SOND_PAYLOAD/share/seabios/bios-256k.bin"' "qemu: ships share/seabios/bios-256k.bin where incus searches for CSM"
	has "$q" 'efi-virtio.rom' "qemu: ships the virtio option ROM"
	has "$q" 'keymaps/en-us' "qemu: ships the en-us keymap"
	has "$q" 'COPYING.LIB=share/licenses/qemu/LGPL-2.1' "qemu: ships the LGPL-2.1 text"
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "GPL-2.0-only AND LGPL-2.1-or-later AND MIT AND BSD-3-Clause" >/dev/null || rc=$?
	[ "$rc" = 0 ] && ok "qemu: the source lane publishes first" || bad "qemu: the source lane publishes first (rc=$rc)"
else
	bad "qemu-sond.yml: present"
fi

e=$here/forks/edk2-ovmf-sond.yml
if [ -f "$e" ]; then
	has "$e" '^          license: BSD-2-Clause-Patent$' "edk2-ovmf: licence BSD-2-Clause-Patent"
	has "$e" 'License.txt=share/licenses/edk2-ovmf/COPYING' "edk2-ovmf: ships License.txt"
	has "$e" 'OvmfPkg/OvmfPkgX64.dsc' "edk2-ovmf: builds OvmfPkgX64"
	has "$e" 'FD_SIZE_4MB' "edk2-ovmf: 4 MiB flash layout"
	has "$e" 'submodules: recursive' "edk2-ovmf: checks out edk2's submodules (openssl, Brotli, ...)"
	# The pairs incus 7.6 tries in /usr/share/OVMF, GENERIC and SECUREBOOT (driver_edk2.go).
	# OVMF_CODE_4M.ms.fd/OVMF_VARS_4M.ms.fd: the SECUREBOOT pair incus picked on Roubaix (Ubuntu
	# package ovmf has no OVMF_VARS.4MB.ms.fd, so the second entry wins) for every VM created with
	# the default security.secureboot=true. A replica's qemu.nvram links to OVMF_VARS_4M.ms.fd, and
	# incus starts it only with the pair whose Vars has that name.
	for f in OVMF_CODE_4M.fd OVMF_VARS_4M.fd OVMF_CODE_4M.secboot.fd OVMF_VARS_4M.secboot.fd OVMF_CODE_4M.ms.fd OVMF_VARS_4M.ms.fd; do
		has "$e" "\\\$SOND_PAYLOAD/share/OVMF/$f\"" "edk2-ovmf: ships share/OVMF/$f"
	done
	has "$e" 'virt-fw-vars .*--enroll-redhat' "edk2-ovmf: the .ms Vars template carries the Microsoft UEFI CA and KEK"
	has "$e" 'virt-fw-vars .*--secure-boot' "edk2-ovmf: the .ms Vars template boots with secure boot on"
	grep -q 'source-bundle' "$e" && bad "edk2-ovmf: permissive, no source lane" || ok "edk2-ovmf: permissive, no source lane"
	rc=0
	python3 - "$DISTRO" <<'PY' || rc=$?
import sys
sys.path.insert(0, sys.argv[1])
from sondpkg import spdx
spdx.check_license("BSD-2-Clause-Patent")
PY
	[ "$rc" = 0 ] && ok "sondpkg admits BSD-2-Clause-Patent" || bad "sondpkg admits BSD-2-Clause-Patent"
else
	bad "edk2-ovmf-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-qemu-fork: OK\n'
else
	printf 'test-qemu-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
