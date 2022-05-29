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
rm -f /usr/share/libalpm/hooks/{60-mkinitcpio-remove.hook,90-mkinitcpio-install.hook}
PKGS+="mkinitcpio "

if [[ ${bootloader_type} -eq 1 ]]; then
    PKGS+="grub-btrfs "
elif [[ ${bootloader_type} -eq 2 ]]; then
    # trbs, the developer of python-pid, uses an expired PGP key.
    gpg --recv-keys 13FFEEE3DF809D320053C587D6E95F20305701A1
    PKGS_AUR+="refind-btrfs "
    _pkgs_aur_add
fi

_pkgs_add

[[ ${bootloader_type} -eq 1 ]] &&
    grub-mkconfig -o /boot/grub/grub.cfg

# Without this, Dux will not function correctly if ran by a different user than the home directories' assigned user.
git config --global --add safe.directory /home/"${WHICH_USER}"/dux
git config --global --add safe.directory /root/dux

_cleanup() {
    echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/custom_settings
}
trap _cleanup EXIT
