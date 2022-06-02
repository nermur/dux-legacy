#!/bin/bash
# shellcheck disable=SC2034
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"

clear

# Now is the right time to generate a initramfs.
if ! lspci | grep -P "VGA|3D|Display" | grep -q "NVIDIA" && ((1 >= nvidia_driver_series <= 3)); then
    _move2bkup "/etc/mkinitcpio.d/linux-zen.preset" &&
        cp "${cp_flags}" "${GIT_DIR}"/files/etc/mkinitcpio.d/linux-zen.preset "/etc/mkinitcpio.d/"
    if [[ ${include_kernel_lts} -eq 1 ]]; then
        _move2bkup "/etc/mkinitcpio.d/linux-lts.preset" &&
            cp "${cp_flags}" "${GIT_DIR}"/files/etc/mkinitcpio.d/linux-lts.preset "/etc/mkinitcpio.d/"
    fi
    rm -f /usr/share/libalpm/hooks/{60-mkinitcpio-remove.hook,90-mkinitcpio-install.hook}
    PKGS+="mkinitcpio "

    [[ ${bootloader_type} -eq 1 ]] &&
        grub-mkconfig -o /boot/grub/grub.cfg
fi

_pkgs_add || :

# Without this, Dux will not function correctly if ran by a different user than the home directories' assigned user.
git config --global --add safe.directory /home/"${WHICH_USER}"/dux
git config --global --add safe.directory /root/dux

_cleanup() {
    echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/custom_settings
}
trap _cleanup EXIT
