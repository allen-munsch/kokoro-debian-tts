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
cat > "$KOKORO_DIR/kokoro-tts-server.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Kokoro TTS Server - handles TTS requests via stdin
This runs as a daemon and processes text-to-speech requests
"""
import sys
import os
import tempfile
import subprocess
import signal
import logging
from pathlib import Path

# Setup logging
log_dir = Path.home() / ".cache" / "kokoro-tts"
log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    filename=log_dir / "kokoro-tts.log",
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Import and initialize Kokoro
try:
    from kokoro_onnx import Kokoro
    import soundfile as sf
    import numpy as np
    logging.info("Kokoro TTS Server starting...")
    
    # Initialize Kokoro with full paths to model files
    kokoro = Kokoro(
        "/opt/kokoro-tts/models/kokoro-v1.0.onnx",
        "/opt/kokoro-tts/models/voices.bin"
    )
    
    # Get available voices
    available_voices = list(kokoro.voices.keys())
    logging.info(f"Available voices: {available_voices}")
    
    # Use af_bella as default (nice female voice)
    default_voice = "af_bella"
    logging.info(f"Kokoro initialized successfully with default voice: {default_voice}")
    
except Exception as e:
    logging.error(f"Failed to initialize Kokoro: {e}")
    sys.exit(1)

class KokoroTTSServer:
    def __init__(self):
        self.voice = default_voice
        self.speed = 1.0
        self.running = True
        self.kokoro = kokoro
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self.handle_shutdown)
        signal.signal(signal.SIGINT, self.handle_shutdown)
    
    def handle_shutdown(self, signum, frame):
        logging.info("Received shutdown signal")
        self.running = False
        sys.exit(0)
    
    def speak(self, text):
        """Generate and play speech"""
        try:
            logging.info(f"Generating speech with voice '{self.voice}': {text[:50]}...")
            
            # Generate audio using kokoro_onnx API
            samples, sample_rate = self.kokoro.create(
                text,
                voice=self.voice,
                speed=self.speed
            )
            
            # Convert to numpy array if needed
            if not isinstance(samples, np.ndarray):
                samples = np.array(samples)
            
            # Save to temporary file
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, samples, sample_rate)
                tmp_path = tmp.name
            
            # Play audio - detect audio system
            audio_players = [
                (["pw-play", tmp_path], "pw-play"),
                (["paplay", tmp_path], "paplay"),
                (["aplay", "-q", tmp_path], "aplay")
            ]
            
            result = None
            for cmd, name in audio_players:
                try:
                    result = subprocess.run(cmd, capture_output=True, timeout=10)
                    if result.returncode == 0:
                        break
                except (FileNotFoundError, subprocess.TimeoutExpired):
                    continue
            
            # Clean up
            os.unlink(tmp_path)
            
            if result.returncode == 0:
                logging.info("Speech completed successfully")
                return True
            else:
                logging.error(f"paplay failed: {result.stderr.decode()}")
                return False
                
        except Exception as e:
            logging.error(f"Error generating speech: {e}", exc_info=True)
            return False
    
    def run(self):
        """Main server loop - process requests from stdin"""
        logging.info("Server ready, waiting for requests...")
        
        while self.running:
            try:
                # Read line from stdin
                line = sys.stdin.readline()
                if not line:
                    # EOF reached
                    break
                
                line = line.strip()
                if not line:
                    continue
                
                # Process command
                if line.startswith("SPEAK:"):
                    text = line[6:].strip()
                    self.speak(text)
                    print("OK", flush=True)
                elif line.startswith("VOICE:"):
                    new_voice = line[6:].strip()
                    if new_voice in self.kokoro.voices:
                        self.voice = new_voice
                        logging.info(f"Voice changed to: {self.voice}")
                        print("OK", flush=True)
                    else:
                        logging.warning(f"Voice '{new_voice}' not available, keeping '{self.voice}'")
                        print("ERROR", flush=True)
                elif line.startswith("SPEED:"):
                    self.speed = float(line[6:].strip())
                    logging.info(f"Speed changed to: {self.speed}")
                    print("OK", flush=True)
                elif line == "QUIT":
                    logging.info("Quit command received")
                    break
                else:
                    # Default: just speak the line
                    self.speak(line)
                    print("OK", flush=True)
                    
            except Exception as e:
                logging.error(f"Error processing request: {e}", exc_info=True)
                print("ERROR", flush=True)
        
        logging.info("Server shutting down")

if __name__ == "__main__":
    server = KokoroTTSServer()
    server.run()
PYEOF

chmod +x "$KOKORO_DIR/kokoro-tts-server.py"

# Create Speech Dispatcher module script
echo ""
echo "8. Creating Speech Dispatcher module..."
cat > "$KOKORO_DIR/kokoro-speechd.sh" << 'SHEOF'
#!/bin/bash
# Speech Dispatcher interface for Kokoro TTS
# This script communicates with the Kokoro TTS server

KOKORO_FIFO="/tmp/kokoro-tts.fifo"

# Check if server is running
if [ ! -p "$KOKORO_FIFO" ]; then
    echo "Error: Kokoro TTS server not running" >&2
    exit 1
fi

# Send text to server
if [ -n "$1" ]; then
    echo "$1" > "$KOKORO_FIFO" 2>/dev/null || {
        echo "Error: Failed to communicate with Kokoro TTS server" >&2
        exit 1
    }
fi

exit 0
SHEOF

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
