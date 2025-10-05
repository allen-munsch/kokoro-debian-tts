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