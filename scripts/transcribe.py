"""Transcribe a 16 kHz mono 16-bit WAV file offline with Vosk.

Used by the bridge's transcribe_audio tool (bridge/customize.mjs): the browser
decodes whatever the user attached (mp3, m4a, ogg …) to plain 16 kHz samples,
the bridge writes them as a WAV, and this prints the words. Runs in the wake
listener's environment (%USERPROFILE%\\.jarvis\\wake-venv), which has Vosk and
the small Indian English model already — nothing leaves the machine.

    python transcribe.py file.wav    -> the transcript on stdout
"""

import json
import os
import sys
import wave
from pathlib import Path

from vosk import KaldiRecognizer, Model, SetLogLevel

_VOSK = Path(os.environ["USERPROFILE"]) / ".jarvis" / "vosk"
# The big Indian English model when installed (far more accurate), else the small one.
MODEL = next(
    (p for p in (_VOSK / "vosk-model-en-in-0.5", _VOSK / "vosk-model-small-en-in-0.4") if p.exists()),
    _VOSK / "vosk-model-small-en-in-0.4",
)


_WHISPER = Path(os.environ["USERPROFILE"]) / ".jarvis" / "whisper"


def whisper(path):
    """Whisper (faster-whisper, int8 on the CPU) when installed: it understands
    real speech far better than Vosk. base.en first (fast), else small.en.
    None when it is not installed or fails, so Vosk is used instead."""
    model_dir = next((p for p in (_WHISPER / "base.en", _WHISPER / "small.en") if (p / "model.bin").exists()), None)
    if not model_dir:
        return None
    try:
        from faster_whisper import WhisperModel

        model = WhisperModel(str(model_dir), device="cpu", compute_type="int8", cpu_threads=min(8, os.cpu_count() or 4))
        segs, _ = model.transcribe(path, language="en", beam_size=1, vad_filter=True, condition_on_previous_text=False)
        return " ".join(s.text.strip() for s in segs).strip()
    except Exception:
        return None


def main(path):
    SetLogLevel(-1)
    text = whisper(path)
    if text is not None:
        sys.stdout.reconfigure(encoding="utf-8")
        print(text)
        return
    if not MODEL.exists():
        sys.exit("The offline speech model is not installed (~/.jarvis/vosk).")
    with wave.open(path, "rb") as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2:
            sys.exit("Expected 16-bit mono audio.")
        rec = KaldiRecognizer(Model(str(MODEL)), wav.getframerate())
        parts = []
        while True:
            data = wav.readframes(8000)
            if not data:
                break
            if rec.AcceptWaveform(data):
                parts.append(json.loads(rec.Result()).get("text", ""))
        parts.append(json.loads(rec.FinalResult()).get("text", ""))
    sys.stdout.reconfigure(encoding="utf-8")
    print(" ".join(p for p in parts if p).strip())


if __name__ == "__main__":
    main(sys.argv[1])
