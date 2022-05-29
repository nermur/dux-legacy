#!/bin/bash
# shellcheck disable=SC2162
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)

source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

if ! grep -q "'archiso'" /etc/mkinitcpio.d/linux.preset; then
	echo -e "\nERROR: Do not run this script outside of the Arch Linux ISO!\n"
	exit 1
fi
if cryptsetup status "lukspart" | grep -q "inactive"; then
	echo -e "\nERROR: Forgot to mount the LUKS2 partition as 'lukspart'?\n"
	exit 1
fi

[[ -z ${BOOT_PART:-} ]] &&
	BOOT_PART=$(blkid | sed -n '/BOOTEFI/p' | cut -f1 -d' ' | tr -d :) && export BOOT_PART

LUKS_PART="/dev/mapper/lukspart"
SUBVOL_LIST=(root btrfs srv snapshots pkg log home)

_make_dirs() {
	mkdir "${mkdir_flags}" /mnt/{boot,btrfs,var/{log,cache/pacman/pkg},srv,.snapshots,root,home}
}

# If the Btrfs filesystem doesn't exist on the partition containing "lukspart", create it.
if ! lsblk -fl | grep --line-buffered "lukspart" | grep -q "btrfs"; then
	umount -flRq /mnt || :
	mkfs.btrfs "${LUKS_PART}"
	mount -t btrfs "${LUKS_PART}" /mnt

	_make_dirs
	mount -t vfat -o nodev,nosuid,noexec "${BOOT_PART}" /mnt/boot

	_make_subvolumes() {
		for subvols in "${SUBVOL_LIST[@]}"; do
			btrfs subvolume create /mnt/@"${subvols}"
		done
	}
	_make_subvolumes
fi

_mount_partitions() {
	umount -flRq /mnt || :

	# Why 'noatime': https://archive.is/wjH73
	local OPTS="noatime,compress=zstd:1"

	mount -t btrfs -o "${OPTS}",subvol=@root "${LUKS_PART}" /mnt &&
		_make_dirs # Incase one of these directories was removed.

	mount -t vfat -o nodev,nosuid,noexec "${BOOT_PART}" /mnt/boot

	mount -t btrfs -o "${OPTS}",subvolid=5 "${LUKS_PART}" /mnt/btrfs
	mount -t btrfs -o "${OPTS}",subvol=@srv "${LUKS_PART}" /mnt/srv
	mount -t btrfs -o "${OPTS}",subvol=@snapshots "${LUKS_PART}" /mnt/.snapshots
	mount -t btrfs -o "${OPTS}",subvol=@pkg "${LUKS_PART}" /mnt/var/cache/pacman/pkg
	mount -t btrfs -o "${OPTS}",subvol=@log "${LUKS_PART}" /mnt/var/log
	mount -t btrfs -o "${OPTS}",subvol=@home "${LUKS_PART}" /mnt/home
}
_mount_partitions

if [[ ${DEBUG} -ne 1 ]]; then
	echo -e "\nTesting up to the 12 best mirrors for your selected countries, please wait...\n"
	# Use likely fastest mirrors in user selected region(s), or the user's own selected country list.
	# shellcheck disable=SC2086
	reflector -c "${reflector_countrylist}" -p https --delay 1 --score 12 --fastest 6 --save /etc/pacman.d/mirrorlist >&/dev/null
fi

# Fixes an edge case stemming from Pacman suddenly exiting (due to the user pressing Ctrl + C, which sends SIGINT).
rm -f /mnt/var/lib/pacman/db.lck

# Keep packages here to a minimum; packages are to be installed later if possible.
pacstrap /mnt cryptsetup dosfstools btrfs-progs base base-devel git \
	zsh grml-zsh-config --quiet --noconfirm --ask=4 --needed

# GnuPG can't use systemd-resolved's selected "nameserver"(s) without this symlink; prevents installation issues.
ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

cat <<'EOF' >/mnt/etc/fstab
# Static information about the filesystems.
# See fstab(5) for details.

# <file system> <dir> <type> <options> <dump> <pass>
EOF
genfstab -U /mnt >>/mnt/etc/fstab

echo -e "# Some useful configuration is gone if this isn't mounted\ndebugfs    /sys/kernel/debug      debugfs  defaults  0 0" >>/mnt/etc/fstab

sed -i -e 's/^#Color/Color/' \
	-e '/^#ParallelDownloads/s/^#//' /mnt/etc/pacman.conf
