#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

_pkgs_aur_add() {
	[[ -n ${PKGS_AUR} ]] &&
		# -Sdd bypasses a dependency cycle problem proprietary NVIDIA drivers have (only if different proprietary version is installed, say 'nvidia-lts')
		sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 paru -Sdd --quiet --noconfirm --useask --needed --skipreview ${PKGS_AUR}"
}

PKGS+="lib32-mesa lib32-ocl-icd lib32-vulkan-icd-loader mesa ocl-icd vulkan-icd-loader "

_nouveau_setup() {
	PKGS+="xf86-video-nouveau "
	_move2bkup "/etc/modprobe.d/nvidia.conf"
	_move2bkup "/etc/modprobe.d/nouveau.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/nouveau.conf "/etc/modprobe.d/"

	_nouveau_reclocking() {
		GPU_PSTATE=$(whiptail --inputbox "$(</sys/kernel/debug/dri/0/pstate)" 0 0 --title "Specify highest power state (likely 0f); do not use the AC power state!" 3>&1 1>&2 2>&3)
		exitstatus=$?
		if [[ ${exitstatus} -eq 0 ]]; then
			# Kernel parameter only; reclocking later (say, after graphical.target) is likely to crash the GPU.
			NOUVEAU_RECLOCK="nouveau.config=NvClkMode=$((16#${GPU_PSTATE}))"
			local PARAMS="${NOUVEAU_RECLOCK}"
			_modify_kernel_parameters
		fi
	}
	_nouveau_reclocking

	# Works fine, though using X11 instead of Wayland is bad on Nouveau
	printf "needs_root_rights = no" >/etc/X11/Xwrapper.config

	_nouveau_custom_parameters() {
		if [[ ${nouveau_custom_parameters} -eq 1 ]]; then
			# Atomic mode-setting reduces potential flickering while also being quicker, the result is buttery-smooth rendering under Wayland; disabled due to instability
			# Message Signaled Interrupts lowers system latency ("DPC latency" on Windows) while increasing GPU performance
			#
			# init_on_alloc=0 init_on_free=0: https://gitlab.freedesktop.org/xorg/driver/xf86-video-nouveau/-/issues/547
			# cipher=0: https://gitlab.freedesktop.org/xorg/driver/xf86-video-nouveau/-/issues/547#note_1097449
			local PARAMS="init_on_alloc=0 init_on_free=0 nouveau.atomic=0 nouveau.config=NvMSI=1 nouveau.config=cipher=0"
			_modify_kernel_parameters
		fi
	}
	_nouveau_custom_parameters

	# Have to rebuild initramfs to apply new kernel module config changes by /etc/modprobe.d
	REGENERATE_INITRAMFS=1
}

_nvidia_setup() {
	PKGS+="xorg-server-devel nvidia-prime "
	_move2bkup "/etc/modprobe.d/nvidia.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/nvidia.conf "/etc/modprobe.d/"

	[[ ${nvidia_force_pcie_gen2} -eq 1 ]] &&
		sed -i "s/NVreg_EnablePCIeGen3=1/NVreg_EnablePCIeGen3=0/" /etc/modprobe.d/nvidia.conf

	[[ ${nvidia_stream_memory_operations} -eq 1 ]] &&
		sed -i "s/NVreg_EnableStreamMemOPs=0/NVreg_EnableStreamMemOPs=1/" /etc/modprobe.d/nvidia.conf

	_nvidia_enable_drm() {
		local PARAMS="nvidia-drm.modeset=1"
		_modify_kernel_parameters

		if ! grep -q "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" /etc/mkinitcpio.conf; then
			echo "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" >>/etc/mkinitcpio.conf
		fi
	}
	_nvidia_enable_drm

	_nvidia_force_max_performance() {
		if [[ ${nvidia_force_max_performance} -eq 1 ]]; then
			sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 cp ${cp_flags} ${GIT_DIR}/files/home/.config/systemd/user/nvidia-max-performance.service /home/${WHICH_USER}/.config/systemd/user/"
			systemctl --user enable nvidia-max-performance.service

			# Allow the "Prefer Maximum Performance" PowerMizer setting on laptops
			local PARAMS="nvidia.NVreg_RegistryDwords=OverrideMaxPerf=0x1"
			_modify_kernel_parameters
		fi
	}
	_nvidia_force_max_performance

	_nvidia_after_install() {
		# Running Xorg rootless breaks clock/power/fan control: https://gitlab.com/leinardi/gwe/-/issues/92
		printf "needs_root_rights = yes" >/etc/X11/Xwrapper.config

		# GreenWithEnvy: Overclocking, power & fan control, GPU graphs; akin to MSI Afterburner
		nvidia-xconfig --cool-bits=28
		FLATPAKS+="com.leinardi.gwe "

		# Xorg will break on trying to load Nouveau first if this file exists
		[[ -e "/etc/X11/xorg.conf.d/20-nouveau.conf" ]] &&
			chattr -f -i /etc/X11/xorg.conf.d/20-nouveau.conf &&
			rm -f /etc/X11/xorg.conf.d/20-nouveau.conf

		REGENERATE_INITRAMFS=1
	}
	trap _nvidia_after_install EXIT
}

_amd_setup() {
	PKGS+="libva-mesa-driver mesa-vdpau "
	_move2bkup "/etc/modprobe.d/amdgpu.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/amdgpu.conf "/etc/modprobe.d/"

	_move2bkup "/etc/modprobe.d/radeon.conf" &&
		cp "${cp_flags}" "${GIT_DIR}"/files/etc/modprobe.d/radeon.conf "/etc/modprobe.d/"

	if [[ ${amd_graphics_force_radeon} -eq 1 ]]; then
		_move2bkup "/etc/modprobe.d/amdgpu.conf"
		echo "MODULES+=(radeon)" >>/etc/mkinitcpio.conf
	else
		_move2bkup "/etc/modprobe.d/radeon.conf"
		echo "MODULES+=(amdgpu)" >>/etc/mkinitcpio.conf
		_amd_graphics_sysfs() {
			if [[ ${amd_graphics_sysfs} -eq 1 ]]; then
				local PARAMS="amdgpu.ppfeaturemask=0xffffffff"
				_modify_kernel_parameters
			fi
		}
		_amd_graphics_sysfs
	fi

	REGENERATE_INITRAMFS=1
}

_intel_setup() {
	[[ ${intel_video_accel} -eq 1 ]] &&
		PKGS+="libva-intel-driver "
	[[ ${intel_video_accel} -eq 2 ]] &&
		PKGS+="intel-media-driver "

	PKGS+="vulkan-intel "

	# Early load KMS driver
	if ! grep -q "i915" /etc/mkinitcpio.conf; then
		echo -e "\nMODULES+=(i915)" >>/etc/mkinitcpio.conf
	fi

	REGENERATE_INITRAMFS=1
}

# grep: -P/--perl-regexp benched faster than -E/--extended-regexp
# shellcheck disable=SC2249
case $(lspci | grep -P "VGA|3D|Display" | grep -Po "NVIDIA|AMD/ATI|Intel Corporation|VMware SVGA|Red Hat") in
*"NVIDIA"*)
	case ${nvidia_driver_series} in
	1)
		_nvidia_setup
		PKGS+="nvidia-dkms egl-wayland nvidia-utils opencl-nvidia libxnvctrl nvidia-settings \
				lib32-nvidia-utils lib32-opencl-nvidia "
		;;
	2)
		_nvidia_setup
		PKGS+="egl-wayland "
		PKGS_AUR+="nvidia-470xx-dkms nvidia-470xx-utils opencl-nvidia-470xx libxnvctrl-470xx nvidia-470xx-settings \
				lib32-nvidia-470xx-utils lib32-opencl-nvidia-470xx "
		;;
	3) # Settings for current drivers seem to work fine for 390.xxx
		_nvidia_setup
		PKGS+="egl-wayland "
		PKGS_AUR+="nvidia-390xx-dkms nvidia-390xx-utils opencl-nvidia-390xx libxnvctrl-390xx nvidia-390xx-settings \
				lib32-nvidia-390xx-utils lib32-opencl-nvidia-390xx "
		;;
	4)
		_nouveau_setup
		;;
	*)
		printf "\nWARNING: No valid 'nvidia_driver_series' option was specified!\n"
		;;
	esac
	;;&
*"AMD/ATI"*)
	_amd_setup
	;;&
*"Intel Corporation"*)
	_intel_setup
	;;&
*"VMware"*)
	PKGS+="xf86-video-vmware "
	;;&
*"Red Hat"*)
	PKGS+="xf86-video-qxl spice-vdagent qemu-guest-agent "
	;;
esac

_pkgs_add
_pkgs_aur_add || :
_flatpaks_add || :

if [[ ${NOT_CHROOT} -eq 0 ]]; then
	# shellcheck disable=SC2086
	_systemctl enable ${SERVICES}
elif [[ ${NOT_CHROOT} -eq 1 ]]; then
	# shellcheck disable=SC2086
	_systemctl enable --now ${SERVICES}
fi

[[ ${DUX_INSTALLER} -ne 1 ]] && [[ ${REGENERATE_INITRAMFS} -eq 1 ]] &&
	mkinitcpio -P

[[ ${DUX_INSTALLER} -ne 1 ]] && [[ ${REGENERATE_GRUB2_CONFIG} -eq 1 ]] &&
	grub-mkconfig -o /boot/grub/grub.cfg

cleanup() {
	mkdir "${mkdir_flags}" "${BACKUPS}/etc/modprobe.d"
	chown -R "${WHICH_USER}:${WHICH_USER}" "${BACKUPS}/etc/modprobe.d"
}
trap cleanup EXIT
