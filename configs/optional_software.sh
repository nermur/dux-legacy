#!/bin/bash
# shellcheck disable=SC2034
set -a

# Support for virtual machines through QEMU/Libvirt/Virt-manager.
virtual_machines="0"

# Interactive application firewall.
# Please have clear intentions for using this, as it will be annoying to handle otherwise.
opensnitch="0"

# - Recommendations -
# For headphones: https://github.com/jaakkopasanen/AutoEq#pulseeffects--easyeffects
# For microphones: Use "Noise Reduction" to start out with.
easyeffects="0"

# C/C++ debugging and reverse engineering: Valgrind, GDB, radere2 + ghidra (graphical interface: Cutter), pwndbg.
cxx_toolbox="0"

# A patchbay for Pipewire. Used to direct where audio transmits to and from.
helvum="1"

# An online music player that's very useful for quickly finding songs you like, for both the big and small artists.
spotify="1"

# An adblocker for Spotify Free users.
spotify_adblock="1"

# Official Discord client with additional safety and privacy provided by Flatpak's sandboxing.
# However, this sandboxing prevents the following features from working out of the box: 
# Game Activity, Unrestricted File Access, Rich Presence.
discord="1"

# Text editor and/or IDE.
visual_studio_code="1"

# Pacman GUI frontend; makes it easier to manage Arch Linux.
octopi="1"

# An excellent Serif font to use for reading.
ttf_merriweather="1"

# A de-duplicating file backup utility using the best backend (BorgBackup).
vorta="1"

# File manager/explorer; already installed by default.
dolphin="1"

# Video player.
mpv="1"

# PDF, Postscript, TIFF, DVI, and DjVu viewer.
evince="1"

# Screen recorder, livestreamer, and virtual + physical camera manager.
obs_studio="1"

# Official builds of Firefox from Mozilla; third-party builds usually have worse performance and more bugs.
firefox="1"

# EPUB, Mobipocket, Kindle, FictionBook, and Comic book viewer.
foliate="1"

# BitTorrent client.
qbittorrent="1"

# Image/GIF viewer & editor.
nomacs="1"

# A professional image editor.
gimp="1"

# Video downloader (CLI).
yt_dlp="1"

# Email, calendar, and RSS reader.
evolution="1"

# Messaging platform #2.
telegram="1"

# Git GUI.
github_desktop="1"

# A comprehensive process manager. 
qps="1"

# Video game helpers: GOverlay, MangoHUD, Lutris.
vg_toolbox="1"

# A Pomodoro Timer; helps keep time in your control.
solanum="1"

# Spaced repetition flashcards, to remember learning material effectively.
# Required reading: https://docs.ankiweb.net/background.html
anki="1"
