#!/bin/bash

# Complete purge of all Kokoro TTS installation files and configurations
# This script removes everything to allow a clean reinstallation

echo "=== Purging Kokoro TTS Installation ==="
echo ""

# Stop and disable systemd service
echo "1. Stopping and disabling Kokoro TTS service..."
systemctl --user stop kokoro-tts 2>/dev/null || true
systemctl --user disable kokoro-tts 2>/dev/null || true
sudo systemctl stop kokoro-tts 2>/dev/null || true
sudo systemctl disable kokoro-tts 2>/dev/null || true

# Stop Speech Dispatcher
echo "2. Stopping Speech Dispatcher..."
killall speech-dispatcher 2>/dev/null || true
sudo systemctl stop speech-dispatcher 2>/dev/null || true

# Remove systemd service files
echo "3. Removing systemd service files..."
if [ -f "$HOME/.config/systemd/user/kokoro-tts.service" ]; then
    rm -f "$HOME/.config/systemd/user/kokoro-tts.service"
    systemctl --user daemon-reload
fi
if [ -f "/etc/systemd/system/kokoro-tts.service" ]; then
    sudo rm -f /etc/systemd/system/kokoro-tts.service
    sudo systemctl daemon-reload
fi

# Remove FIFO pipe
echo "4. Removing FIFO pipe..."
rm -f /tmp/kokoro-tts.fifo
sudo rm -f /tmp/kokoro-tts.fifo

# Remove Kokoro installation directory (including models)
if [ -d "/opt/kokoro-tts" ]; then
    echo "5. Removing /opt/kokoro-tts (including all models)..."
    sudo rm -rf /opt/kokoro-tts
fi

# Remove Speech Dispatcher module configuration
if [ -f "/etc/speech-dispatcher/modules/kokoro.conf" ]; then
    echo "6. Removing Kokoro Speech Dispatcher module configuration..."
    sudo rm -f /etc/speech-dispatcher/modules/kokoro.conf
fi

# Restore Speech Dispatcher main config
SPEECHD_CONF="/etc/speech-dispatcher/speechd.conf"
echo "7. Cleaning up Speech Dispatcher configuration..."

if [ -f "$SPEECHD_CONF" ]; then
    # Remove all Kokoro references
    sudo sed -i '/DefaultModule kokoro/d' "$SPEECHD_CONF"
    sudo sed -i '/AddModule.*kokoro/d' "$SPEECHD_CONF"
    
    # Uncomment any commented DefaultModule lines
    sudo sed -i 's/^#DefaultModule espeak-ng/DefaultModule espeak-ng/' "$SPEECHD_CONF"
    
    # Remove all backup files
    sudo rm -f "$SPEECHD_CONF.backup"*
fi

# Remove helper scripts
echo "8. Removing helper scripts..."
sudo rm -f /usr/local/bin/speak-kokoro
sudo rm -f /usr/local/bin/say
sudo rm -f /usr/local/bin/kokoro-say
sudo rm -f /usr/local/bin/kokoro-direct

# Remove user test files
echo "9. Removing user test files..."
rm -f "$HOME/kokoro_test.py"
rm -f "$HOME/kokoro_activate.sh"

# Clean up logs
if [ -d "$HOME/.cache/kokoro-tts" ]; then
    echo "10. Removing Kokoro TTS logs..."
    rm -rf "$HOME/.cache/kokoro-tts"
fi

# Clean up Speech Dispatcher socket
rm -f /run/user/$(id -u)/speech-dispatcher/speechd.sock 2>/dev/null

echo ""
echo "=== Purge Complete ==="
echo ""
echo "All Kokoro TTS files, models, configurations, and services have been removed."
echo ""
echo "To reinstall, run: ./install-kokoro.sh"
