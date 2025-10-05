#!/bin/bash

# Comprehensive debug script for Kokoro TTS installation
# This will help identify exactly what's wrong

echo "=== Kokoro TTS Comprehensive Debug Script ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Check Speech Dispatcher installation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. SPEECH DISPATCHER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v spd-say &> /dev/null; then
    print_status 0 "spd-say command found: $(which spd-say)"
else
    print_status 1 "spd-say command NOT found"
fi

# Check if Speech Dispatcher is running
if pgrep -x "speech-dispatcher" > /dev/null; then
    PID=$(pgrep -x speech-dispatcher)
    print_status 0 "Speech Dispatcher is running (PID: $PID)"
else
    print_status 1 "Speech Dispatcher is NOT running"
    print_info "Start with: speech-dispatcher &"
fi

# List available output modules
echo ""
echo "Available Speech Dispatcher modules:"
spd-say -O 2>/dev/null || echo "  Could not list modules (Speech Dispatcher not running?)"

# 2. Check espeak-ng
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. ESPEAK-NG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v espeak-ng &> /dev/null; then
    print_status 0 "espeak-ng found: $(espeak-ng --version | head -n1)"
else
    print_status 1 "espeak-ng NOT found"
fi

# 3. Check Kokoro systemd service
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. KOKORO SYSTEMD SERVICE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for user service first
if [ -f "$HOME/.config/systemd/user/kokoro-tts.service" ]; then
    print_status 0 "User service file exists"
    
    if systemctl --user is-active --quiet kokoro-tts; then
        print_status 0 "User service is active"
    else
        print_status 1 "User service is NOT active"
    fi
    
    if systemctl --user is-enabled --quiet kokoro-tts; then
        print_status 0 "User service is enabled"
    else
        print_status 1 "User service is NOT enabled"
    fi
    
    echo ""
    echo "User service status:"
    systemctl --user status kokoro-tts --no-pager -l
    
    echo ""
    echo "Recent user service logs (last 20 lines):"
    journalctl --user -u kokoro-tts -n 20 --no-pager
    
elif [ -f "/etc/systemd/system/kokoro-tts.service" ]; then
    print_status 0 "System service file exists"
    
    if sudo systemctl is-active --quiet kokoro-tts; then
        print_status 0 "System service is active"
    else
        print_status 1 "System service is NOT active"
    fi
    
    if sudo systemctl is-enabled --quiet kokoro-tts; then
        print_status 0 "System service is enabled"
    else
        print_status 1 "System service is NOT enabled"
    fi
    
    echo ""
    echo "System service status:"
    sudo systemctl status kokoro-tts --no-pager -l
    
    echo ""
    echo "Recent system service logs (last 20 lines):"
    sudo journalctl -u kokoro-tts -n 20 --no-pager
else
    print_status 1 "Service file NOT found (checked both user and system)"
fi

# 4. Check FIFO pipe
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. FIFO PIPE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -p "/tmp/kokoro-tts.fifo" ]; then
    print_status 0 "FIFO pipe exists: /tmp/kokoro-tts.fifo"
    ls -l /tmp/kokoro-tts.fifo
else
    print_status 1 "FIFO pipe NOT found at /tmp/kokoro-tts.fifo"
    print_info "Service should create this automatically"
fi

# 5. Check Kokoro installation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. KOKORO INSTALLATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "/opt/kokoro-tts" ]; then
    print_status 0 "Installation directory exists: /opt/kokoro-tts"
    
    # Check virtual environment
    if [ -f "/opt/kokoro-tts/venv/bin/python3" ]; then
        print_status 0 "Virtual environment exists"
        VENV_PYTHON="/opt/kokoro-tts/venv/bin/python3"
        print_info "Python: $($VENV_PYTHON --version)"
        
        # Test kokoro_onnx import
        echo ""
        echo "Testing Python imports in venv:"
        $VENV_PYTHON -c "
import sys
try:
    from kokoro_onnx import Kokoro
    print('  ✓ kokoro_onnx')
except ImportError as e:
    print(f'  ✗ kokoro_onnx: {e}')
    sys.exit(1)

try:
    import soundfile
    print('  ✓ soundfile')
except ImportError as e:
    print(f'  ✗ soundfile: {e}')
    sys.exit(1)

try:
    import numpy
    print('  ✓ numpy')
except ImportError as e:
    print(f'  ✗ numpy: {e}')
    sys.exit(1)
"
        if [ $? -eq 0 ]; then
            print_status 0 "All Python dependencies OK"
        else
            print_status 1 "Python dependencies have errors"
        fi
    else
        print_status 1 "Virtual environment NOT found"
    fi
    
    # Check server script
    echo ""
    if [ -f "/opt/kokoro-tts/kokoro-tts-server.py" ]; then
        print_status 0 "Server script exists"
        print_info "$(ls -lh /opt/kokoro-tts/kokoro-tts-server.py)"
    else
        print_status 1 "Server script NOT found"
    fi
    
    # Check Speech Dispatcher wrapper
    if [ -f "/opt/kokoro-tts/kokoro-speechd.sh" ]; then
        print_status 0 "Speech Dispatcher wrapper exists"
        print_info "$(ls -lh /opt/kokoro-tts/kokoro-speechd.sh)"
    else
        print_status 1 "Speech Dispatcher wrapper NOT found"
    fi
    
    # Check model files
    echo ""
    echo "Model files:"
    if [ -f "/opt/kokoro-tts/models/voices.bin" ]; then
        print_status 0 "voices.bin exists ($(du -h /opt/kokoro-tts/models/voices.bin | cut -f1))"
    else
        print_status 1 "voices.bin NOT found"
    fi
    
    if [ -f "/opt/kokoro-tts/models/kokoro-v1.0.onnx" ]; then
        print_status 0 "kokoro-v1.0.onnx exists ($(du -h /opt/kokoro-tts/models/kokoro-v1.0.onnx | cut -f1))"
    else
        print_status 1 "kokoro-v1.0.onnx NOT found"
    fi
    
    # Test model loading
    if [ -f "/opt/kokoro-tts/models/voices.bin" ] && [ -f "/opt/kokoro-tts/models/kokoro-v1.0.onnx" ]; then
        echo ""
        echo "Testing model loading:"
        $VENV_PYTHON << 'PYEOF'
try:
    from kokoro_onnx import Kokoro
    kokoro = Kokoro(
        "/opt/kokoro-tts/models/kokoro-v1.0.onnx",
        "/opt/kokoro-tts/models/voices.bin"
    )
    print("  ✓ Models loaded successfully")
except Exception as e:
    print(f"  ✗ Failed to load models: {e}")
    exit(1)
PYEOF
        if [ $? -eq 0 ]; then
            print_status 0 "Model loading works"
        else
            print_status 1 "Model loading failed"
        fi
    fi
else
    print_status 1 "Installation directory NOT found"
fi

# 6. Check Speech Dispatcher configuration
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. SPEECH DISPATCHER CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SPEECHD_CONF="/etc/speech-dispatcher/speechd.conf"
if [ -f "$SPEECHD_CONF" ]; then
    print_status 0 "speechd.conf exists"
    
    echo ""
    echo "DefaultModule setting:"
    grep "^DefaultModule" "$SPEECHD_CONF" || echo "  (No DefaultModule set)"
    
    echo ""
    echo "Kokoro module references:"
    grep -i "kokoro" "$SPEECHD_CONF" || echo "  (No kokoro references found)"
else
    print_status 1 "speechd.conf NOT found"
fi

echo ""
if [ -f "/etc/speech-dispatcher/modules/kokoro.conf" ]; then
    print_status 0 "Kokoro module config exists"
    echo ""
    echo "Module configuration:"
    head -20 /etc/speech-dispatcher/modules/kokoro.conf
else
    print_status 1 "Kokoro module config NOT found"
fi

# 7. Check audio system
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. AUDIO SYSTEM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v aplay &> /dev/null; then
    print_status 0 "aplay found"
    echo ""
    echo "Audio devices:"
    aplay -l 2>&1 | grep "^card" || echo "  No audio devices found"
else
    print_status 1 "aplay NOT found"
fi

if command -v pactl &> /dev/null; then
    if pactl info &> /dev/null; then
        print_status 0 "PulseAudio is running"
    else
        print_status 1 "PulseAudio is NOT running"
    fi
else
    print_warning "PulseAudio not found (might be using ALSA or PipeWire)"
fi

# 8. Test Kokoro server directly
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. DIRECT SERVER TEST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "/opt/kokoro-tts/kokoro-tts-server.py" ] && [ -f "/opt/kokoro-tts/venv/bin/python3" ]; then
    echo "Testing server script directly (without FIFO):"
    echo "This will generate audio and try to play it..."
    echo ""
    
    timeout 10s /opt/kokoro-tts/venv/bin/python3 << 'PYEOF' 2>&1 | head -30
import sys
sys.path.insert(0, '/opt/kokoro-tts')

try:
    print("Importing modules...")
    from kokoro_onnx import Kokoro
    import soundfile as sf
    import numpy as np
    import tempfile
    import subprocess
    import os
    
    print("Loading models...")
    kokoro = Kokoro(
        "/opt/kokoro-tts/models/kokoro-v1.0.onnx",
        "/opt/kokoro-tts/models/voices.bin"
    )
    
    print("Generating speech...")
    samples, sample_rate = kokoro.create("Testing direct server", voice="af", speed=1.0)
    
    print(f"Generated {len(samples)} samples at {sample_rate}Hz")
    
    # Save and play
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        sf.write(tmp.name, samples, sample_rate)
        tmp_path = tmp.name
    
    print(f"Saved to: {tmp_path}")
    print("Playing audio...")
    result = subprocess.run(["aplay", "-q", tmp_path], capture_output=True)
    
    os.unlink(tmp_path)
    
    if result.returncode == 0:
        print("✓ SUCCESS: Audio played")
    else:
        print(f"✗ FAILED: {result.stderr.decode()}")
        
except Exception as e:
    print(f"✗ ERROR: {e}")
    import traceback
    traceback.print_exc()
PYEOF
    
    if [ $? -eq 0 ]; then
        print_status 0 "Direct server test succeeded"
    else
        print_status 1 "Direct server test failed"
    fi
fi

# 9. Test FIFO communication
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. FIFO COMMUNICATION TEST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -p "/tmp/kokoro-tts.fifo" ]; then
    echo "Testing FIFO communication..."
    echo "Sending test message to FIFO (this should produce audio)..."
    
    (echo "Direct FIFO test" > /tmp/kokoro-tts.fifo) &
    FIFO_PID=$!
    sleep 2
    
    if ps -p $FIFO_PID > /dev/null 2>&1; then
        print_warning "FIFO write is hanging (server might not be reading)"
        kill $FIFO_PID 2>/dev/null
    else
        print_status 0 "FIFO communication completed"
    fi
else
    print_status 1 "FIFO not available for testing"
fi

# 10. Test Speech Dispatcher
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10. SPEECH DISPATCHER TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if pgrep -x "speech-dispatcher" > /dev/null; then
    echo "Testing espeak-ng via Speech Dispatcher..."
    spd-say -o espeak-ng "Testing espeak" 2>&1
    print_status $? "espeak-ng test"
    
    echo ""
    echo "Testing Kokoro via Speech Dispatcher..."
    spd-say -o kokoro "Testing Kokoro" 2>&1
    print_status $? "Kokoro test"
    
    echo ""
    echo "Testing default module..."
    spd-say "Testing default module" 2>&1
    print_status $? "Default module test"
else
    print_warning "Speech Dispatcher not running, skipping tests"
fi

# 11. Check logs
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "11. LOGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$HOME/.cache/kokoro-tts/kokoro-tts.log" ]; then
    print_status 0 "Kokoro log exists"
    echo ""
    echo "Last 15 lines of Kokoro log:"
    tail -15 "$HOME/.cache/kokoro-tts/kokoro-tts.log"
else
    print_status 1 "Kokoro log NOT found at $HOME/.cache/kokoro-tts/kokoro-tts.log"
fi

echo ""
if [ -d "$HOME/.cache/speech-dispatcher/log" ]; then
    print_status 0 "Speech Dispatcher log directory exists"
    echo ""
    echo "Recent Speech Dispatcher logs:"
    ls -lth "$HOME/.cache/speech-dispatcher/log/" | head -5
else
    print_status 1 "Speech Dispatcher log directory NOT found"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY & NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check critical components
CRITICAL_OK=true

# Check if service is running (either user or system)
SERVICE_RUNNING=false
if systemctl --user is-active --quiet kokoro-tts 2>/dev/null; then
    SERVICE_RUNNING=true
elif sudo systemctl is-active --quiet kokoro-tts 2>/dev/null; then
    SERVICE_RUNNING=true
fi

if ! $SERVICE_RUNNING; then
    echo "❌ Kokoro service is not running"
    echo "   Fix: systemctl --user start kokoro-tts"
    CRITICAL_OK=false
fi

if [ ! -p "/tmp/kokoro-tts.fifo" ]; then
    echo "❌ FIFO pipe missing"
    echo "   Fix: sudo systemctl restart kokoro-tts"
    CRITICAL_OK=false
fi

if [ ! -f "/opt/kokoro-tts/models/kokoro-v1.0.onnx" ] || [ ! -f "/opt/kokoro-tts/models/voices.bin" ]; then
    echo "❌ Model files missing"
    echo "   Fix: Re-run ./install-kokoro.sh"
    CRITICAL_OK=false
fi

if ! pgrep -x "speech-dispatcher" > /dev/null; then
    echo "❌ Speech Dispatcher not running"
    echo "   Fix: speech-dispatcher &"
    CRITICAL_OK=false
fi

if $CRITICAL_OK; then
    echo "✅ All critical components appear to be working"
    echo ""
    echo "If you still have issues:"
    echo "  1. Check live logs: sudo journalctl -u kokoro-tts -f"
    echo "  2. Check Kokoro log: tail -f ~/.cache/kokoro-tts/kokoro-tts.log"
    echo "  3. Try manual Speech Dispatcher: killall speech-dispatcher && speech-dispatcher -D"
fi

echo ""
echo "=== END DEBUG REPORT ==="
