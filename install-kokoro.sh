#!/bin/bash

# Complete idempotent Kokoro TTS installation with user systemd service
# This script can be run multiple times safely
# Uses user systemd service to access PulseAudio properly

set -e

echo "=== Installing Kokoro TTS (Complete Edition) ==="
echo ""

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "Error: This script is designed for Ubuntu/Debian systems"
    exit 1
fi

# Install system dependencies
echo "1. Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    espeak-ng \
    speech-dispatcher \
    git \
    build-essential \
    libsndfile1 \
    portaudio19-dev \
    python3-dev \
    wget

# Check if using PipeWire or PulseAudio
if command -v pipewire &> /dev/null; then
    echo "✓ Detected PipeWire (Pop!_OS default)"
    AUDIO_CMD="pw-play"
elif command -v pulseaudio &> /dev/null; then
    echo "✓ Detected PulseAudio"
    AUDIO_CMD="paplay"
else
    echo "⚠ No PipeWire or PulseAudio detected, using aplay"
    AUDIO_CMD="aplay -q"
fi

# Detect Python
if command -v pyenv &> /dev/null; then
    echo "✓ pyenv detected"
    PYTHON_BIN="$(pyenv which python3)"
    echo "  Using: $PYTHON_BIN"
else
    echo "✓ Using system python3"
    PYTHON_BIN="/usr/bin/python3"
fi

# Create installation directory
KOKORO_DIR="/opt/kokoro-tts"
echo ""
echo "2. Setting up installation directory..."

if [ -d "$KOKORO_DIR" ]; then
    echo "   Directory exists, will update existing installation"
else
    sudo mkdir -p "$KOKORO_DIR"
fi
sudo chown $USER:$USER "$KOKORO_DIR"

cd "$KOKORO_DIR"

# Create or update virtual environment
echo ""
echo "3. Setting up Python virtual environment..."
if [ -d "venv" ]; then
    echo "   Virtual environment exists, removing and recreating..."
    rm -rf venv
fi

$PYTHON_BIN -m venv venv
source venv/bin/activate

echo ""
echo "4. Installing Python packages..."
pip install --upgrade pip wheel
pip install kokoro-onnx soundfile numpy scipy

# Download Kokoro model files
echo ""
echo "5. Downloading Kokoro voice models..."
mkdir -p "$KOKORO_DIR/models"
cd "$KOKORO_DIR/models"

# Download voices.bin if not present
if [ -f "voices.bin" ]; then
    echo "   ✓ voices.bin already exists"
else
    echo "   Downloading voices.bin..."
    wget -q --show-progress \
        https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin \
        -O voices.bin
    echo "   ✓ voices.bin downloaded"
fi

# Download kokoro model if not present
if [ -f "kokoro-v1.0.onnx" ]; then
    echo "   ✓ kokoro-v1.0.onnx already exists"
else
    echo "   Downloading kokoro-v1.0.onnx (310MB)..."
    wget -q --show-progress \
        https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
    echo "   ✓ kokoro-v1.0.onnx downloaded"
fi

# Verify installation
echo ""
echo "6. Verifying installation..."
cd "$KOKORO_DIR"
source venv/bin/activate

python3 << 'PYEOF'
from kokoro_onnx import Kokoro
import soundfile as sf
print("✓ kokoro_onnx imported successfully")
print("✓ soundfile imported successfully")

# Test model loading
try:
    kokoro = Kokoro("/opt/kokoro-tts/models/kokoro-v1.0.onnx", "/opt/kokoro-tts/models/voices.bin")
    voices = list(kokoro.voices.keys())
    print(f"✓ Kokoro models loaded successfully")
    print(f"✓ Available voices: {', '.join(voices[:5])}...")
except Exception as e:
    print(f"✗ Failed to load Kokoro models: {e}")
    exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "✗ Installation verification failed"
    exit 1
fi

# Create the TTS server script
echo ""
echo "7. Creating TTS server script..."


if [ ! -f "kokoro-tts-server.py" ]; then
    echo "Error: kokoro-tts-server.py not found in current directory"
    exit 1
fi
cp -f kokoro-tts-server.py "$KOKORO_DIR/kokoro-tts-server.py"

chmod +x "$KOKORO_DIR/kokoro-tts-server.py"

# Create Speech Dispatcher module script
echo ""
echo "8. Creating Speech Dispatcher module..."

if [ ! -f "kokoro-speechd.sh" ]; then
    echo "Error: kokoro-speechd.sh not found in current directory"
    exit 1
fi
cp -f kokoro-speechd.sh "$KOKORO_DIR/kokoro-speechd.sh"

chmod +x "$KOKORO_DIR/kokoro-speechd.sh"

# Create user systemd service (runs in user session with PulseAudio access)
echo ""
echo "9. Creating user systemd service..."
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/kokoro-tts.service" << EOF
[Unit]
Description=Kokoro TTS Server
After=sound.target

[Service]
Type=simple
WorkingDirectory=$KOKORO_DIR
Environment="XDG_RUNTIME_DIR=/run/user/%U"
ExecStartPre=/bin/sh -c 'mkfifo -m 666 /tmp/kokoro-tts.fifo || true'
ExecStart=/bin/sh -c 'tail -f /tmp/kokoro-tts.fifo | $KOKORO_DIR/venv/bin/python3 $KOKORO_DIR/kokoro-tts-server.py'
ExecStopPost=/bin/rm -f /tmp/kokoro-tts.fifo
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Create Speech Dispatcher module config
echo ""
echo "10. Configuring Speech Dispatcher..."
sudo mkdir -p /etc/speech-dispatcher/modules

sudo tee /etc/speech-dispatcher/modules/kokoro.conf > /dev/null << EOF
# Kokoro TTS Module Configuration

GenericExecuteSynth \
"$KOKORO_DIR/kokoro-speechd.sh '\$DATA'"

GenericCmdDependency "bash"
GenericSoundIconFolder "/usr/share/sounds/sound-icons/"
GenericPunctNone ""
GenericPunctSome "--punct=\"()<>[]{}\""
GenericPunctMost "--punct=\"(){}[];:'\\\",.\""
GenericPunctAll "--punct"

AddVoice "en" "FEMALE1" "af_bella"
AddVoice "en" "MALE1"   "am_adam"
AddVoice "en" "FEMALE2" "af_sarah"
AddVoice "en" "FEMALE3" "af_sky"
AddVoice "en" "MALE2"   "am_michael"
AddVoice "en" "MALE3"   "am_liam"
EOF

# Update Speech Dispatcher main config
SPEECHD_CONF="/etc/speech-dispatcher/speechd.conf"

# Create backup if it doesn't exist
if [ ! -f "$SPEECHD_CONF.backup" ]; then
    sudo cp "$SPEECHD_CONF" "$SPEECHD_CONF.backup"
fi

# Remove any existing Kokoro references
sudo sed -i '/DefaultModule kokoro/d' "$SPEECHD_CONF"
sudo sed -i '/AddModule.*kokoro/d' "$SPEECHD_CONF"

# Add kokoro module if not present
if ! grep -q "AddModule.*kokoro" "$SPEECHD_CONF"; then
    echo 'AddModule "kokoro" "sd_generic" "kokoro.conf"' | sudo tee -a "$SPEECHD_CONF" > /dev/null
fi

# Comment out other DefaultModule lines and add kokoro
sudo sed -i 's/^DefaultModule/#DefaultModule/' "$SPEECHD_CONF"
if ! grep -q "^DefaultModule kokoro" "$SPEECHD_CONF"; then
    echo "DefaultModule kokoro" | sudo tee -a "$SPEECHD_CONF" > /dev/null
fi

# Enable and start user service
echo ""
echo "11. Starting Kokoro TTS service..."
systemctl --user daemon-reload
systemctl --user enable kokoro-tts
systemctl --user restart kokoro-tts

# Wait for service to start
sleep 3

# Check service status
if systemctl --user is-active --quiet kokoro-tts; then
    echo "✓ Kokoro TTS service is running"
else
    echo "✗ Kokoro TTS service failed to start"
    echo ""
    echo "Check logs with:"
    echo "  systemctl --user status kokoro-tts"
    echo "  journalctl --user -u kokoro-tts -n 50"
    echo "  tail -f ~/.cache/kokoro-tts/kokoro-tts.log"
    exit 1
fi

# Restart Speech Dispatcher
echo ""
echo "12. Restarting Speech Dispatcher..."
killall speech-dispatcher 2>/dev/null || true
rm -f /run/user/$(id -u)/speech-dispatcher/speechd.sock 2>/dev/null
sleep 1
speech-dispatcher &
sleep 2

# Create convenient test commands
echo ""
echo "13. Creating convenience commands..."
sudo tee /usr/local/bin/kokoro-say > /dev/null << 'EOF'
#!/bin/bash
# Convenient command to use Kokoro TTS
spd-say -o kokoro "$@"
EOF

sudo chmod +x /usr/local/bin/kokoro-say

# Create direct FIFO command
sudo tee /usr/local/bin/kokoro-direct > /dev/null << 'EOF'
#!/bin/bash
# Send text directly to Kokoro FIFO (bypassing Speech Dispatcher)
if [ -z "$1" ]; then
    echo "Usage: kokoro-direct <text>"
    exit 1
fi
echo "$1" > /tmp/kokoro-tts.fifo
EOF

sudo chmod +x /usr/local/bin/kokoro-direct

# Final test
echo ""
echo "14. Testing installation..."
sleep 2

echo "Testing direct FIFO..."
echo "Hello from Kokoro text to speech" > /tmp/kokoro-tts.fifo
sleep 2

echo ""
echo "Testing via Speech Dispatcher..."
spd-say -o kokoro "Testing Kokoro via Speech Dispatcher" 2>&1 || echo "  (Speech Dispatcher test - check if you heard audio)"

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "✓ Kokoro TTS installed and running as user systemd service"
echo "✓ Speech Dispatcher configured to use Kokoro by default"
echo "✓ Model files downloaded (voices.bin and kokoro-v1.0.onnx)"
echo ""
echo "Commands:"
echo "  spd-say 'Hello world'              # Uses Kokoro by default"
echo "  kokoro-say 'Hello world'           # Explicit Kokoro"
echo "  kokoro-direct 'Hello world'        # Direct FIFO (faster)"
echo "  spd-say -o espeak-ng 'text'        # Use espeak-ng instead"
echo ""
echo "Available voices:"
echo "  af_bella, af_sarah, af_sky (female)"
echo "  am_adam, am_michael, am_liam (male)"
echo ""
echo "Service management:"
echo "  systemctl --user status kokoro-tts"
echo "  systemctl --user restart kokoro-tts"
echo "  journalctl --user -u kokoro-tts -f"
echo ""
echo "Logs:"
echo "  ~/.cache/kokoro-tts/kokoro-tts.log"
echo ""
echo "To uninstall completely, run: ./purge.sh"
