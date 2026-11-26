"""JARVIS wake listener.

A small, always-on, offline listener for "Hey Jarvis" that runs even while
JARVIS is off. When it hears the phrase it starts JARVIS (or just reopens his
window if the brain is already running), and JARVIS greets you and listens.

Detection is openWakeWord's pre-trained "hey jarvis" model: offline, free, a
few percent of one CPU core, and fast — it spots the phrase within a fraction
of a second, where the page's own recogniser has to transcribe it first. So it
stays on while JARVIS runs too: with a window open it signals it through the
bridge (POST /wake) and he chimes and listens at once, like "Hey Google".

Started and stopped by the "JARVIS - ON / OFF" switch on the desktop
(scripts/jarvis-switch.ps1) — nothing starts it with Windows — using the
isolated Python environment in %USERPROFILE%\\.jarvis\\wake-venv.
Log: %USERPROFILE%\\.jarvis\\wake-listener.log

    --threshold 0.15  how sure the model must be (0..1): raise it if JARVIS
                      starts by mistake, lower it if it misses you. Measured
                      on this PC: "Hey Jarvis" scored about 0.19-0.20, other
                      speech and silence 0.000-0.001.
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import threading
import time
import urllib.request
from collections import deque
from pathlib import Path

import numpy as np
import sounddevice as sd
from openwakeword.model import Model
from openwakeword.utils import download_models

ROOT = Path(__file__).resolve().parent.parent
BAT = ROOT / "start-jarvis.bat"
HOME = Path(os.environ["USERPROFILE"]) / ".jarvis"
HOME.mkdir(parents=True, exist_ok=True)
# Present while the desktop kill switch is OFF.
KILL_SWITCH = HOME / "disabled"
# Present while the microphone is muted from the onscreen popup: same effect
# as the kill switch for listening, but JARVIS himself stays running.
MUTED = HOME / "muted"

logging.basicConfig(
    filename=HOME / "wake-listener.log",
    level=logging.INFO,
    format="%(asctime)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.info

RATE = 16_000
CHUNK = 1280  # 80 ms, the frame size openWakeWord expects
NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW


REMINDERS = HOME / "reminders.json"

# A Windows notification that stays until dismissed (as bridge/assistant.mjs).
TOAST_PS = r"""
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
function X($s) { [Security.SecurityElement]::Escape($s) }
$doc = "<toast scenario='reminder'><visual><binding template='ToastGeneric'><text>$(X $env:JARVIS_T)</text><text>$(X $env:JARVIS_B)</text></binding></visual><actions><action content='Dismiss' arguments='dismiss' activationType='system'/></actions><audio src='ms-winsoundevent:Notification.Reminder'/></toast>"
$x = New-Object Windows.Data.Xml.Dom.XmlDocument; $x.LoadXml($doc)
$id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($x))
"""


def toast(title, body):
    env = dict(os.environ, JARVIS_T=title, JARVIS_B=body)
    subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", TOAST_PS],
        env=env, creationflags=NO_WINDOW, timeout=20, check=False,
    )


PAST = HOME / "past-events.json"


def archive_event(r):
    """Keep a fired reminder for the calendar (as bridge/assistant.mjs does)."""
    try:
        past = json.loads(PAST.read_text(encoding="utf-8"))
        if not isinstance(past, list):
            past = []
    except (OSError, ValueError):
        past = []
    past.append({"id": r.get("id"), "at": r.get("at"), "text": r.get("text", ""), "kind": r.get("kind")})
    tmp = PAST.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(past[-500:], indent=2), encoding="utf-8")
    os.replace(tmp, PAST)


def fire_due_reminders():
    """While JARVIS is off: show due reminders and timers, and move repeating
    ones to their next time — the same bookkeeping the bridge does. Scheduled
    WhatsApp messages are left for the bridge, which sends them when it starts
    (if they are not hours late)."""
    from datetime import datetime, timedelta, timezone

    try:
        items = json.loads(REMINDERS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return
    if not isinstance(items, list):
        return
    now = datetime.now(timezone.utc)
    keep, fired = [], 0
    for r in items:
        try:
            at = datetime.fromisoformat(str(r.get("at", "")).replace("Z", "+00:00"))
            if at.tzinfo is None:
                at = at.astimezone()
        except ValueError:
            keep.append(r)
            continue
        if at > now or r.get("kind") == "whatsapp":
            keep.append(r)
            continue
        late = now - at
        note = f" (due {at.astimezone():%I:%M %p})" if late > timedelta(minutes=5) else ""
        title = "Jarvis timer" if r.get("kind") == "timer" else "Jarvis reminder"
        toast(title, f"{r.get('text', '')}{note}")
        fired += 1
        if r.get("kind") != "timer":
            archive_event(r)
        step = {"daily": 1, "weekly": 7}.get(r.get("repeat") or "", 0)
        if step:
            while at <= now:
                at += timedelta(days=step)
            keep.append({**r, "at": at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")})
    if fired:
        tmp = REMINDERS.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(keep, indent=2), encoding="utf-8")
        os.replace(tmp, REMINDERS)
        log(f"showed {fired} reminder(s) while JARVIS was off")


def single_instance():
    """Exit quietly if another listener already holds the lock."""
    import ctypes

    ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\JarvisWakeListener")
    if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        sys.exit(0)


def bridge():
    """(bridge up, JARVIS windows connected)."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:8787/health", timeout=1) as r:
            return True, int(json.load(r).get("clients", 0))
    except Exception:
        return False, 0




def wake_window():
    """Tell the open JARVIS window to listen now. True if one was there."""
    try:
        # The bridge's local key, made fresh at each start (bridge/server.mjs).
        try:
            token = (HOME / "bridge-token").read_text().strip()
        except OSError:
            token = ""
        req = urllib.request.Request(
            "http://127.0.0.1:8787/wake", data=b"", method="POST",
            headers={"x-jarvis-token": token},
        )
        with urllib.request.urlopen(req, timeout=1) as r:
            return int(json.load(r).get("clients", 0)) > 0
    except Exception:
        return False


PENDING = HOME / "pending-command.json"


def brain_mode():
    """The bridge's brain: "cloud", "local" (offline, on Ollama) or "none"; None if down."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:8787/health", timeout=1) as r:
            return json.load(r).get("brain")
    except Exception:
        return None


def ask_bridge(text):
    """Hand a request straight to JARVIS, as if typed in the popup."""
    try:
        try:
            token = (HOME / "bridge-token").read_text().strip()
        except OSError:
            token = ""
        req = urllib.request.Request(
            "http://127.0.0.1:8787/popup/ask", data=json.dumps({"text": text}).encode("utf-8"),
            method="POST", headers={"x-jarvis-token": token, "content-type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=3) as r:
            return int(json.load(r).get("sent", 0)) > 0
    except Exception:
        return False


LISTEN_NOW = HOME / "listen-now"
CAPTURE = {"loudest": 0}  # how loud the last capture got, for the log
OFFLINE = {"on": False}  # the bridge is on the local model (checked every 3 s)

# The big Indian English model (about 1 GB): far more accurate for commands
# than the small one, but too heavy to keep listening with all the time. The
# small model keeps listening for "Hey Jarvis"; this one only transcribes the
# command, offline. Loaded in the background the first time JARVIS goes
# offline (takes a while), so nothing is ever waiting on it.
BIG_DIR = HOME / "vosk" / "vosk-model-en-in-0.5"
BIG = {"model": None, "loading": False}


def load_big_model():
    import threading

    def work():
        try:
            from vosk import Model as VoskModel

            t0 = time.monotonic()
            BIG["model"] = VoskModel(str(BIG_DIR))
            log(f"big speech model ready for offline commands ({time.monotonic() - t0:.0f}s to load)")
        except Exception as err:
            log(f"big speech model unavailable, using the small one: {err}")
        finally:
            BIG["loading"] = False

    BIG["loading"] = True
    log("offline: loading the big speech model in the background")
    threading.Thread(target=work, daemon=True).start()


# Whisper (faster-whisper, int8 on the CPU) for the COMMAND, offline. Vosk
# keeps listening for "Hey Jarvis" (fast, light); what is said after it is
# transcribed by Whisper, which understood real speech far better — Vosk
# turned a clean, unclipped command into "uphill oram these are it". small.en
# takes ~3 s a command on this laptop, base.en ~1 s (measured); small first.
WHISPER_DIRS = [HOME / "whisper" / "small.en", HOME / "whisper" / "base.en"]
WHISPER = {"model": None, "loading": False}
SAMPLES = HOME / "voice-samples"  # the last offline commands' audio, to check misheard ones


def load_whisper():
    def work():
        try:
            from faster_whisper import WhisperModel

            logging.getLogger("faster_whisper").setLevel(logging.WARNING)  # not "VAD filter removed…" per command
            path = next((p for p in WHISPER_DIRS if (p / "model.bin").exists()), None)
            if not path:
                return
            t0 = time.monotonic()
            WHISPER["model"] = WhisperModel(str(path), device="cpu", compute_type="int8")
            log(f"Whisper ({path.name}) ready for offline commands ({time.monotonic() - t0:.0f}s to load)")
        except Exception as err:
            log(f"Whisper unavailable, using Vosk for commands: {err}")
        finally:
            WHISPER["loading"] = False

    WHISPER["loading"] = True
    threading.Thread(target=work, daemon=True).start()


# Whisper's well-known inventions on silence or noise.
PHANTOMS = {"", "you", "thank you", "thanks", "thank you for watching", "thanks for watching", "bye", "okay", "ok", "so"}


def whisper_text(pcm):
    """The command in `pcm` by Whisper, as plain lower-case words ("9 p.m." ->
    "9 pm"); "" if Whisper is not ready or heard only noise."""
    m = WHISPER["model"]
    if m is None or not pcm:
        return ""
    import re

    names = wake_names()
    prompt = (
        f"Commands spoken to an assistant called {', '.join(n.title() for n in names)}: go to standby, "
        "what's the time now, what is my battery level, open Chrome, open my downloads, close Spotify, "
        "remind me to call mom at 9 pm, what's on my calendar, create a new folder, volume up."
    )
    try:
        audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
        segs, _ = m.transcribe(audio, language="en", beam_size=1, initial_prompt=prompt, vad_filter=True,
                               condition_on_previous_text=False)
        text = " ".join(s.text.strip() for s in segs).strip()
    except Exception as err:
        log(f"Whisper failed: {err}")
        return ""
    text = re.sub(r"\b([ap])\.\s?m\.?", r"\1m", text, flags=re.I)
    text = re.sub(r"[^\w\s':/-]", " ", text).lower()
    text = re.sub(r"\s+", " ", text).strip()
    return "" if text in PHANTOMS else text


def keep_sample(pcm, said):
    """The last 20 offline commands' audio (with what was heard, in the name)."""
    try:
        import re
        import wave

        SAMPLES.mkdir(parents=True, exist_ok=True)
        name = time.strftime("%Y%m%d-%H%M%S") + "-" + (re.sub(r"[^a-z0-9]+", "-", said.lower())[:40] or "nothing") + ".wav"
        with wave.open(str(SAMPLES / name), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm)
        for old in sorted(SAMPLES.glob("*.wav"))[:-20]:
            old.unlink(missing_ok=True)
    except Exception:
        pass


def tones(*notes):
    """Short beeps: (frequency, ms) each. Best effort."""
    try:
        import winsound

        for f, ms in notes:
            winsound.Beep(f, ms)
    except Exception:
        pass


def notify_async(title, body):
    """A Windows notification without holding up the listening (it takes ~1 s)."""
    threading.Thread(target=lambda: toast(title, body), daemon=True).start()


def command_after_name(text):
    """What followed his name in one breath ("hey jarvis what's my battery
    level" -> "what's my battery level"); "" if nothing did."""
    words = text.split()
    names = [n.split() for n in wake_names()]
    for i in range(len(words) - 1, -1, -1):
        for n in names:
            if words[i : i + len(n)] == n:
                return " ".join(words[i + len(n) :]).strip()
    return ""


# Everyday offline commands. Heard against this list as well as free-form: a
# restricted grammar snaps a slightly blurred phrase onto the nearest real
# command, where free-form gave "what split them know" for "what's the time
# now". Used only when Vosk is sure; anything else stays free-form.
COMMANDS = [
    "what time is it", "what is the time", "what is the time now", "tell me the time", "time now",
    "what is the date", "what is the date today", "what day is it", "what day is it today",
    "what is my battery level", "what is the battery level", "how much battery do i have", "battery status", "battery level",
    "how much free space do i have", "how much storage do i have", "disk space",
    "what is on my calendar", "what are my reminders", "any reminders", "my schedule",
    "open chrome", "open google chrome", "open notepad", "open calculator", "open settings", "open spotify",
    "open whatsapp", "open file explorer", "open explorer", "open terminal", "open visual studio code", "open vs code",
    "open downloads", "open the downloads folder", "open documents", "open the documents folder", "open desktop",
    "open pictures", "open music", "open videos",
    "close chrome", "close notepad", "close calculator", "close spotify",
    "turn the volume up", "turn the volume down", "volume up", "volume down", "louder", "quieter",
    "mute", "unmute", "pause", "play", "next song", "previous song",
    "lock the computer", "lock my computer", "lock the pc", "lock my pc", "lock the screen",
    "what is my cpu usage", "what is my memory usage", "am i connected to the internet", "which wifi am i on",
    "what is my system status", "what is the system status", "system status", "how is my laptop doing",
    "how is my computer doing", "how is my pc doing",
    "go to standby", "go to standby mode", "go to stand by", "go to stand by mode", "standby", "stand by",
    "standby mode", "go to sleep", "sleep mode", "stop", "stop listening", "cancel", "never mind",
]


def grammar_command(model, pcm, with_wake=False):
    """The command in `pcm` if it is one of COMMANDS and Vosk is sure (every
    word heard with confidence ≥ 0.8); "" otherwise. `with_wake`: the audio
    may start with his name ("hey jarvis what time is it")."""
    from vosk import KaldiRecognizer

    phrases = list(COMMANDS)
    if with_wake:
        wakes = [f"{g} {n}" for n in wake_names() for g in GREETINGS] + wake_names()
        phrases += [f"{w} {c}" for w in wakes for c in COMMANDS]
    rec = KaldiRecognizer(model, RATE, json.dumps(phrases + ["[unk]"]))
    rec.SetWords(True)
    words = []
    for i in range(0, len(pcm), 8000):
        if rec.AcceptWaveform(pcm[i : i + 8000]):
            words += json.loads(rec.Result()).get("result", [])
    words += json.loads(rec.FinalResult()).get("result", [])
    words = [w for w in words if w.get("word") != "[unk]"]
    # 0.6: with a distorted (clipping) mic the right command came back at
    # 0.6-0.8; unrelated speech falls into [unk] rather than a command.
    if not words or min(w.get("conf", 0) for w in words) < 0.6:
        return ""
    text = " ".join(w["word"] for w in words)
    if with_wake:
        after = command_after_name(text)
        text = after or text
    return text if text in COMMANDS else ""


def transcribe(model, pcm):
    from vosk import KaldiRecognizer

    rec = KaldiRecognizer(model, RATE)
    parts = []
    for i in range(0, len(pcm), 8000):
        if rec.AcceptWaveform(pcm[i : i + 8000]):
            parts.append(json.loads(rec.Result()).get("text", ""))
    parts.append(json.loads(rec.FinalResult()).get("text", ""))
    return " ".join(p for p in parts if p).strip()


def keep_level():
    """Offline, every 15 s: the Windows mic level back down to 75% if
    something raised it (Chrome's own recogniser does, online). The clip
    guard below only acts after speech has already clipped — the first
    command after going offline was garbled every time ("what's the airplane
    know"); this keeps it in range before anyone speaks."""
    script = str(ROOT / "scripts" / "mic-level.ps1")
    while True:
        if OFFLINE["on"]:
            try:
                r = subprocess.run(
                    ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Max", "75"],
                    capture_output=True, text=True, timeout=30,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                level = r.stdout.strip()
                if level and level != KEPT.get("level"):
                    KEPT["level"] = level
                    log(f"microphone level {level}% (kept at 75% or below offline)")
            except Exception:
                pass
            time.sleep(15)
        else:
            time.sleep(3)


KEPT = {"level": None}


def clipped_share():
    """The share of the last capture's samples at the limit (0.0-1.0)."""
    return CAPTURE.get("clipped", 0) / max(1, CAPTURE.get("samples", 0))


def clip_guard():
    """The command just heard clipped (peaks at the top of the range): the
    Windows mic level is too high — Chrome's gain control has pushed it to
    100% before — and clipped speech is what garbled offline commands
    ("vantage they're paying now"). Lower it 15 points, never below 50%.
    Only after real clipping, so a level the user chose is otherwise left
    alone. In the background: the helper takes a second or two."""
    # Read now: the next capture resets them. Real clipping, not one click at
    # the top of the range: over 0.2% of the samples flat at the limit. This
    # microphone (a digital AMD array) has no "Microphone Boost" to lower, so
    # the level is the only gain there is, and it may go as low as 30%.
    loudest = CAPTURE["loudest"]
    share = clipped_share()
    if share < 0.002:
        return

    def run():
        try:
            r = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                 str(ROOT / "scripts" / "mic-level.ps1"), "-Lower", "10", "-Floor", "30"],
                capture_output=True, text=True, timeout=30,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            log(f"speech clipped ({share:.1%} of it, loudest {loudest}) - microphone level now {r.stdout.strip()}%")
        except Exception as err:
            log(f"speech clipped, could not lower the microphone level: {err}")

    threading.Thread(target=run, daemon=True).start()


def offline_capture(stream, vosk_model, why, recent=None):
    """Offline: hear the command with Vosk and hand it to JARVIS. For "Hey
    Jarvis" and for the mic button alike. Uses the big model when it is
    loaded, the small one until then.

    Said in one breath ("hey jarvis, what's my battery level"), the command is
    already in `recent` — the last few seconds of audio — because the phrase
    is only recognised once the speaker stops: listening *after* it heard
    nothing (measured: "nothing heard" three times in a row). Otherwise a
    two-tone chime and a notification say he is listening, and he waits."""
    model = BIG["model"] or vosk_model
    if recent:
        pcm = b"".join(recent)
        heard = whisper_text(pcm)
        said = command_after_name(heard) if heard else ""
        if not said:
            said = grammar_command(model, pcm, with_wake=True) or command_after_name(transcribe(model, pcm))
        if len(said.split()) >= 2:
            tones((880, 90), (1320, 110))
            ok = ask_bridge(said)
            log(f'offline command ({why}, same breath): "{said}"' + ("" if ok else " (could not reach JARVIS)"))
            return
    tones((880, 90), (1320, 110))
    notify_async("Listening (offline)", "Say your command now.")
    said = capture_command(stream, model, limit=14.0, quiet=1.5, save=False)
    clip_guard()
    if said:
        ok = ask_bridge(said)
        log(f'offline command ({why}): "{said}" (loudest {CAPTURE["loudest"]}, clipped {clipped_share():.1%})' + ("" if ok else " (could not reach JARVIS)"))
    else:
        tones((440, 220))  # nothing heard: try again
        log(f"offline ({why}): nothing heard (loudest {CAPTURE['loudest']})")


def capture_command(stream, vosk_model, limit=8.0, quiet=1.3, save=True):
    """Right after "Hey Jarvis" with JARVIS off: transcribe what follows (up to
    `limit` seconds, ending at `quiet` seconds of silence after speech) with
    Vosk, free-form, and leave it for his window (GET /pending-command).
    With save=False it is only returned — offline, the window's own
    recogniser (Chrome's, which needs the internet) cannot hear."""
    from vosk import KaldiRecognizer

    rec = KaldiRecognizer(vosk_model, RATE)
    start = time.monotonic()
    heard_at = None
    parts = []
    # The tail of "Hey Jarvis" itself is still in the buffer when this starts.
    # Counting it as the command beginning ended the capture during the
    # natural pause before the command ("nothing heard", measured offline).
    settle = 0.7
    CAPTURE["loudest"] = 0
    CAPTURE["samples"] = 0
    CAPTURE["clipped"] = 0
    captured = []  # the command's audio, for the everyday-command check
    while time.monotonic() - start < limit:
        if stream.read_available < CHUNK:
            time.sleep(0.02)
            continue
        audio, _ = stream.read(CHUNK)
        if time.monotonic() - start < settle:
            continue  # the wake phrase's own tail: not part of the command
        captured.append(audio.tobytes())
        peak = int(np.abs(audio).max())
        CAPTURE["loudest"] = max(CAPTURE["loudest"], peak)
        CAPTURE["samples"] = CAPTURE.get("samples", 0) + audio.size
        CAPTURE["clipped"] = CAPTURE.get("clipped", 0) + int((np.abs(audio.astype(np.int32)) >= 32000).sum())
        # 1000, not 1500: a normal voice a little way from the laptop peaked
        # around 1,000-1,800 here and was taken for silence.
        if peak > 1000:
            heard_at = time.monotonic()
        if rec.AcceptWaveform(audio.tobytes()):
            parts.append(json.loads(rec.Result()).get("text", ""))
        if heard_at and time.monotonic() - heard_at > quiet:
            break
        # Offline, 8 s to start speaking (people wait for the chime, then think).
        if not heard_at and time.monotonic() - start > (8.0 if not save else 3.5):
            break  # nothing said after his name: he will just listen
    parts.append(json.loads(rec.FinalResult()).get("text", ""))
    text = " ".join(p for p in parts if p).strip()
    pcm = b"".join(captured)
    # Whisper, when it is loaded (offline), reads the command far better than
    # Vosk; Vosk's reading is the fallback.
    heard = whisper_text(pcm) if heard_at else ""
    if heard:
        if heard != text:
            log(f'Whisper heard "{heard}" (Vosk heard "{text}")')
        text = heard
    # Without Whisper: an everyday command heard clearly against the list
    # beats a blurred free-form reading of it.
    elif captured:
        sure = grammar_command(vosk_model, pcm)
        if sure:
            if sure != text:
                log(f'everyday command "{sure}" (free-form heard "{text}")')
            text = sure
    if not save and heard_at:
        keep_sample(pcm, text)
    # Strip a repeated wake phrase the recogniser may have caught again
    # ("hello friday", "friday", "hey jarvis" …).
    leads = sorted({f"{g} {n}" for n in wake_names() for g in GREETINGS} | set(wake_names()), key=len, reverse=True)
    for lead in leads:
        if text.startswith(lead):
            text = text[len(lead):].strip()
            break
    if not save:
        return text
    if len(text.split()) >= 2:
        PENDING.write_text(json.dumps({"text": text, "at": int(time.time() * 1000)}), encoding="utf-8")
        log(f'caught the command while starting: "{text}"')
    return text


def start_jarvis():
    # Always through the launcher: it starts the brain only if it is not
    # already up, and opens the window on the loading screen straight away.
    log("starting JARVIS" if not bridge()[0] else "brain is running - opening the JARVIS window")
    subprocess.Popen(
        ["cmd", "/c", str(BAT), "wake"],
        cwd=ROOT,
        creationflags=NO_WINDOW,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


GREETINGS = ("hey", "hi", "hello", "ok", "okay")


def assistant_name():
    """The assistant's name from setup ("Friday", "J.A.R.V.I.S" -> "jarvis"),
    lower case, as it is said."""
    try:
        raw = json.loads((HOME / "profile.json").read_text(encoding="utf-8-sig")).get("assistant") or ""
    except (OSError, ValueError):
        raw = ""
    name = " ".join(raw.replace(".", "").lower().split())
    return name or "jarvis"


def wake_names():
    """The names he answers to: the one from setup, and "jarvis" always (the
    openWakeWord model only knows "Hey Jarvis", so it stays an alias)."""
    name = assistant_name()
    return [name] if name == "jarvis" else [name, "jarvis"]


def wake_grammar(names):
    """Vosk phrases: a greeting and the name ("hey friday", "hello friday"),
    or the name alone. Anything else falls into [unk]."""
    phrases = [f"{g} {n}" for n in names for g in GREETINGS] + list(names)
    return json.dumps(phrases + ["[unk]"])


def heard_wake(result, names, offline):
    """Did this finished Vosk result call him? With a greeting in front, yes.
    The name alone only when it was the whole utterance and Vosk was sure:
    restricted to a tiny grammar, Vosk forces near-misses onto the nearest
    phrase ("go to stand by" became "jarvis" six times a minute), and the
    confidence is what tells a real "Friday" from a forced one. Offline (this
    listener is the only way in) a lone name is enough."""
    text = result.get("text", "")
    if any(f"{g} {n}" in text for n in names for g in GREETINGS):
        return True
    if text in names:
        if offline:
            return True
        words = result.get("result") or []
        return bool(words) and min(w.get("conf", 0) for w in words) >= 0.85
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=0.15)
    args = ap.parse_args()

    single_instance()
    download_models(["hey_jarvis"])  # no-op once cached
    # The voice-activity filter zeroes the score unless there is human speech,
    # which is what keeps a low threshold from firing on taps, music or fans.
    model = Model(wakeword_models=["hey_jarvis"], inference_framework="onnx", vad_threshold=0.5)

    # A second detector: Vosk's small Indian English model, listening only for
    # the phrase. openWakeWord was trained mostly on synthetic American voices
    # and scores some accents near zero; either detector hearing it is enough.
    # Optional — without the model folder the listener runs on openWakeWord.
    vosk_rec = None
    vosk_model = None
    vosk_dir = HOME / "vosk" / "vosk-model-small-en-in-0.4"
    if vosk_dir.exists():
        try:
            from vosk import KaldiRecognizer, Model as VoskModel, SetLogLevel

            SetLogLevel(-1)
            vosk_model = VoskModel(str(vosk_dir))
        except Exception as err:
            log(f"Vosk unavailable, using openWakeWord alone: {err}")
    names = wake_names()
    last_names_check = time.monotonic()

    def make_rec():
        # The name from setup: "hey/hi/hello/ok <name>", or the name alone.
        from vosk import KaldiRecognizer

        rec = KaldiRecognizer(vosk_model, RATE, wake_grammar(names))
        rec.SetWords(True)  # word confidences, for the name said alone
        return rec

    if vosk_model is not None:
        vosk_rec = make_rec()
    log(f"ready (threshold {args.threshold}, Vosk {'on' if vosk_rec else 'off'}, answers to: {', '.join(names)})")
    threading.Thread(target=keep_level, daemon=True).start()

    stream = None
    last_fire = 0.0  # last time the phrase was acted on at all
    last_start = -1e9  # last cold start of JARVIS
    last_check = 0.0
    last_reminders = 0.0
    jarvis_on = False
    last_data = last_sound = time.monotonic()
    stat_at, stat_peak, stat_score = time.monotonic(), 0, 0.0

    paused = False
    last_mute_check = 0.0
    recent = deque(maxlen=100)  # 100 x 80 ms = the last 8 s of audio
    while True:
        try:
            # The kill switch (desktop shortcut, scripts/jarvis-switch.ps1).
            # While it is off: microphone closed, phrase ignored, nothing
            # started — including at login, since this runs from Startup.
            off = KILL_SWITCH.exists()
            muted = MUTED.exists()
            # A mute lasts only while JARVIS is open. Muted and then closed,
            # nothing on screen could unmute him, and "Hey Jarvis" stayed dead
            # until someone found ~/.jarvis/muted by hand.
            if muted and not off and time.monotonic() - last_mute_check > 3:
                last_mute_check = time.monotonic()
                if not bridge()[0]:
                    try:
                        MUTED.unlink()
                    except OSError:
                        pass
                    muted = False
                    log("JARVIS is closed - mute lifted")
            if off or muted:
                if not paused:
                    paused = True
                    log("switched OFF - not listening" if off else "microphone MUTED - not listening")
                if stream is not None:
                    stream.stop()
                    stream.close()
                    stream = None
                # Short while muted, so unmuting takes effect almost at once.
                time.sleep(2 if off else 0.5)
                continue
            if paused:
                paused = False
                log("switched ON - listening again")
                last_check = 0.0

            now = time.monotonic()
            # A new name saved in setup: listen for it within ten seconds.
            if now - last_names_check > 10:
                last_names_check = now
                fresh_names = wake_names()
                if fresh_names != names:
                    names = fresh_names
                    if vosk_model is not None:
                        vosk_rec = make_rec()
                    log(f"now answers to: {', '.join(names)}")
            if now - last_check > 3:
                last_check = now
                up, clients = bridge()
                running = up and clients > 0
                # Offline (the bridge on the local model): remember it, for
                # the forgiving wake check, and get the big speech model ready.
                was_offline = OFFLINE["on"]
                OFFLINE["on"] = bool(up) and brain_mode() == "local"
                if OFFLINE["on"] != was_offline:
                    log("offline mode: listening for the phrase more readily" if OFFLINE["on"] else "back online")
                if OFFLINE["on"] and BIG_DIR.exists() and BIG["model"] is None and not BIG["loading"]:
                    load_big_model()
                if OFFLINE["on"] and WHISPER["model"] is None and not WHISPER["loading"]:
                    load_whisper()
                if running != jarvis_on:
                    jarvis_on = running
                    log(
                        "JARVIS is running - waking his window on the phrase"
                        if running
                        else 'JARVIS is off - will start him on the phrase'
                    )
                # With the brain down nobody else is watching the clock:
                # reminders and timers still pop up as notifications.
                if not up and now - last_reminders > 30:
                    last_reminders = now
                    fire_due_reminders()

            if stream is None:
                stream = sd.InputStream(samplerate=RATE, channels=1, dtype="int16", blocksize=CHUNK)
                stream.start()
                model.reset()
                last_data = last_sound = time.monotonic()

            # The mic button, offline: Chrome's recogniser cannot hear without
            # the internet, so the bridge asks for the command to be heard
            # here instead (a fresh ~/.jarvis/listen-now).
            if LISTEN_NOW.exists():
                try:
                    fresh = time.time() - LISTEN_NOW.stat().st_mtime < 10
                    LISTEN_NOW.unlink()
                except OSError:
                    fresh = False
                if fresh and vosk_model is not None:
                    offline_capture(stream, vosk_model, "mic button")
                    model.reset()
                last_data = last_sound = time.monotonic()
                continue

            # Never block on the microphone: a device that stops delivering
            # audio (Chrome letting go of it, a driver hiccup) would otherwise
            # freeze this loop silently — alive, logging nothing, hearing
            # nothing. No audio for 3 s, or pure digital silence for 30 s,
            # and the stream is reopened.
            now = time.monotonic()
            if stream.read_available < CHUNK:
                if now - last_data > 3:
                    log("microphone stalled - reopening it")
                    stream.close()
                    stream = None
                else:
                    time.sleep(0.02)
                continue
            audio, _ = stream.read(CHUNK)
            last_data = now
            # The last 8 s, for a command said in the same breath as his name.
            recent.append(audio.tobytes())
            peak = int(np.abs(audio).max())
            if peak > 0:
                last_sound = now
            elif now - last_sound > 30:
                log("microphone gave pure silence for 30 s - reopening it")
                stream.close()
                stream = None
                continue

            score = float(model.predict(audio[:, 0])["hey_jarvis"])

            # Once a minute: proof of life, and what it is actually hearing.
            stat_peak = max(stat_peak, peak)
            stat_score = max(stat_score, score)
            if now - stat_at > 60:
                log(f"listening - loudest {stat_peak}, best score {stat_score:.2f}")
                stat_at, stat_peak, stat_score = now, 0, 0.0

            # Vosk: only the whole phrase "hey jarvis", and only on a finished
            # result. Restricted to a tiny grammar it forces near-misses onto
            # the nearest phrase — accepting "jarvis" alone or partial results,
            # "go to stand by" woke him six times in a minute. Runs whether he
            # is open or not: it is the detector that copes with an Indian
            # accent, and the page ignores a wake while it is already listening,
            # so a stray one cannot chop a sentence.
            #
            # Offline this listener is the only way in (Chrome's recogniser,
            # which also listens for the phrase online, needs the internet),
            # so it is more forgiving there: a lower threshold, and a lone
            # "jarvis" counts. A false wake offline costs only a beep.
            offline = OFFLINE["on"]
            threshold = min(args.threshold, 0.08) if offline else args.threshold
            vosk_heard = False
            if vosk_rec is not None:
                if vosk_rec.AcceptWaveform(audio.tobytes()):
                    got = json.loads(vosk_rec.Result())
                    vosk_heard = heard_wake(got, names, offline)
                    if vosk_heard:
                        log(f'Vosk caught "{got.get("text", "")}"')
            if score < threshold and not vosk_heard:
                continue
            if vosk_heard and score < threshold:
                score = 1.0  # for the log: it was Vosk that caught it

            # One utterance spans several 80 ms frames: count it once.
            if time.monotonic() - last_fire < 2:
                continue
            last_fire = time.monotonic()
            model.reset()
            if vosk_rec is not None:
                vosk_rec.Reset()

            # Running: wake the window on the spot, like "Hey Google". Tried
            # whenever the bridge might be up, not only when the last check
            # said so — that check is up to three seconds old.
            # Offline (the bridge runs on the local model): Chrome's recogniser
            # needs the internet, so hear the command here, with Vosk, and
            # hand it over as a typed request.
            if vosk_model is not None and brain_mode() == "local":
                log(f'heard "Hey Jarvis" ({score:.2f}) - offline, listening here')
                offline_capture(stream, vosk_model, "wake phrase", recent=list(recent))
                recent.clear()
                model.reset()
                last_data = last_sound = time.monotonic()
                continue
            if jarvis_on or bridge()[0]:
                if wake_window():
                    log(f'heard "Hey Jarvis" ({score:.2f}) - woke the window')
                    continue
                jarvis_on = False  # closed since the last check: start him instead

            # Off: start him. Its own, longer cooldown, so a start in progress
            # is not started again — but a failed wake above never delays it.
            if time.monotonic() - last_start > 45:
                last_start = time.monotonic()
                log(f'heard "Hey Jarvis" ({score:.2f}) - JARVIS is off')
                start_jarvis()
                # He takes a while to come up; whatever is said in the
                # meantime ("Hey Jarvis, what's the weather") is caught here,
                # offline, and answered the moment he is ready.
                if vosk_model is not None:
                    capture_command(stream, vosk_model)
                stream.stop()
                stream.close()
                stream = None
                time.sleep(12)  # let him come up before listening again
                last_check = 0.0
        except Exception as err:  # keep running whatever happens
            log(f"error: {err}")
            if stream is not None:
                try:
                    stream.close()
                except Exception:
                    pass
                stream = None
            time.sleep(5)


if __name__ == "__main__":
    main()
