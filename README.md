# Kokoro TTS for Debian/Ubuntu

Complete installation scripts for [Kokoro TTS](https://github.com/nazdridoy/kokoro-tts) with Speech Dispatcher integration on Debian-based Linux systems.

Kokoro is a high-quality, open-weight text-to-speech model with 82 million parameters that delivers natural-sounding speech in multiple languages.

## Features

- **54 voices** across multiple languages (English, Japanese, Chinese, French, Hindi, Italian, Portuguese, Spanish)
- **Speech Dispatcher integration** - works system-wide with screen readers and accessibility tools
- **Fast generation** - near real-time on modern hardware
- **User systemd service** - auto-starts on login with proper audio access
- **PipeWire & PulseAudio support** - works on Pop!_OS, Ubuntu, and other Debian derivatives
- **Idempotent installation** - safe to run multiple times

## Prerequisites

- Ubuntu 22.04+, Debian 11+, Pop!_OS 22.04+, or similar
- ~500MB disk space for models and dependencies
- Python 3.10+
- Audio system (PipeWire, PulseAudio, or ALSA)

## Quick Start

```bash
git clone https://github.com/allen-munsch/kokoro-debian-tts.git
cd kokoro-debian-tts
chmod +x install-kokoro.sh
./install-kokoro.sh
```

The installation will:
1. Install system dependencies (espeak-ng, speech-dispatcher, etc.)
2. Create Python virtual environment
3. Download Kokoro models (~340MB)
4. Set up user systemd service
5. Configure Speech Dispatcher
6. Test the installation

## Usage

### Basic Commands

```bash
# Default (uses Kokoro via Speech Dispatcher)
spd-say "Hello world"

# Explicit Kokoro
kokoro-say "Testing Kokoro"

# Direct FIFO (fastest, bypasses Speech Dispatcher)
kokoro-direct "Quick test"

# Use espeak-ng instead
spd-say -o espeak-ng "Testing espeak"
```

### Available Voices

English voices include:
- **Female**: `af_bella`, `af_sarah`, `af_sky`, `af_nicole`, `af_alloy`
- **Male**: `am_adam`, `am_michael`, `am_liam`, `am_eric`
- **British Female**: `bf_emma`, `bf_alice`, `bf_isabella`
- **British Male**: `bm_george`, `bm_lewis`, `bm_daniel`

Other languages: French (`ff_siwis`), Japanese (`jf_*`, `jm_*`), Chinese (`zf_*`, `zm_*`), Hindi (`hf_*`, `hm_*`), and more.

To use a specific voice:
```bash
echo "VOICE:af_sarah" > /tmp/kokoro-tts.fifo
echo "Hello with Sarah's voice" > /tmp/kokoro-tts.fifo
```

### Service Management

```bash
# Check status
systemctl --user status kokoro-tts

# Restart service
systemctl --user restart kokoro-tts

# View logs
journalctl --user -u kokoro-tts -f

# Application log
tail -f ~/.cache/kokoro-tts/kokoro-tts.log
```

## Troubleshooting

### Run the debug script

```bash
./debug-tts.sh
```

This comprehensive script checks:
- Speech Dispatcher status
- Systemd service status
- Audio system configuration
- Model files
- FIFO pipe communication
- Direct TTS generation

### Common Issues

**No audio output:**
```bash
# Check if service is running
systemctl --user status kokoro-tts

# Test audio system
speaker-test -t wav -c 2

# Restart everything
systemctl --user restart kokoro-tts
killall speech-dispatcher
speech-dispatcher &
```

**Speech Dispatcher socket errors:**
```bash
killall speech-dispatcher
rm -f /run/user/$(id -u)/speech-dispatcher/speechd.sock
speech-dispatcher &
```

**PulseAudio connection refused (on PipeWire systems):**
- The updated install script detects PipeWire and uses `pw-play` automatically
- If issues persist, check: `systemctl --user status pipewire pipewire-pulse`

**Service fails to start:**
```bash
# Check logs for errors
journalctl --user -u kokoro-tts -n 50
tail -f ~/.cache/kokoro-tts/kokoro-tts.log
```

## Uninstallation

```bash
./purge.sh
```

This removes:
- All Kokoro files and models
- Systemd service
- Speech Dispatcher configuration
- Helper scripts
- Logs

## Architecture

**Components:**
- **kokoro-tts-server.py** - Python daemon that generates speech
- **User systemd service** - Manages the TTS server lifecycle
- **FIFO pipe** (`/tmp/kokoro-tts.fifo`) - Fast IPC mechanism
- **Speech Dispatcher module** - System-wide TTS integration
- **Helper scripts** - Convenient command-line tools

**Audio pipeline:**
```
Text input → FIFO pipe → Kokoro server → Audio generation → 
pw-play/paplay/aplay → Audio output
```

**Files installed:**
- `/opt/kokoro-tts/` - Installation directory (models, venv, scripts)
- `~/.config/systemd/user/kokoro-tts.service` - User service
- `/etc/speech-dispatcher/modules/kokoro.conf` - Speech Dispatcher module
- `/usr/local/bin/{kokoro-say,kokoro-direct}` - Helper commands
- `~/.cache/kokoro-tts/kokoro-tts.log` - Application log

## Requirements

**System packages:**
- espeak-ng
- speech-dispatcher
- build-essential
- libsndfile1
- portaudio19-dev
- python3-dev

**Python packages (in venv):**
- kokoro-onnx
- soundfile
- numpy
- scipy

## Credits

- [Kokoro-82M](https://github.com/nazdridoy/kokoro-tts) - The TTS model
- [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) - ONNX runtime wrapper
- Speech Dispatcher - System TTS framework

## License

MIT License - see LICENSE file for details

The Kokoro model weights are licensed under Apache 2.0.
