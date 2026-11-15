"""
JARVIS's natural voices: Microsoft's online neural voices through edge-tts
(free, no key, needs the internet).

Runs for as long as the bridge does (bridge/voices.mjs starts it), so each
sentence costs only the synthesis itself rather than a Python start-up. One
JSON request per line on stdin, one JSON reply per line on stdout:

  {"id": 1, "op": "list"}
      -> {"id": 1, "voices": [{"id", "name", "lang", "langName", "gender"}]}
  {"id": 2, "op": "say", "text": "...", "voice": "en-GB-RyanNeural", "rate": "+10%", "out": "C:/.../a.mp3"}
      -> {"id": 2, "file": "C:/.../a.mp3"}   or   {"id": 2, "error": "..."}

Requests are handled concurrently, so a slow sentence never holds up the next.
"""

import asyncio
import json
import sys

import edge_tts


def short_name(v):
    # "Microsoft Ryan Online (Natural) - English (United Kingdom)" -> "Ryan"
    friendly = v.get("FriendlyName") or v["ShortName"]
    name = friendly.replace("Microsoft ", "").split(" Online")[0].split(" - ")[0].strip()
    return name or v["ShortName"]


async def handle(req, write):
    rid = req.get("id")
    try:
        if req.get("op") == "list":
            voices = await edge_tts.list_voices()
            out = [
                {
                    "id": v["ShortName"],
                    "name": short_name(v),
                    "lang": v["Locale"],
                    "langName": v.get("LocaleName") or v["Locale"],
                    "gender": v.get("Gender", ""),
                }
                for v in voices
            ]
            write({"id": rid, "voices": out})
        elif req.get("op") == "say":
            com = edge_tts.Communicate(req["text"], req["voice"], rate=req.get("rate") or "+0%")
            await com.save(req["out"])
            write({"id": rid, "file": req["out"]})
        else:
            write({"id": rid, "error": "unknown op"})
    except Exception as e:  # noqa: BLE001 - every failure goes back as a reply
        write({"id": rid, "error": str(e) or type(e).__name__})


async def main():
    loop = asyncio.get_running_loop()

    def write(obj):
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()

    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break  # the bridge has gone: so do we
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        asyncio.create_task(handle(req, write))


if __name__ == "__main__":
    # UTF-8 both ways: Windows would otherwise read the requests in its ANSI
    # code page, and Tamil (or any non-Latin) text arrived garbled.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    asyncio.run(main())
