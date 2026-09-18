#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

UBUNTU_SUITE=${UBUNTU_SUITE:-noble}
UBUNTU_MIRROR=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
QEMU_SYSTEM_ARM=${QEMU_SYSTEM_ARM:-qemu-system-arm}
ARM_CC=${ARM_CC:-arm-linux-gnueabihf-gcc}

work=${WORK_DIR:-"$repo_root/build/full-system-arm-gpio"}
rootfs="$work/rootfs"
disk="$work/ubuntu-armhf.raw"
serial="$work/serial.log"
kernel="$work/vmlinuz"
initrd="$work/initrd.img"
dtb="$work/vexpress-v2p-ca15-tc1.dtb"
programs="$work/programs"

rm -rf "$work"
mkdir -p "$work" "$programs"

for command in debootstrap mkfs.ext4 "$QEMU_SYSTEM_ARM" "$ARM_CC"; do
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

for name in gpio_output gpio_input gpio_edge_wait; do
    "$ARM_CC" -std=c11 -Wall -Wextra -Werror -O2 \
        -I"$script_dir" "$script_dir/$name.c" -o "$programs/$name"
done

sudo debootstrap \
    --foreign \
    --arch=armhf \
    --variant=minbase \
    --components=main,universe \
    --include=linux-image-generic,kmod,busybox-static,initramfs-tools \
    "$UBUNTU_SUITE" "$rootfs" "$UBUNTU_MIRROR"

sudo install -m 0755 "$qemu_arm_static" "$rootfs/usr/bin/$(basename "$qemu_arm_static")"
if [ -d /proc/sys/fs/binfmt_misc ]; then
    sudo update-binfmts --enable qemu-arm 2>/dev/null || true
fi
sudo chroot "$rootfs" /debootstrap/debootstrap --second-stage

for name in gpio_output gpio_input gpio_edge_wait; do
    sudo install -m 0755 "$programs/$name" "$rootfs/usr/local/bin/$name"
done

kernel_release=$(sudo sh -c "ls -1 '$rootfs/lib/modules' | sort | tail -n 1")
[ -n "$kernel_release" ] || {
    printf '%s\n' 'FAIL: Ubuntu armhf rootfs has no installed kernel modules' >&2
    exit 1
}

# Keep the off-machine initramfs small and deterministic. Only the modules
# needed to find and mount the PL181/MMC ext4 root belong in the early image.
printf '%s\n' 'MODULES=list' | sudo tee "$rootfs/etc/initramfs-tools/conf.d/idric-device-oracle" >/dev/null
modules_file="$rootfs/etc/initramfs-tools/modules"
require_boot_module() {
    module=$1
    config=$2
    if sudo find "$rootfs/lib/modules/$kernel_release" -type f -name "$module.ko*" -print -quit | grep -q .; then
        printf '%s\n' "$module" | sudo tee -a "$modules_file" >/dev/null
    elif sudo grep -q "^$config=y$" "$rootfs/boot/config-$kernel_release" 2>/dev/null; then
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
sudo chroot "$rootfs" /usr/sbin/update-initramfs -u -k "$kernel_release"

sudo tee "$rootfs/usr/local/sbin/device-action-init" >/dev/null <<'GUEST_INIT'
#!/bin/busybox sh
set -eu

exec </dev/console >/dev/console 2>&1

/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
/bin/busybox mount -t proc proc /proc 2>/dev/null || true
/bin/busybox mount -t sysfs sysfs /sys 2>/dev/null || true
mkdir -p /sys/kernel/config
/bin/busybox mount -t configfs configfs /sys/kernel/config 2>/dev/null || true

/sbin/modprobe gpio-sim

config=/sys/kernel/config/gpio-sim/idric-device
bank="$config/gpio-bank0"
line="$bank/line0"
mkdir -p "$line"
echo 1 > "$bank/num_lines"
echo idric-gpio-line-0 > "$line/name"
echo 1 > "$config/live"

chip_name=$(cat "$bank/chip_name")
dev_name=$(cat "$config/dev_name")
chip="/dev/$chip_name"
line_state=$(find "/sys/devices/platform/$dev_name" -type d -name sim_gpio0 | head -n 1)

[ -c "$chip" ] || {
    echo "GPIO_CHIP_MISSING=$chip"
    exit 120
}
[ -n "$line_state" ] || {
    echo 'GPIO_SIM_LINE_STATE_MISSING=1'
    exit 121
}

echo "GPIO_CHIP=$chip"
echo "GPIO_SIM_DEVICE=$dev_name"

output_log=/tmp/gpio-output.log
/usr/local/bin/gpio_output "$chip" 0 >"$output_log" &
output_pid=$!
i=0
while ! grep -q '^HIGH$' "$output_log" 2>/dev/null && [ "$i" -lt 50 ]; do
    /bin/busybox sleep 0.02
    i=$((i + 1))
done
high=$(cat "$line_state/value")
i=0
while ! grep -q '^LOW$' "$output_log" 2>/dev/null && [ "$i" -lt 100 ]; do
    /bin/busybox sleep 0.02
    i=$((i + 1))
done
low=$(cat "$line_state/value")
wait "$output_pid"
cat "$output_log"
echo "GPIO_OUTPUT_OBSERVED=$high,$low"
[ "$high" = 1 ] && [ "$low" = 0 ]

echo pull-down > "$line_state/pull"
input_low=$(/usr/local/bin/gpio_input "$chip" 0)
echo pull-up > "$line_state/pull"
input_high=$(/usr/local/bin/gpio_input "$chip" 0)
echo "GPIO_INPUT_OBSERVED=$input_low,$input_high"
[ "$input_low" = 0 ] && [ "$input_high" = 1 ]

echo pull-down > "$line_state/pull"
edge_log=/tmp/gpio-edge.log
/usr/local/bin/gpio_edge_wait "$chip" 0 >"$edge_log" &
edge_pid=$!
i=0
while ! grep -q '^armed offset=0$' "$edge_log" 2>/dev/null && [ "$i" -lt 100 ]; do
    /bin/busybox sleep 0.02
    i=$((i + 1))
done
if ! grep -q '^armed offset=0$' "$edge_log"; then
    if kill -0 "$edge_pid" 2>/dev/null; then
        echo 'GPIO_EDGE_ARM_TIMEOUT=1'
        printf 'GPIO_EDGE_WCHAN='
        cat "/proc/$edge_pid/wchan" 2>/dev/null || true
        kill -9 "$edge_pid" 2>/dev/null || true
    else
        set +e
        wait "$edge_pid"
        edge_status=$?
        set -e
        echo "GPIO_EDGE_ARM_STATUS=$edge_status"
    fi
    /bin/busybox poweroff -f
    /bin/busybox sleep 5
    exit 122
fi
echo pull-up > "$line_state/pull"
wait "$edge_pid"
cat "$edge_log"
grep -q '^rising offset=0 ' "$edge_log"
echo 'GPIO_EDGE_OBSERVED=rising'

echo 'GPIO_TESTS_PASS=1'
/bin/busybox sync
/bin/busybox poweroff -f
/bin/busybox sleep 5
GUEST_INIT
sudo chmod 0755 "$rootfs/usr/local/sbin/device-action-init"

kernel_source=$(sudo find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort | tail -n 1)
initrd_source=$(sudo find "$rootfs/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort | tail -n 1)
dtb_source=$(sudo find "$rootfs" -type f -name 'vexpress-v2p-ca15-tc1.dtb' | sort | head -n 1)
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
rm -f "$serial"

"$QEMU_SYSTEM_ARM" \
    -machine vexpress-a15 \
    -cpu cortex-a15 \
    -smp 2 \
    -m 512M \
    -kernel "$kernel" \
    -dtb "$dtb" \
    -initrd "$initrd" \
    -append 'console=ttyAMA0,115200 root=/dev/mmcblk0 rw rootwait init=/usr/local/sbin/device-action-init panic=-1' \
    -drive "file=$disk,format=raw,if=sd" \
    -display none \
    -serial "file:$serial" \
    -no-reboot &
qemu_pid=$!

cleanup_qemu() {
    if kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
}
trap cleanup_qemu EXIT HUP INT TERM

i=0
while [ "$i" -lt 240 ]; do
    if [ -f "$serial" ] && grep -q 'GPIO_TESTS_PASS=1' "$serial"; then
        break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

cleanup_qemu
trap - EXIT HUP INT TERM
cat "$serial" 2>/dev/null || true
grep -q 'GPIO_TESTS_PASS=1' "$serial"

echo 'PASS: ARMv7 Ubuntu guest exercised gpio_output, gpio_input, and gpio_edge_wait through gpio-sim'
