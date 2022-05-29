#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

TOTAL_RAM=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))
CPU_VENDOR=$(grep -m1 'vendor' /proc/cpuinfo | cut -f2 -d' ')
# Also covers GCC's -mtune
MARCH=$(gcc -march=native -Q --help=target | grep -oP '(?<=-march=).*' -m1 | awk '{$1=$1};1')
# Caches result of 'nproc'
NPROC=$(nproc)

if [[ ${support_hibernation} -eq 1 ]]; then
	truncate -s 0 /swapfile
	chattr +C /swapfile
	fallocate -l $((TOTAL_RAM / 2))MiB /swapfile
	chmod 0600 /swapfile
	mkswap /swapfile
	swapon /swapfile
fi

_preparation() {
	pacman -Sy --noconfirm --ask=4 archlinux-keyring && pacman -Su --noconfirm --ask=4

	sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
	locale-gen

	local TZ
	TZ=$(curl -s http://ip-api.com/line?fields=timezone)
	systemd-firstboot --keymap="${system_keymap}" --timezone="${TZ}" --locale="en_US.UTF-8" --hostname="${system_hostname}" --setup-machine-id --force || :
	# Use the new locale.conf now to stop 'perl' from complaining about a broken locale.
	unset LANG
	source /etc/profile.d/locale.sh
}
_preparation

_userinfo() {
	if [[ ! -s "/etc/hostname" ]]; then
		cat <<EOF >/etc/hosts
127.0.0.1        localhost
::1              ip6-localhost
127.0.1.1        ${system_hostname}        ${system_hostname}
EOF
	fi

	# Safe to do; if say /home/admin existed, it wouldn't also remove /home/admin.
	if id -u "${WHICH_USER}" >/dev/null 2>&1; then
		userdel "${WHICH_USER}"
	fi

	# gamemode: Allows for maximum performance while a specific program is running.
	groupadd --force -g 385 gamemode

	# Why 'video': https://github.com/Hummer12007/brightnessctl/issues/63
	useradd -m -G users,wheel,video,gamemode -s /bin/zsh "${WHICH_USER}" &&
		echo "${WHICH_USER}:${PWCODE}" | chpasswd
	unset PWCODE

	# sudo: Allow users in group 'wheel' to elevate to superuser without prompting for a password (until 04-finalize.sh).
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/custom_settings

	# Ensure these directories exist.
	mv -f "/home/${WHICH_USER}/dux" "/home/${WHICH_USER}/dux_backup_${DATE}" || :
	cp -f -R "${GIT_DIR}" "/home/${WHICH_USER}/dux"

	BACKUPS="/home/${WHICH_USER}/dux_backups" && export BACKUPS

	mkdir "${mkdir_flags}" {/etc/{modules-load.d,modprobe.d,pacman.d/hooks,X11,fonts,systemd/user,snapper/configs,conf.d},/boot,/home/"${WHICH_USER}"/.config/{fontconfig/conf.d,systemd/user},/usr/share/libalpm/scripts}
}
_userinfo

# Ensure multi-threading across all PKGBUILDs to drastically lower compilation times.
sed -i -e "s/-march=x86-64 -mtune=generic/-march=${MARCH} -mtune=${MARCH}/" \
	-e 's/.RUSTFLAGS.*/RUSTFLAGS="-C opt-level=2 -C target-cpu=native"/' \
	-e "s/.MAKEFLAGS.*/MAKEFLAGS=\"-j${NPROC} -l${NPROC}\"/" \
	-e "s/xz -c -z -/xz -c -z -T ${NPROC} -/" \
	-e "s/bzip2 -c -f/pbzip2 -c -f/" \
	-e "s/gzip -c -f -n/pigz -c -f -n/" \
	-e "s/zstd -c -z -q -/zstd -c -z -q -T${NPROC} -/" \
	-e "s/lrzip -q/lrzip -q -p ${NPROC}/" /etc/makepkg.conf

sed -i "s/.DefaultEnvironment.*/DefaultEnvironment=\"GNUMAKEFLAGS=-j${NPROC} -l${NPROC}\" \"MAKEFLAGS=-j${NPROC} -l${NPROC}\"/" \
	/etc/systemd/{system.conf,user.conf}

sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

_hardware() {
	if [[ ${hardware_wifi_and_bluetooth} -eq 1 ]]; then
		PKGS+="iwd bluez bluez-utils "
		SERVICES+="iwd.service bluetooth.service "
	fi

	[[ ${hardware_mobile_broadband} -eq 1 ]] &&
		PKGS+="modemmanager mobile-broadband-provider-info usb_modeswitch wvdial "

	if [[ ${hardware_dsl_pppoe} -eq 1 ]]; then
		PKGS+="rp-pppoe wvdial "
		groupadd --force -g 20 dialout
		gpasswd -a "${WHICH_USER}" dialout
	fi

	[[ ${hardware_nonwacom_drawing_tablet} -eq 1 ]] &&
		PKGS_AUR+="digimend-drivers-git-dkms uclogic-tools " && export PKGS_AUR

	if [[ ${hardware_printers_and_scanners} -eq 1 ]]; then
		# Also requires nss-mdns; installed by default.
		PKGS+="cups cups-filters ghostscript gsfonts cups-pk-helper sane system-config-printer simple-scan "
		# Also requires avahi-daemon.service; enabled by default.
		SERVICES+="cups.socket cups-browsed.service "
		_printer_config() {
			chattr -f -i /etc/nsswitch.conf
			sed -i "s/hosts:.*/hosts: files mymachines myhostname mdns_minimal [NOTFOUND=return] resolve/" /etc/nsswitch.conf
			chattr -f +i /etc/nsswitch.conf
		}
		trap _printer_config EXIT
	fi
}
_hardware

# Root-less Xorg to lower its memory usage and increase overall security.
_move2bkup "/etc/X11/Xwrapper.config" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/X11/Xwrapper.config "/etc/X11/"

if ! grep -q 'PRUNENAMES = ".snapshots"' /etc/updatedb.conf; then
	# Tells mlocate to ignore Snapper's Btrfs snapshots; avoids slowdowns and excessive memory usage.
	printf 'PRUNENAMES = ".snapshots"' >>/etc/updatedb.conf
fi

# Default graphical packages, regardless of options selected.
PKGS+="noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-hack ttf-liberation ttf-carlito ttf-caladea \
	dconf-editor gnome-logs konsole \
	flatpak gsettings-desktop-schemas xdg-desktop-portal xdg-desktop-portal-gtk ibus \
	ark dolphin kde-cli-tools kdegraphics-thumbnailers kimageformats qt5-imageformats ffmpegthumbs taglib openexr libjxl "

# Default packages, regardless of options selected.
PKGS+="irqbalance zram-generator power-profiles-daemon thermald dbus-broker gamemode lib32-gamemode iptables-nft libnewt pigz pbzip2 \
strace usbutils linux-firmware gnome-keyring avahi nss-mdns \
man-db man-pages pacman-contrib snapper snap-pac mkinitcpio linux-zen linux-zen-headers bat \
wget trash-cli reflector rebuild-detector vim "

[[ ${bootloader_type} -eq 1 ]] &&
	PKGS+="grub os-prober "
[[ ${bootloader_type} -eq 2 ]] &&
	PKGS+="refind "
[[ ${include_kernel_lts} -eq 1 ]] &&
	PKGS+="linux-lts linux-lts-headers "
[[ -d "/sys/firmware/efi" ]] &&
	PKGS+="efibootmgr "

case $(systemd-detect-virt) in
"none")
	if [[ ${CPU_VENDOR} = "AuthenticAMD" ]]; then
		PKGS+="amd-ucode "
	elif [[ ${CPU_VENDOR} = "GenuineIntel" ]]; then
		PKGS+="intel-ucode "
	fi
	;;
"kvm")
	PKGS+="qemu-guest-agent "
	;;
"vmware")
	PKGS+="open-vm-tools "
	SERVICES+="vmtoolsd.service vmware-vmblock-fuse.service "
	;;
"oracle")
	PKGS+="virtualbox-guest-utils "
	SERVICES+="vboxservice.service "
	;;
"microsoft")
	PKGS+="hyperv "
	SERVICES+="hv_fcopy_daemon.service hv_kvp_daemon.service hv_vss_daemon.service "
	;;
*)
	printf "\nWARNING: 'systemd-detect-virt' did not return an expected string.\n"
	;;
esac

# -Syuu (double -u) to start using the multilib repo now.
# shellcheck disable=SC2086
pacman -Syuu --quiet --noconfirm --ask=4 --needed ${PKGS}

_move2bkup "/etc/mkinitcpio.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/mkinitcpio.conf "/etc/"

# This'll prevent many unnecessary initramfs generations, speeding up the install process drastically.
ln -sf /dev/null /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
ln -sf /dev/null /usr/share/libalpm/hooks/90-mkinitcpio-install.hook

# Default services, regardless of options selected.
SERVICES+="fstrim.timer reflector.timer irqbalance.service systemd-oomd.service dbus-broker.service systemd-timesyncd.service power-profiles-daemon.service thermald.service systemd-resolved.service rfkill-unblock@all avahi-daemon.service "

# shellcheck disable=SC2086
_systemctl enable ${SERVICES}

[[ ${disks_lvm2} -eq 0 ]] &&
	systemctl mask lvm2-lvmpolld.socket lvm2-monitor.service

[[ ! -d "/sys/firmware/efi" ]] &&
	declare -r bootloader_type="1" && export bootloader_type

COMMON_PARAMS="loglevel=3 sysrq_always_enabled=1 quiet add_efi_memmap acpi_osi=Linux nmi_watchdog=0 skew_tick=1 mce=ignore_ce nosoftlockup"
LUKS_UUID=$(blkid | sed -n '/crypto_LUKS/p' | cut -f2 -d' ' | cut -d '=' -f2 | sed 's/\"//g')
if [[ ${bootloader_type} -eq 1 ]]; then
	_setup_grub2_bootloader() {
		if [[ $(</sys/firmware/efi/fw_platform_size) -eq 64 ]]; then
			grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
		elif [[ $(</sys/firmware/efi/fw_platform_size) -eq 32 ]]; then
			grub-install --target=i386-efi --efi-directory=/boot --bootloader-id=GRUB
		else
			grub-install --target=i386-pc "${BOOT_PART//[0-9]/}"
		fi
	}
	_grub2_bootloader_config() {
		sed -i -e "s/.GRUB_CMDLINE_LINUX/GRUB_CMDLINE_LINUX/" \
			-e "s/.GRUB_CMDLINE_LINUX_DEFAULT/GRUB_CMDLINE_LINUX_DEFAULT/" \
			-e "s/.GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/" \
			"${BOOT_CONF}" # can't allow these to be commented out

		# https://access.redhat.com/sites/default/files/attachments/201501-perf-brief-low-latency-tuning-rhel7-v1.1.pdf
		# acpi_osi=Linux: tell BIOS to load their ACPI tables for Linux.
		sed -i -e "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=lukspart root=/dev/mapper/lukspart rootflags=subvol=@root rw\"|" \
			-e "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${COMMON_PARAMS}\"|" \
			-e "s|GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|" \
			"${BOOT_CONF}"
	}
	_setup_grub2_bootloader
	_grub2_bootloader_config

elif [[ ${bootloader_type} -eq 2 ]]; then
	_setup_refind_bootloader() {
		# x86_64-efi: rEFInd overrides GRUB2 without issues.
		refind-install

		_move2bkup "/etc/pacman.d/hooks/refind.hook" &&
			cp "${cp_flags}" "${GIT_DIR}"/files/etc/pacman.d/hooks/refind.hook "/etc/pacman.d/hooks/"
	}
	_refind_bootloader_config() {
		_move2bkup "${BOOT_CONF}"
		cat <<EOF >"${BOOT_CONF}"
"Boot using standard options"  "rd.luks.name=${LUKS_UUID}=lukspart root=/dev/mapper/lukspart rootflags=subvol=@root rw ${COMMON_PARAMS}"

"Boot to single-user mode"  "single rd.luks.name=${LUKS_UUID}=lukspart root=/dev/mapper/lukspart rootflags=subvol=@root rw ${COMMON_PARAMS}"

"Boot with minimal options"  "rd.luks.name=${LUKS_UUID}=lukspart root=/dev/mapper/lukspart rootflags=subvol=@root rw"
EOF
	}
	_setup_refind_bootloader
	_refind_bootloader_config

	_move2bkup "/usr/share/libalpm/scripts/grub-mkconfig"
	_move2bkup "/etc/pacman.d/hooks/zz_snap-pac-grub-post.hook"
fi

# Ensure "net.ipv4.tcp_congestion_control = bbr" is a valid option.
_move2bkup "/etc/modules-load.d/tcp_bbr.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/modules-load.d/tcp_bbr.conf "/etc/modules-load.d/"

# zRAM is a swap type that helps performance more often than not, and doesn't decrease longevity of drives.
_move2bkup "/etc/systemd/zram-generator.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/systemd/zram-generator.conf "/etc/systemd/" &&
	sed -i "s/max-zram-size = ~post_chroot.sh~/max-zram-size = ${TOTAL_RAM}/" /etc/systemd/zram-generator.conf

# Configures some kernel parameters; also contains memory management settings specific to zRAM.
_move2bkup "/etc/sysctl.d/99-custom.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/sysctl.d/99-custom.conf "/etc/sysctl.d/"

# Stop systemd-oomd from being overzealous on killing memory heavy processes before the physical memory is fully used.
sed -i -e "s/.DefaultMemoryPressureLimit.*/DefaultMemoryPressureLimit=100%/" \
	-e "s/.SwapUsedLimit.*/SwapUsedLimit=100%/" /etc/systemd/oomd.conf

# Use overall best I/O scheduler for each drive type (NVMe, SSD, HDD).
_move2bkup "/etc/udev/rules.d/60-io-schedulers.rules" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/udev/rules.d/60-io-schedulers.rules "/etc/udev/rules.d/"

# https://wiki.archlinux.org/title/zsh#On-demand_rehash
_move2bkup "/etc/pacman.d/hooks/zsh.hook" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/pacman.d/hooks/zsh.hook "/etc/pacman.d/hooks/"

# Flatpak requires this for "--filesystem=xdg-config/fontconfig:ro"
_move2bkup "/etc/fonts/local.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/fonts/local.conf "/etc/fonts/"

# Makes our font and cursor settings work inside Flatpak.
FLATPAK_PARAMS="--filesystem=xdg-config/fontconfig:ro --filesystem=/home/${WHICH_USER}/.icons/:ro --filesystem=/home/${WHICH_USER}/.local/share/icons/:ro --filesystem=/usr/share/icons/:ro"
if [[ ${DEBUG} -eq 1 ]]; then
	# shellcheck disable=SC2086
	flatpak -vv override ${FLATPAK_PARAMS}
else
	# shellcheck disable=SC2086
	flatpak override ${FLATPAK_PARAMS}
fi

# Syntax errors in /etc/nsswitch.conf will break /etc/passwd, /etc/group, and /etc/hosts (breaking the whole OS until repaired).
chattr -f +i /etc/nsswitch.conf

_move2bkup "/etc/xdg/reflector/reflector.conf" &&
	cp "${cp_flags}" "${GIT_DIR}"/files/etc/xdg/reflector/reflector.conf "/etc/xdg/reflector/"

_prepare_03() {
	chmod +x -R {/home/"${WHICH_USER}"/dux,/home/"${WHICH_USER}"/dux_backup_"${DATE}"} || :
	chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}"
}
trap _prepare_03 EXIT
