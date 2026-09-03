# Omarchy AirPlay & HomePod Multi-Room

An advanced Omarchy status bar plugin for **Apple HomePod AirPlay 2 Multi-Room Audio Streaming** and **Wayland Desktop Screen Mirroring** through [DoubleTake](https://github.com/omarroth/doubletake).

Stream low-latency desktop audio to multiple Apple HomePods and AirPlay speakers synchronously, control room volumes directly from the bar, and mirror your screen to Apple TVs.

---

## 🚀 Quick Setup (One-Command Installer)

To install all prerequisites (OwnTone, PipeWire sinks, FIFO bridge, systemd services) and configure low-latency AirPlay 2:

```bash
cd ~/.config/omarchy/plugins/io.github.bchurch95.omarchy-universal-cast
./setup-homepod.sh
```

---

## ✨ Features

### 🎵 Apple HomePod & AirPlay 2 Multi-Room Audio
- **Multi-Room Synchronized Audio**: Stream system audio to multiple Apple HomePods (Living Room, Bedroom, Kitchen, Bathroom, Nursery, etc.) simultaneously in sync via AirPlay 2 PTP clocks.
- **Automatic PipeWire Routing**: Selecting a HomePod automatically routes system audio and active applications (YouTube, Spotify, etc.) to the HomePods. Unselecting returns audio seamlessly to laptop speakers.
- **Native Per-Speaker Volume Sliders**: Smoothly control the amplifier volume of each individual room directly from the status bar popup.
- **Batch Actions**: One-click "Select All" and "Turn Off All".
- **Zero Echo / No Local Delay**: Automatically disables local ALSA soundcard double-playback.

### 🖥️ AirPlay Screen Mirroring (Apple TV & Receivers)
- Discovers AirPlay receivers through mDNS/Avahi.
- Starts and stops desktop mirroring from the bar via DoubleTake.
- Pairs new receivers with on-screen PIN codes.
- Supports Wayland screen/window/region pickers and configurable FPS/codecs.

---

## Requirements & Prerequisites

### Core System Packages
- **Omarchy** with `omarchy-shell` & `hyprland`
- **Audio & Discovery**: `pipewire`, `pipewire-pulse`, `pulseaudio-utils` (`parec`), `wireplumber`, `avahi` (`avahi-daemon`), `jq`
- **Python 3** for bounded process supervision and local state management
- **HomePod AirPlay 2 Multi-Room Server**: `owntone-server` (AUR)

### Video & GPU Hardware Acceleration
- **DoubleTake**: `doubletake` (with AirPlay 2 HAP & Intel QSV support)
- **GStreamer Core & Media Plugins**: `gst-plugins-good`, `gst-plugins-bad`, `gst-plugin-pipewire`, `gst-plugin-gtk`
- **Hardware Acceleration**:
  - **Intel Arc / Lunar Lake / Xe Graphics**: `gst-plugin-qsv`, `onevpl-intel-gpu`, `intel-media-driver`, `libva-utils`
  - **NVIDIA**: `gst-plugin-nvcodec` / Vulkan
  - **Software (CPU Fallback)**: OpenH264 SIMD (`openh264enc`)

### Install Packages (Arch / Omarchy)

```sh
# Core audio, discovery, and GPU hardware encoding
sudo pacman -S --needed avahi jq pipewire pipewire-pulse pulseaudio-utils wireplumber \
    libva-utils gst-plugins-good gst-plugins-bad gst-plugin-pipewire \
    gst-plugin-qsv onevpl-intel-gpu intel-media-driver

# Multi-room HomePod daemon and AirPlay screen mirroring
yay -S --needed owntone-server doubletake

# Enable system services
sudo systemctl enable --now avahi-daemon owntone
```

---

## 📺 Apple TV & AirPlay Configuration Notes

### 1. Apple TV Access Permissions
To mirror smoothly from Linux to tvOS:
- On your Apple TV, go to **Settings > AirPlay and HomeKit**.
- Set **Allow Access** to **"Everyone on the Same Network"** (or *"Anyone on the Same Network"*). If set to "Current User" or "Home Members Only", tvOS may silently reject connection requests from non-Apple devices.
- Set **Require Code** to **"First Time Only"** or **"Off"**.

### 2. Device Separation
The status bar widget automatically categorizes network devices:
- **Screen Mirroring (Video Receivers)**: Automatically filters mDNS TXT records to show only video-capable devices (`Apple TV`, `MacBook Pro`, AirPlay display adapters). Audio-only speakers are excluded from the screen list.
- **HomePods & Audio (AirPlay 2 Multi-Room)**: Displays all HomePods, Sonos, and AirPlay speakers with individual volume sliders, **Select All**, and **Turn Off All** controls.

### 3. Firewall (UFW)
DoubleTake uses a local port range (default: `60000:60010`) for reverse timing and event sockets. If you use a firewall like UFW, permit both UDP and TCP traffic for your Apple TV's IP:
```sh
sudo ufw allow in proto udp from <APPLE_TV_IP> to any port 60000:60010
sudo ufw allow in proto tcp from <APPLE_TV_IP> to any port 60000:60010
```

---

## Install

### From GitHub

After this repository has been published, install the plugin with Omarchy:

```sh
omarchy plugin add https://github.com/bchurch95/omarchy-airplay.git --enable
omarchy bar move io.github.bchurch95.omarchy-universal-cast --section right
```

The first command installs a user-owned copy below
`~/.config/omarchy/plugins/`; it does not modify Omarchy's packaged files.

### From the Omarchy Plugin Marketplace

Once the listing has been approved, install it from the Omarchy plugin browser
or with the marketplace-provided install command. The marketplace listing
points to the same public GitHub repository; it does not host a separate copy
of the plugin.

### Development checkout

For local development, clone the repository and link it into your user plugin
directory:

```sh
git clone https://github.com/bchurch95/omarchy-airplay.git
cd omarchy-airplay
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.bchurch95.omarchy-universal-cast
omarchy-shell shell rescanPlugins
omarchy bar move io.github.bchurch95.omarchy-universal-cast --section right
```

Saved changes under `~/.config/omarchy/plugins/` normally reload
automatically. If the plugin does not appear after a manifest change, run
`omarchy-shell shell rescanPlugins`.

## Use

Click the AirPlay icon in the bar to open or close the receiver list. Click a
receiver row to select it; click that row again to clear the selection. Use the
screen icon on the right to start or stop mirroring.

For a new receiver, select it and press the screen icon once. Enter the PIN
shown by the receiver, then choose **Pair & connect**. DoubleTake stores the
receiver credential in `~/.config/doubletake/credentials.json` for later use.
The PIN field is only shown after a connection has been attempted.

The trash icon is shown only for paired receivers. It removes that receiver's
saved DoubleTake credential, so the next connection must pair again. It does
not change the receiver itself.

By default, **Choose capture source every time** is enabled. A new mirroring
session opens the portal picker so you can choose a screen, window, or region.
It clears only the saved capture selection for that receiver and keeps its
AirPlay pairing intact.

## Configure

Open the widget's settings in Omarchy to configure the DoubleTake executable,
video codec, hardware encoder, FPS, target latency, audio, and UDP port range.

`h264` is the compatibility default. On current Intel graphics, `vaapi` with
the VAAPI driver set to `iHD` is often a good low-latency option. On hybrid-GPU
systems, explicitly selecting the working encoder can be more reliable than
`auto`.

Useful IPC calls:

```sh
omarchy-shell io.github.bchurch95.omarchy-universal-cast status
omarchy-shell io.github.bchurch95.omarchy-universal-cast toggle
omarchy-shell io.github.bchurch95.omarchy-universal-cast discover
omarchy-shell io.github.bchurch95.omarchy-universal-cast select "Living Room" 192.168.1.50 AA:BB:CC:DD:EE:FF
omarchy-shell io.github.bchurch95.omarchy-universal-cast unselect
```

## Troubleshooting

### No receivers are listed

Confirm Avahi is running, then test discovery:

```sh
systemctl is-active avahi-daemon
avahi-browse --resolve --terminate _airplay._tcp
```

The computer and receiver must be on the same network, and multicast DNS must
not be blocked by the network.

### The portal picker does not appear or mirroring is black

Check that PipeWire and the Hyprland portal are running, then stop the mirror
and start it again from the receiver row. Selecting a source in the portal is
required before video can begin.

### Mirroring connects but does not update

Try `h264` at 30 FPS, then explicitly select the encoder that matches your GPU
(`vaapi`, `nvenc`, or software). If UFW is enabled, use **Allow selected
receiver** for the selected receiver and retry.

### Inspect plugin validation and logs

```sh
omarchy plugin validate ~/.config/omarchy/plugins/io.github.bchurch95.omarchy-universal-cast
omarchy plugin list --json | jq '.[] | select(.id == "io.github.bchurch95.omarchy-universal-cast")'
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

## Remove

Stop any active mirror, then remove the plugin by its manifest ID:

```sh
omarchy plugin remove io.github.bchurch95.omarchy-universal-cast
```

This removes only the installed plugin copy. It does not uninstall DoubleTake,
remove Avahi, or delete saved receiver credentials. If you also want to remove
all DoubleTake pairings, delete `~/.config/doubletake/credentials.json`
yourself after checking that it contains no credentials you want to keep.

## Security and privacy

Plugins run with the user's permissions. Review this repository and its
dependencies before installing it. Screen contents are sent to the selected
AirPlay receiver on the local network. Pair only with receivers you trust, and
keep firewall rules limited to trusted receiver addresses.

Receiver discovery is bounded to 32 IPv4 receivers with sanitized, length-
limited names. Local state and DoubleTake credentials are read only from
regular, user-owned, non-group/world-writable files without following links.
External helper processes have timeouts, output limits, and process-group
cleanup.

## Languages

The plugin uses English by default and selects Norwegian Bokmål text for `nb`,
`nn`, and `no` system locales. Translations live in `i18n/I18n.js`; add another
language there by supplying the same message keys as the English map.

## License

[MIT](LICENSE)
