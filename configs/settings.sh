#!/bin/bash
# shellcheck disable=SC2034,SC2249
set -a

# Don't use any of the following: symbols, spaces, upper-case letters.
INITIAL_USER="admin"

# Don't use any of the following: symbols, spaces.
system_hostname="arch"

# Controls keyboard layout.
# by ca cf cz de dk es et fa fi fr gr hu il it lt lv mk nl no pl ro ru sg ua uk us
system_keymap="us"

# DSL/PPPoE connections.
hardware_dsl_pppoe="0"

# Mobile broadband (2G/3G/4G) devices and connections.
hardware_mobile_broadband="0"

# NOTE: WiFi and Bluetooth are inseparable here.
hardware_wifi_and_bluetooth="1"

# https://digimend.github.io/tablets/
hardware_nonwacom_drawing_tablet="0"

# Supported printer list: https://www.openprinting.org/printers
hardware_printers_and_scanners="1"

# LVM2 not used to reduce potential breakage, also reduces boot times; LVM2 could have been used to allow resizing the /boot partition.
disks_lvm2="0"

# NOT FULLY TESTED YET
support_hibernation="0"

# If UEFI isn't available, GRUB2 is forced.
# 1: GRUB2
# 2: rEFInd
bootloader_type="2"

# A good backup incase linux-zen doesn't work right.
# Will download around an extra 300MB.
include_kernel_lts="1"

#- Download server region selection
#
# North America (United States -> Canada): US,CA
# South America (Brazil -> Mexico -> United States): BR,MX,US
# Europe #1 (Germany -> Netherlands): DE,NL
# Europe #2 (Sweden -> Finland -> Norway): SE,FI,NO
# South Africa (SA -> Kenya -> India): ZA,KE,IN
# West Asia (Israel -> Italy -> France -> Georgia): IL,IT,FR,GE
# NE Asia (Japan -> South Korea -> Taiwan): JP,SK,TW
# SE Asia (Singapore -> Hong Kong -> Indonesia -> Thailand): SG,HK,ID,TH
# Oceania (Australia -> New Zealand -> New Caledonia): AU,NZ,NC
#
# Countries not listed here are at your own risk!
reflector_countrylist="US,CA"

#- GNOME is more stable than KDE.
# 0:  Don't install a desktop environment (use your own).
# 1:  GNOME  -> https://www.gnome.org/
# 2:  KDE    -> https://kde.org/plasma-desktop/
desktop_environment="1"

case ${desktop_environment} in
1)
    # This rice won't break GNOME now and in the future; it's not recommended to run the non-riced/vanilla GNOME.
    allow_gnome_rice="1"

    if [[ ${allow_gnome_rice} -eq 1 ]]; then
        gnome_document_font_name="Liberation Sans 11"
        gnome_font_name="Liberation Sans 11"
        gnome_monospace_font_name="Hack 10" # This is actually font size 11; it's a GNOME quirk.

        gnome_font_aliasing="rgba" # rgba, greyscale, none
        # "full" is intended for Liberation Sans, for others it's usually "slight".
        gnome_font_hinting="full" # none, slight, medium, full

        gnome_mouse_accel_profile="flat"    # flat, adaptive, default
        gnome_remember_app_usage="false"    # true, false
        gnome_remember_recent_files="false" # true, false
    fi

    # - GNOME Display Manager -
    gdm_auto_login="1"
    gdm_disable_wayland="0"
    ;;
2)
    # A touchscreen keyboard.
    kde_install_virtual_keyboard="0"
    # For Wacom-based touchscreens and tablets.
    kde_install_wacom_configurator="0"
    # Try this only if KDE seems buggy.
    kde_use_kwinft="0"
    # Again like GNOME, extra care was taken to ensure this doesn't break anything.
    allow_kde_rice="1"

    if [[ ${allow_kde_rice} -eq 1 ]]; then
        kde_general_font="Liberation Sans,11"
        kde_fixed_width_font="Hack,11"
        kde_small_font="Liberation Sans,9"
        kde_toolbar_font="Liberation Sans,10"
        kde_menu_font="Liberation Sans,10"

        # "false" to use the default mouse acceleration profile (Adaptive).
        kde_mouse_accel_flat="true"
        # hintnone, hintslight, hintmedium, hintfull
        # hintfull note: Fonts will look squished in some software; not an issue for GNOME.
        kde_font_hinting="hintfull"
        # none, rgb, bgr, vrgb (Vertical RGB), vbgr (Vertical BGR)
        kde_font_aliasing="rgb"

        # Disables window titlebars to prioritize mouse & keyboard instead of mouse oriented window management.
        kwin_no_titlebars="1"

        kwin_animations="false" # true, false

        # Controls window drop-shadows: ShadowNone, ShadowSmall, ShadowMedium, ShadowLarge, ShadowVeryLarge
        kwin_shadow_size="ShadowNone"
    fi

    # - Simple Desktop Display Manager -
    sddm_autologin="1"
    sddm_autologin_session_type="plasma" # plasma, plasmawayland
    ;;
esac

# 1: Proprietary current
# 2: Proprietary 470.xxx
# 3: Proprietary 390.xxx (For Fermi 1.0 to Maxwell 1.0)
# 4: Open-source (For Maxwell 1.0 or older)
nvidia_driver_series="1"

case ${nvidia_driver_series} in
[1-3])
    # Enforce "Prefer Maximum Performance" (some GPUs lag hard without this).
    nvidia_force_max_performance="0"

    # Disable PCIe Gen 3.0 support (not recommended; only if needed for stability).
    nvidia_force_pcie_gen2="0"

    # https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__MEMOP.html#group__CUDA__MEMOP
    nvidia_stream_memory_operations="0"
    ;;
4)
    # Increases stability and performance for Nouveau drivers.
    nouveau_custom_parameters="1"
    ;;
esac

# Force 'radeon' driver (GCN2 and below only, but not recommended).
amd_graphics_force_radeon="0"

# Allows adjusting clocks and voltages; Gamemode can use this to automatically set/unset max performance.
amd_graphics_sysfs="1"

# Enables hardware video acceleration; use 2 if possible.
# 1: GMA 4500 (2008) up to Coffee Lake's (2017) HD Graphics.
# 2: HD Graphics series starting from Broadwell (2014) and newer.
intel_video_accel="2"

# Skip installing GPU software, which will break desktop environments.
disable_gpu="0"
