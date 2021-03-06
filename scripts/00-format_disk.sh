#!/bin/bash
# shellcheck disable=SC2162
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/configs/settings.sh"

[[ ${DEBUG} -eq 1 ]] &&
    set -x

umount -flRq /mnt || :
cryptsetup close cleanit >&/dev/null || :
cryptsetup close lukspart >&/dev/null || :

lsblk -o PATH,MODEL,PARTLABEL,FSTYPE,FSVER,SIZE,FSUSE%,FSAVAIL,MOUNTPOINTS

_select_disk() {
    read -rep $'\nDisk examples: /dev/sda or /dev/nvme0n1; don\'t use partition numbers like: /dev/sda1 or /dev/nvme0n1p1.\nInput your desired disk, then press ENTER: ' -i "/dev/" DISK
    _disk_selected() {
        echo -e "\n\e[1;35mSelected disk: ${DISK}\e[0m\n"
        read -p "Is this correct? [Y/N]: " choice
    }
    _disk_selected
    case ${choice} in
    [Y]*)
        return 0
        ;;
    [N]*)
        _select_disk
        ;;
    *)
        echo -e "\nInvalid option!\nValid options: Y, N"
        _disk_selected
        ;;
    esac
}
_select_disk
export DISK

if [[ ${DISK} =~ "nvme" ]] || [[ ${DISK} =~ "mmc" ]]; then
    PARTITION2="${DISK}p2"
    PARTITION3="${DISK}p3"
else
    PARTITION2="${DISK}2"
    PARTITION3="${DISK}3"
fi

_wipe_partitions() {
    # shellcheck disable=SC2086
    wipefs -af ${DISK}* # Remove partition-table signatures on selected disk
    sgdisk -Z "${DISK}" # Remove GPT & MBR data structures on selected disk
}

_secure_overwrite() {
    read -p $'\nNOTE: Saying \'N\' will use the normal erasure, which takes no time at all.\nEstimated wait time: minutes up to hours, depending on the disk medium and size.\nDo you want to securely erase this disk? [Y/N]: ' choice
    case ${choice} in
    [Y]*)
        _wipe_partitions
        cryptsetup open --type plain -d /dev/urandom "${DISK}" cleanit
        ddrescue --force /dev/zero /dev/mapper/cleanit
        cryptsetup close cleanit
        ;;
    [N]*)
        _wipe_partitions
        return 0
        ;;
    *)
        echo -e "\nInvalid option!\nValid options: Y, N"
        _secure_overwrite
        ;;
    esac
}
_secure_overwrite

sgdisk -a 2048 -o "${DISK}"                                               # Create GPT disk 2048 alignment
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BOOTMBR' "${DISK}"    # Partition 1 (MBR "BIOS" boot)
sgdisk -n 2::+1024M --typecode=2:ef00 --change-name=2:'BOOTEFI' "${DISK}" # Partition 2 (UEFI boot)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'DUX' "${DISK}"         # Partition 3 (Root dir)
[[ ! -d "/sys/firmware/efi" ]] &&
    # Set partition 2 to use typecode ef02 if UEFI was not detected.
    sgdisk -A 1:set:2 "${DISK}"

partprobe "${DISK}" # Make Linux kernel use the latest partition tables without rebooting

mkfs.fat -F 32 "${PARTITION2}"

_password_prompt() {
    read -rp $'\nEnter a new password for the LUKS2 container: ' DESIREDPW
    if [[ -z ${DESIREDPW} ]]; then
        echo -e "\nNo password was entered, please try again.\n"
        _password_prompt
    fi

    read -rp $'\nPlease repeat your LUKS2 password: ' LUKS_PWCODE
    if [[ ${DESIREDPW} == "${LUKS_PWCODE}" ]]; then
        echo -n "${LUKS_PWCODE}" | cryptsetup luksFormat -M luks2 "${PARTITION3}"
        echo -n "${LUKS_PWCODE}" | cryptsetup open "${PARTITION3}" lukspart
    else
        echo -e "\nPasswords do not match, please try again.\n"
        _password_prompt
    fi
}
[[ ${use_disk_encryption} -eq 1 ]] && _password_prompt
exit 0
