#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

UBUNTU_SUITE=${UBUNTU_SUITE:-jammy}
UBUNTU_MIRROR=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
QEMU_SYSTEM_ARM=${QEMU_SYSTEM_ARM:-qemu-system-arm}
ARM_CLANG=${ARM_CLANG:-clang}
ARM_EXEC_TARGET=${ARM_EXEC_TARGET:-armv7a-linux-gnueabihf}

work=${WORK_DIR:-"$repo_root/build/full-system-arm-red"}
rootfs="$work/rootfs"
disk="$work/ubuntu-armhf.raw"
serial="$work/serial.log"
monitor="${TMPDIR:-/tmp}/idric-arm-red-$$.sock"
screen="$work/red.ppm"
program="$work/linux-fbdev-red.armv7-thumb2"
kernel="$work/vmlinuz"
initrd="$work/initrd.img"
dtb="$work/vexpress-v2p-ca9.dtb"

rm -rf "$work"
mkdir -p "$work"

for command in debootstrap mkfs.ext4 python3 "$QEMU_SYSTEM_ARM" "$ARM_CLANG"; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'FAIL: required command not found: %s\n' "$command" >&2
        exit 1
    }
done
qemu_arm_static=$(command -v qemu-arm-static 2>/dev/null || command -v qemu-armhf-static 2>/dev/null || true)
[ -n "$qemu_arm_static" ] || {
    printf '%s\n' 'FAIL: qemu-arm-static or qemu-armhf-static is required' >&2
    exit 1
}

"$ARM_CLANG" --target="$ARM_EXEC_TARGET" -fuse-ld=lld -nostdlib -static \
    -march=armv7-a -mthumb -Wl,-e,_start -Wl,--no-dynamic-linker \
    "$script_dir/linux_fbdev_red.S" -o "$program"

sudo debootstrap \
    --foreign --arch=armhf --variant=minbase --components=main,universe \
    --include=linux-image-generic,kmod,busybox-static,initramfs-tools \
    "$UBUNTU_SUITE" "$rootfs" "$UBUNTU_MIRROR"
sudo install -m 0755 "$qemu_arm_static" "$rootfs/usr/bin/$(basename "$qemu_arm_static")"
if [ -d /proc/sys/fs/binfmt_misc ]; then
    sudo update-binfmts --enable qemu-arm 2>/dev/null || true
fi
sudo chroot "$rootfs" /debootstrap/debootstrap --second-stage
sudo install -m 0755 "$program" "$rootfs/usr/local/bin/screen-red"

kernel_release=$(sudo sh -c "ls -1 '$rootfs/lib/modules' | sort | tail -n 1")
[ -n "$kernel_release" ] || {
    printf '%s\n' 'FAIL: Ubuntu armhf rootfs has no installed kernel modules' >&2
    exit 1
}
kernel_config="$rootfs/boot/config-$kernel_release"
[ -f "$kernel_config" ] || {
    printf 'FAIL: guest kernel config is missing: %s\n' "$kernel_config" >&2
    exit 1
}

printf '%s\n' 'MODULES=list' | sudo tee "$rootfs/etc/initramfs-tools/conf.d/idric-device-oracle" >/dev/null
modules_file="$rootfs/etc/initramfs-tools/modules"
require_boot_module() {
    module=$1
    config=$2
    if sudo find "$rootfs/lib/modules/$kernel_release" -type f -name "$module.ko*" -print -quit | grep -q .; then
        printf '%s\n' "$module" | sudo tee -a "$modules_file" >/dev/null
    elif sudo grep -q "^$config=y$" "$kernel_config" 2>/dev/null; then
        :
    else
        printf 'FAIL: guest kernel lacks required boot support: %s / %s\n' "$module" "$config" >&2
        exit 1
    fi
}
require_boot_module armmmci CONFIG_MMC_ARMMMCI
require_boot_module mmc_core CONFIG_MMC
require_boot_module mmc_block CONFIG_MMC_BLOCK
require_boot_module ext4 CONFIG_EXT4_FS

require_builtin_config() {
    config=$1
    if ! sudo grep -q "^$config=y$" "$kernel_config"; then
        printf 'FAIL: guest kernel lacks required built-in display support: %s=y\n' "$config" >&2
        exit 1
    fi
    printf 'DISPLAY_CONFIG=%s=y\n' "$config"
}

display_modules="$rootfs/etc/idric-display-modules"
sudo sh -c ": > '$display_modules'"
require_display_component() {
    module=$1
    config=$2
    if sudo grep -q "^$config=y$" "$kernel_config"; then
        printf 'DISPLAY_COMPONENT=%s built-in (%s=y)\n' "$module" "$config"
        return
    fi
    if ! sudo grep -q "^$config=m$" "$kernel_config"; then
        printf 'FAIL: guest kernel lacks required display component: %s / %s\n' "$module" "$config" >&2
        exit 1
    fi
    if ! sudo chroot "$rootfs" /sbin/modinfo -k "$kernel_release" "$module" >/dev/null 2>&1; then
        printf 'FAIL: guest kernel declares %s=m but module %s is unavailable\n' "$config" "$module" >&2
        exit 1
    fi
    printf '%s\n' "$module" | sudo tee -a "$display_modules" >/dev/null
    printf 'DISPLAY_COMPONENT=%s module (%s=m)\n' "$module" "$config"
}

# The custom init below deliberately bypasses systemd/udev. Therefore the
# vexpress display path must be cold-plugged explicitly: QEMU presents the
# Versatile I2C bus and SII9022 bridge in front of the PL111 controller.
require_builtin_config CONFIG_FB
require_builtin_config CONFIG_DRM_FBDEV_EMULATION
require_builtin_config CONFIG_FRAMEBUFFER_CONSOLE
require_display_component i2c_versatile CONFIG_I2C_VERSATILE
require_display_component sii902x CONFIG_DRM_SII902X
require_display_component pl111_drm CONFIG_DRM_PL111

sudo chroot "$rootfs" /usr/sbin/update-initramfs -u -k "$kernel_release"

sudo tee "$rootfs/usr/local/sbin/device-action-init" >/dev/null <<'GUEST_INIT'
#!/bin/busybox sh
exec </dev/console >/dev/console 2>&1
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
/bin/busybox mount -t proc proc /proc 2>/dev/null || true
/bin/busybox mount -t sysfs sysfs /sys 2>/dev/null || true
while IFS= read -r module; do
    [ -n "$module" ] || continue
    echo "DISPLAY_MODULE_LOAD=$module"
    if ! /sbin/modprobe "$module"; then
        echo "DISPLAY_MODULE_STATUS=$module:FAIL"
        echo 'FBDEV_PRESENT=0'
        echo 'PROGRAM_STATUS=124'
        /bin/busybox poweroff -f
        /bin/busybox sleep 5
        exit 124
    fi
    echo "DISPLAY_MODULE_STATUS=$module:OK"
done </etc/idric-display-modules

i=0
while [ ! -c /dev/fb0 ] && [ "$i" -lt 20 ]; do
    /bin/busybox sleep 1
    i=$((i + 1))
done
if [ ! -c /dev/fb0 ]; then
    echo 'FBDEV_PRESENT=0'
    echo '--- /sys/class/drm ---'
    /bin/busybox ls -l /sys/class/drm 2>/dev/null || true
    echo '--- /sys/class/graphics ---'
    /bin/busybox ls -l /sys/class/graphics 2>/dev/null || true
    echo '--- loaded modules ---'
    /bin/busybox cat /proc/modules 2>/dev/null || true
    echo 'PROGRAM_STATUS=125'
    /bin/busybox poweroff -f
    /bin/busybox sleep 5
    exit 125
fi
echo 'FBDEV_PRESENT=1'
echo 'SCREEN_RED_RUNNING=1'
/usr/local/bin/screen-red
status=$?
echo "PROGRAM_STATUS=$status"
/bin/busybox sync
/bin/busybox poweroff -f
/bin/busybox sleep 5
exit "$status"
GUEST_INIT
sudo chmod 0755 "$rootfs/usr/local/sbin/device-action-init"

kernel_source=$(sudo find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort | tail -n 1)
initrd_source=$(sudo find "$rootfs/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort | tail -n 1)
dtb_source=$(sudo find "$rootfs" -type f -name 'vexpress-v2p-ca9.dtb' | sort | head -n 1)
[ -n "$kernel_source" ] && [ -n "$initrd_source" ] && [ -n "$dtb_source" ] || {
    printf '%s\n' 'FAIL: Ubuntu armhf rootfs did not provide kernel/initrd/DTB' >&2
    exit 1
}
sudo cp "$kernel_source" "$kernel"
sudo cp "$initrd_source" "$initrd"
sudo cp "$dtb_source" "$dtb"
sudo chown "$(id -u):$(id -g)" "$kernel" "$initrd" "$dtb"

truncate -s 2G "$disk"
sudo mkfs.ext4 -q -d "$rootfs" "$disk"
sudo chown "$(id -u):$(id -g)" "$disk"
rm -f "$serial" "$monitor" "$screen"

# This lane uses a serial-only custom init. Ubuntu enables deferred fbcon
# takeover, so without nodefer fb0 can exist while the PL111 scanout is
# still unprogrammed. Bind fbcon immediately to commit the real fbdev
# mode before the native oracle writes the framebuffer.
"$QEMU_SYSTEM_ARM" \
    -machine vexpress-a9 -cpu cortex-a9 -m 512M \
    -kernel "$kernel" -dtb "$dtb" -initrd "$initrd" \
    -append 'console=ttyAMA0,115200 root=/dev/mmcblk0 rw rootwait init=/usr/local/sbin/device-action-init panic=-1 fbcon=nodefer' \
    -drive "file=$disk,format=raw,if=sd" \
    -display none -serial "file:$serial" \
    -monitor "unix:$monitor,server=on,wait=off" -no-reboot &
qemu_pid=$!
cleanup_qemu() {
    if kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    rm -f "$monitor"
}
trap cleanup_qemu EXIT HUP INT TERM

i=0
while [ "$i" -lt 180 ]; do
    if [ -f "$serial" ] && grep -q 'SCREEN_RED_RUNNING=1' "$serial"; then break; fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then break; fi
    sleep 1
    i=$((i + 1))
done
if ! [ -f "$serial" ] || ! grep -q 'SCREEN_RED_RUNNING=1' "$serial"; then
    cat "$serial" 2>/dev/null || true
    printf '%s\n' 'FAIL: ARM guest never reached red-screen execution' >&2
    exit 1
fi
sleep 1

python3 - "$monitor" "$screen" <<'PY'
import socket, sys, time
monitor, output = sys.argv[1:]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(50):
    try:
        sock.connect(monitor)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        time.sleep(0.1)
else:
    raise SystemExit("FAIL: QEMU monitor socket was unavailable")
sock.settimeout(2)
try: sock.recv(65536)
except TimeoutError: pass
sock.sendall(("screendump " + output + "\n").encode())
time.sleep(0.5)
try: sock.recv(65536)
except TimeoutError: pass
sock.close()
PY

i=0
while kill -0 "$qemu_pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
cleanup_qemu
trap - EXIT HUP INT TERM
cat "$serial"
grep -q 'FBDEV_PRESENT=1' "$serial"
grep -q 'PROGRAM_STATUS=0' "$serial"

python3 - "$screen" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).read_bytes()
if not p.startswith(b"P6"):
    raise SystemExit("FAIL: QEMU screendump is not binary PPM")
pos = 2
tokens = []
while len(tokens) < 3:
    while p[pos] in b" \t\r\n": pos += 1
    if p[pos] == ord('#'):
        pos = p.index(b"\n", pos) + 1
        continue
    end = pos
    while p[end] not in b" \t\r\n": end += 1
    tokens.append(p[pos:end]); pos = end
w, h, maximum = map(int, tokens)
while p[pos] in b" \t\r\n": pos += 1
pixels = p[pos:]
if maximum != 255 or len(pixels) != w * h * 3:
    raise SystemExit("FAIL: unexpected PPM geometry or sample depth")
red = sum(1 for i in range(0, len(pixels), 3)
          if pixels[i] >= 224 and pixels[i+1] <= 32 and pixels[i+2] <= 32)
ratio = red / (w * h)
print(f"presented_red_pixels={red}/{w*h} ({ratio:.6f})")
if ratio < 0.98:
    raise SystemExit("FAIL: captured ARM guest display is not overwhelmingly red")
PY
printf '%s\n' \
    'PASS: native ARMv7/Thumb-2 ELF executed inside a full-system Ubuntu armhf guest' \
    'PASS: guest used /dev/fb0 and returned status 0' \
    'PASS: QEMU presented-output capture is overwhelmingly red'
