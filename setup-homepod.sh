#!/usr/bin/env bash
# ==============================================================================
# Omarchy AirPlay - HomePod & AirPlay 2 Multi-Room Audio Setup Script
# Repository: https://github.com/bchurch95/omarchy-airplay
# ==============================================================================

set -euo pipefail

BOLD="$(tput bold 2>/dev/null || echo '')"
GREEN="$(tput setaf 2 2>/dev/null || echo '')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
BLUE="$(tput setaf 4 2>/dev/null || echo '')"
RESET="$(tput sgr0 2>/dev/null || echo '')"

log_info()    { echo "${BLUE}${BOLD}==>${RESET} $*"; }
log_success() { echo "${GREEN}${BOLD} [OK]${RESET} $*"; }
log_warn()    { echo "${YELLOW}${BOLD}[WARN]${RESET} $*"; }

echo "${BOLD}================================================================${RESET}"
echo "${BOLD}      Omarchy AirPlay: HomePod & Multi-Room Audio Setup         ${RESET}"
echo "${BOLD}================================================================${RESET}"

# 1. Install Required Packages
log_info "Step 1/6: Checking and installing required packages..."
PACKAGES=(pipewire pipewire-pulse pulseaudio-utils jq avahi wireplumber)

for pkg in "${PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
        log_info "Installing $pkg via pacman..."
        sudo pacman -S --needed --noconfirm "$pkg"
    fi
done

if ! command -v owntone >/dev/null 2>&1; then
    log_info "Installing owntone via AUR..."
    if command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm owntone-server || yay -S --needed --noconfirm owntone
    elif command -v paru >/dev/null 2>&1; then
        paru -S --needed --noconfirm owntone-server || paru -S --needed --noconfirm owntone
    else
        log_warn "Neither yay nor paru found. Please install owntone-server manually from AUR."
    fi
fi
log_success "Packages verified."

# 2. Configure PipeWire Virtual Sink
log_info "Step 2/6: Configuring PipeWire 'HomePods' virtual sink..."
mkdir -p "$HOME/.config/pipewire/pipewire-pulse.conf.d"
cat << 'PWSINK' > "$HOME/.config/pipewire/pipewire-pulse.conf.d/10-homepod-sink.conf"
pulse.cmd = [
    { cmd = "load-module" args = "module-null-sink sink_name=HomePods rate=44100 channels=2 sink_properties=device.description=HomePods" }
]
PWSINK
log_success "PipeWire virtual sink configured (44.1 kHz CD quality)."

# 3. Create Audio FIFO Pipe
log_info "Step 3/6: Setting up /srv/music/desktop.pipe FIFO buffer..."
sudo mkdir -p /srv/music
if [[ ! -p /srv/music/desktop.pipe ]]; then
    sudo rm -f /srv/music/desktop.pipe
    sudo mkfifo /srv/music/desktop.pipe
fi
sudo chmod 666 /srv/music/desktop.pipe
sudo chmod 777 /srv/music
log_success "FIFO pipe initialized."

# 4. Configure /etc/owntone.conf for Apple HomePods
log_info "Step 4/6: Configuring /etc/owntone.conf (AirPlay 2 user-agent & latency tuning)..."
if [[ -f /etc/owntone.conf ]]; then
    # Set User-Agent to official AirPlay to avoid HomePod 403 Forbidden errors
    if grep -q "user_agent =" /etc/owntone.conf; then
        sudo sed -i 's|.*user_agent =.*|\tuser_agent = "AirPlay/320.20"|g' /etc/owntone.conf
    else
        sudo sed -i '1i\tuser_agent = "AirPlay/320.20"' /etc/owntone.conf
    fi

    # Disable IPv6 if present to ensure reliable mDNS pairing
    if grep -q "ipv6 =" /etc/owntone.conf; then
        sudo sed -i 's|.*ipv6 =.*|\tipv6 = no|g' /etc/owntone.conf
    fi

    # Tune buffer for smooth, responsive streaming
    if grep -q "start_buffer_ms =" /etc/owntone.conf; then
        sudo sed -i 's|.*start_buffer_ms =.*|\tstart_buffer_ms = 650|g' /etc/owntone.conf
    fi

    # Disable local ALSA soundcard output to prevent double-audio echo
    sudo sed -i 's|#\ttype = "alsa"|\ttype = "disabled"|g' /etc/owntone.conf
fi
log_success "OwnTone configured."

# 5. Install & Enable User Bridge Service
log_info "Step 5/6: Setting up user background bridge service..."
mkdir -p "$HOME/.local/bin"
cat << 'BRIDGE' > "$HOME/.local/bin/homepod-bridge"
#!/bin/bash
PIPE="/srv/music/desktop.pipe"

while true; do
    # Ensure OwnTone has the live FIFO in queue and starts playing
    curl -s -X POST 'http://localhost:3689/api/queue/items/add?expression=path+is+"/srv/music/desktop.pipe"&playback=start' >/dev/null 2>&1

    # Stream clean 44.1kHz 16-bit PCM from HomePods monitor to pipe
    parec -d HomePods.monitor --rate=44100 --channels=2 --format=s16le > "$PIPE" 2>/dev/null

    sleep 1
done
BRIDGE
chmod +x "$HOME/.local/bin/homepod-bridge"

mkdir -p "$HOME/.config/systemd/user"
cat << 'SERVICE' > "$HOME/.config/systemd/user/homepod-bridge.service"
[Unit]
Description=HomePod PipeWire to AirPlay 2 Audio Bridge
After=pipewire.service pipewire-pulse.service owntone.service

[Service]
ExecStart=/home/%u/.local/bin/homepod-bridge
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
SERVICE

systemctl --user daemon-reload
systemctl --user enable --now homepod-bridge.service
log_success "Bridge service active."

# 6. Restart & Verify Services
log_info "Step 6/6: Starting system services..."
sudo systemctl enable --now avahi-daemon.service
sudo systemctl enable --now owntone.service
sudo systemctl restart owntone.service
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo ""
log_success "Setup complete! HomePods and AirPlay 2 multi-room streaming is now ready."
echo "${BOLD}You can now select any HomePod or room directly from the status bar AirPlay menu.${RESET}"
