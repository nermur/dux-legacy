#!/bin/bash
# shellcheck disable=SC2162
set +H
set -e

umount -flRq /mnt || :
cryptsetup close lukspart >&/dev/null || :

lsblk -o PATH,MODEL,FSTYPE,FSVER,SIZE,FSUSE%,FSAVAIL

_select_disk() {
    read -rep $'\nDisk examples: /dev/sda or /dev/nvme0n1; don\'t use partition numbers like: /dev/sda1 or /dev/nvme0n1p1.\nInput your desired disk, then press ENTER: ' -i "/dev/" DISK
    _disk_selected() {
        echo -e "\n\e[1;35mSelected disk: ${DISK}\e[0m\n"
        read -p "Is this correct? [y/n]: " choice
    }
    _disk_selected
    case ${choice} in
    [Yy]*)
        return 0
        ;;
    [Nn]*)
        _select_disk
        ;;
    *)
        echo -e "\nInvalid option!\nValid options: Y, y, N, n"
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

wipefs -af "${PARTITION3}"  # Assumed here to remove LUKS2 signatures
sgdisk -Zo "${DISK}"        # Remove GPT & MBR data structures and all partitions on selected disk
sgdisk -a 2048 -o "${DISK}" # Create GPT disk 2048 alignment

# Create partitions
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BOOTMBR' "${DISK}"    # Partition 1 (MBR "BIOS" boot)
sgdisk -n 2::+1024M --typecode=2:ef00 --change-name=2:'BOOTEFI' "${DISK}" # Partition 2 (UEFI boot)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'DUX' "${DISK}"         # Partition 3 (LUKS2 encrypted root)
if [[ ! -d "/sys/firmware/efi" ]]; then
    # Set partition 2 to use typecode ef02 if UEFI was not detected.
    sgdisk -A 1:set:2 "${DISK}"
fi

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
_password_prompt
