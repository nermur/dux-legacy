#!/bin/bash
# shellcheck disable=SC2154
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"
source "${GIT_DIR}/configs/optional_software.sh"

mkdir "${mkdir_flags}" /home/"${WHICH_USER}"/.config/systemd/user
chown -R "${WHICH_USER}:${WHICH_USER}" "/home/${WHICH_USER}/.config/systemd/user"

chmod +x -R "${GIT_DIR}"

[[ ${helvum} -eq 1 ]] &&
PKGS+="helvum "

[[ ${virtual_machines} -eq 1 ]] &&
	PKGS+="qemu-desktop libvirt virt-manager edk2-ovmf iptables-nft dnsmasq virglrenderer hwloc dmidecode usbutils swtpm "

_virtual_machines_setup() {
	if [[ ${virtual_machines} -eq 1 ]]; then
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/custom_kvm.conf "/etc/modprobe.d/"
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/udev/rules.d/99-qemu.rules "/etc/udev/rules.d/"

		# qemu: If using QEMU directly is desired instead of libvirt.
		# video: Virtio OpenGL acceleration.
		# kvm: Hypervisor hardware acceleration.
		# libvirt: Access to virutal machines made through libvirt.
		usermod -a -G qemu,video,kvm,libvirt "${WHICH_USER}"

		local PARAMS="intel_iommu=on"
		_modify_kernel_parameters

		[[ ${REGENERATE_GRUB2_CONFIG} -eq 1 ]] &&
			grub-mkconfig -o /boot/grub/grub.cfg

		systemctl enable --now libvirtd.service

		virsh net-autostart default

		whiptail --yesno "A reboot is required to complete installing virtual machine support.\nReboot now?" 0 0 &&
			reboot -f
	fi
}

[[ ${spotify} -eq 1 ]] &&
	PKGS_AUR+="spotify "

[[ ${spotify_adblock} -eq 1 ]] &&
	PKGS_AUR+="spotify-adblock-git spotify-remove-ad-banner "

[[ ${easyeffects} -eq 1 ]] &&
	PKGS+="easyeffects "

if [[ ${opensnitch} -eq 1 ]]; then
	PKGS_AUR+="opensnitch "
	SERVICES+="opensnitchd.service "
fi

[[ ${octopi} -eq 1 ]] &&
	PKGS_AUR+="octopi "

[[ ${ttf_merriweather} -eq 1 ]] &&
	PKGS_AUR+="ttf-merriweather "

[[ ${vorta} -eq 1 ]] &&
	FLATPAKS+="com.borgbase.Vorta "

[[ ${dolphin} -eq 1 ]] &&
	PKGS+="ark dolphin kde-cli-tools kdegraphics-thumbnailers kimageformats qt5-imageformats ffmpegthumbs taglib openexr libjxl "

if [[ ${mpv} -eq 1 ]]; then
	PKGS+="mpv "
	trap 'sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 /home/${WHICH_USER}/dux/scripts/non-SU/software_catalog/mpv_config.sh"' EXIT
fi

[[ ${visual_studio_code} -eq 1 ]] &&
	PKGS_AUR+="visual-studio-code-bin "

[[ ${evince} -eq 1 ]] &&
	PKGS+="evince "

if [[ ${obs_studio} -eq 1 ]]; then
	# v4l2loopback = for Virtual Camera; a good universal way to screenshare.
	PKGS+="obs-studio v4l2loopback-dkms "
	if hash pipewire >&/dev/null; then
		PKGS+="pipewire-v4l2 lib32-pipewire-v4l2 "
	fi
fi

[[ ${firefox} -eq 1 ]] &&
	FLATPAKS+="org.mozilla.firefox "

[[ ${foliate} -eq 1 ]] &&
	PKGS+="foliate "

[[ ${qbittorrent} -eq 1 ]] &&
	PKGS+="qbittorrent "

[[ ${nomacs} -eq 1 ]] &&
	PKGS+="nomacs "

[[ ${gimp} -eq 1 ]] &&
	PKGS+="gimp "

[[ ${yt_dlp} -eq 1 ]] &&
	PKGS+="aria2 atomicparsley ffmpeg rtmpdump yt-dlp "

[[ ${evolution} -eq 1 ]] &&
	PKGS+="evolution "

[[ ${discord} -eq 1 ]] &&
	FLATPAKS+="com.discordapp.Discord "

[[ ${telegram} -eq 1 ]] &&
	FLATPAKS+="org.telegram.desktop "

[[ ${github_desktop} -eq 1 ]] &&
	PKGS_AUR+="github-desktop-bin "

[[ ${solanum} -eq 1 ]] &&
	FLATPAKS+="org.gnome.Solanum "

if [[ ${cxx_toolbox} -eq 1 ]]; then
	PKGS+="gdb gperftools valgrind pwndbg rz-cutter rz-ghidra "
	PKGS_AUR+="lib32-gperftools "
fi

[[ ${qps} -eq 1 ]] &&
	PKGS_AUR+="qps "

# Anki specifically forces the Qt stylesheets, so Kvantum and others don't work; this is not a Flatpak bug.
[[ ${anki} -eq 1 ]] &&
	FLATPAKS+="net.ankiweb.Anki "

if [[ ${vg_toolbox} -eq 1 ]]; then
	PKGS+="lutris "
	PKGS_AUR+="goverlay-bin mangohud-common-x11 mangohud-x11 lib32-mangohud-x11 "
	FLATPAKS+="net.davidotek.pupgui2 "
fi

# Control Flatpak settings per application
FLATPAKS+="com.github.tchx84.Flatseal "

_pkgs_add
_pkgs_aur_add
_flatpaks_add

# shellcheck disable=SC2086
_systemctl enable --now ${SERVICES}

_virtual_machines_setup
