"""linux-headers: the package licence is computed from the headers it installs.

The licence opinion (dictamen-licencias-paquetes-distro-sond.md, section 2.11 and rule 9 of
section 3.1) fixes three choices: every GPL tag becomes GPL-2.0-only (the "or later" lets the
COPYING's version be chosen), every OR takes its GPL branch, and every LGPL tag becomes
LGPL-2.1-only. A header with no SPDX tag must be in UNLABELLED, the reviewed table of the 87 of
kernel 6.12.77: "copying" ones fall under the kernel COPYING (GPL-2.0 WITH Linux-syscall-note);
"permissive" ones carry their whole notice inside and add no identifier. A new unlabelled
header is refused until it is reviewed.
"""

import os
import re

from sondpkg import spdx
from sondpkg.errors import PackagerError

NOTE = "Linux-syscall-note"
_GPL = {"GPL-2.0", "GPL-2.0+", "GPL-2.0-only", "GPL-2.0-or-later", "GPL-1.0+", "GPL-1.0-or-later"}
_LGPL = {"LGPL-2.0+", "LGPL-2.0-or-later", "LGPL-2.1", "LGPL-2.1+", "LGPL-2.1-only", "LGPL-2.1-or-later"}
_ORDER = ("GPL-2.0-only WITH " + NOTE, "LGPL-2.1-only WITH " + NOTE, "MIT", "BSD-3-Clause")
_TAG = re.compile(rb"SPDX-License-Identifier:[ \t]*([^\n]*?)[ \t]*(?:\*/)?[ \t]*\r?$", re.M)

UNLABELLED = {
    # under the kernel COPYING: no notice, a GPL/LGPL text, or GPL among alternatives
    "asm-generic/auxvec.h": "copying",
    "asm-generic/bpf_perf_event.h": "copying",
    "asm-generic/hugetlb_encode.h": "copying",
    "asm-generic/kvm_para.h": "copying",
    "asm/bpf_perf_event.h": "copying",
    "asm/errno.h": "copying",
    "asm/fcntl.h": "copying",
    "asm/ioctl.h": "copying",
    "asm/ioctls.h": "copying",
    "asm/ipcbuf.h": "copying",
    "asm/param.h": "copying",
    "asm/poll.h": "copying",
    "asm/resource.h": "copying",
    "asm/setup.h": "copying",
    "asm/socket.h": "copying",
    "asm/sockios.h": "copying",
    "asm/termbits.h": "copying",
    "asm/termios.h": "copying",
    "asm/types.h": "copying",
    "asm/unistd_32.h": "copying",
    "asm/unistd_64.h": "copying",
    "asm/unistd_x32.h": "copying",
    "linux/aio_abi.h": "copying",
    "linux/coda.h": "copying",
    "linux/errno.h": "copying",
    "linux/if_ppp.h": "copying",
    "linux/irqnr.h": "copying",
    "linux/jffs2.h": "copying",
    "linux/mount.h": "copying",
    "linux/ncsi.h": "copying",
    "linux/ndctl.h": "copying",
    "linux/netfilter/nfnetlink_osf.h": "copying",
    "linux/parport.h": "copying",
    "linux/poll.h": "copying",
    "linux/seg6_local.h": "copying",
    "linux/usb/charger.h": "copying",
    "linux/uuid.h": "copying",
    "linux/version.h": "copying",
    "linux/virtio_rng.h": "copying",
    "rdma/ib_user_ioctl_cmds.h": "copying",
    "rdma/mlx5_user_ioctl_cmds.h": "copying",
    "rdma/mlx5_user_ioctl_verbs.h": "copying",
    "rdma/rdma_user_ioctl_cmds.h": "copying",
    "xen/gntalloc.h": "copying",
    # permissive only, with its full notice inside the file
    "drm/amdgpu_drm.h": "permissive",
    "drm/drm.h": "permissive",
    "drm/drm_fourcc.h": "permissive",
    "drm/drm_mode.h": "permissive",
    "drm/drm_sarea.h": "permissive",
    "drm/i915_drm.h": "permissive",
    "drm/msm_drm.h": "permissive",
    "drm/nouveau_drm.h": "permissive",
    "drm/qxl_drm.h": "permissive",
    "drm/radeon_drm.h": "permissive",
    "drm/v3d_drm.h": "permissive",
    "drm/vc4_drm.h": "permissive",
    "drm/vgem_drm.h": "permissive",
    "drm/virtgpu_drm.h": "permissive",
    "linux/agpgart.h": "permissive",
    "linux/firewire-cdev.h": "permissive",
    "linux/firewire-constants.h": "permissive",
    "linux/kfd_ioctl.h": "permissive",
    "linux/membarrier.h": "permissive",
    "linux/nfc.h": "permissive",
    "linux/nfs_idmap.h": "permissive",
    "linux/nl80211.h": "permissive",
    "linux/quota.h": "permissive",
    "linux/rfkill.h": "permissive",
    "linux/soundcard.h": "permissive",
    "linux/tee.h": "permissive",
    "linux/timex.h": "permissive",
    "linux/virtio_9p.h": "permissive",
    "linux/virtio_balloon.h": "permissive",
    "linux/virtio_blk.h": "permissive",
    "linux/virtio_config.h": "permissive",
    "linux/virtio_console.h": "permissive",
    "linux/virtio_crypto.h": "permissive",
    "linux/virtio_gpu.h": "permissive",
    "linux/virtio_ids.h": "permissive",
    "linux/virtio_input.h": "permissive",
    "linux/virtio_mmio.h": "permissive",
    "linux/virtio_net.h": "permissive",
    "linux/virtio_pci.h": "permissive",
    "linux/virtio_ring.h": "permissive",
    "linux/virtio_scsi.h": "permissive",
    "linux/virtio_types.h": "permissive",
    "linux/virtio_vsock.h": "permissive",
}


def _normalise(atom):
    if atom in _GPL:
        return "GPL-2.0-only"
    if atom in _LGPL:
        return "LGPL-2.1-only"
    return atom


def _parse(text):
    """Return the expression as a tree: ("atom", name, exception) | (op, [children])."""
    tokens = spdx._tokens(text)
    pos = 0

    def operand():
        nonlocal pos
        if pos >= len(tokens):
            raise PackagerError('malformed SPDX expression "%s"' % text)
        token = tokens[pos]
        if token == "(":
            pos += 1
            node = disjunction()
            if pos >= len(tokens) or tokens[pos] != ")":
                raise PackagerError('malformed SPDX expression "%s"' % text)
            pos += 1
            return node
        pos += 1
        exception = None
        if pos < len(tokens) and tokens[pos] == "WITH":
            exception = tokens[pos + 1] if pos + 1 < len(tokens) else None
            pos += 2
        return ("atom", token, exception)

    def chain(op, inner):
        nonlocal pos
        nodes = [inner()]
        while pos < len(tokens) and tokens[pos] == op:
            pos += 1
            nodes.append(inner())
        return nodes[0] if len(nodes) == 1 else (op, nodes)

    def conjunction():
        return chain("AND", operand)

    def disjunction():
        return chain("OR", conjunction)

    spdx.atoms(text)  # validates the grammar
    return disjunction()


def _is_gpl(node):
    if node[0] == "atom":
        return _normalise(node[1]) in ("GPL-2.0-only", "LGPL-2.1-only")
    return any(_is_gpl(child) for child in node[1])


def _terms(node):
    if node[0] == "atom":
        atom = _normalise(node[1])
        return {atom + (" WITH " + node[2] if node[2] else "")}
    if node[0] == "OR":
        gpl = [child for child in node[1] if _is_gpl(child)]
        return _terms(gpl[0] if gpl else node[1][0])
    terms = set()
    for child in node[1]:
        terms |= _terms(child)
    return terms


def _has_note(node):
    if node[0] == "atom":
        return node[2] == NOTE
    return any(_has_note(child) for child in node[1])


def _tag_of(path, relative):
    with open(path, "rb") as handle:
        match = _TAG.search(handle.read())
    if match is None:
        kind = UNLABELLED.get(relative)
        if kind is None:
            raise PackagerError(
                "header %s has no SPDX tag and is not in the reviewed table" % relative
            )
        return None, kind
    return _parse(match.group(1).decode("ascii", "replace")), None


def notices_needed(include, used):
    """Of the headers ``used`` (paths relative to ``include``), those whose notice the binary
    must carry: no branch WITH Linux-syscall-note and not under the kernel COPYING (rule 10)."""
    needed = []
    for relative in sorted(set(used)):
        tree, kind = _tag_of(os.path.join(include, *relative.split("/")), relative)
        if tree is None:
            if kind == "permissive":
                needed.append(relative)
        elif not _has_note(tree):
            needed.append(relative)
    return needed


def computed_license(include):
    """The SPDX expression the opinion's choices give for every header under ``include``."""
    terms = set()
    for directory, _, files in os.walk(include):
        for filename in files:
            path = os.path.join(directory, filename)
            relative = os.path.relpath(path, include).replace(os.sep, "/")
            tree, kind = _tag_of(path, relative)
            if tree is None:
                if kind == "copying":
                    terms.add("GPL-2.0-only WITH " + NOTE)
                continue
            terms |= _terms(tree)
    ordered = [t for t in _ORDER if t in terms] + sorted(terms - set(_ORDER))
    expression = " AND ".join(ordered)
    spdx.check_license(expression)
    return expression
