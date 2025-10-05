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