# Jarvis — bug report

Found on 26 Nov 2026 by using the Jarvis page in a test browser (clicking
through everything, watching the page's and the bridge's errors) and running
the type check, linter and tests. **All fixed the same day** and retested.

After the fixes: type check clean · lint passes · tests 30 passed, 0 failed ·
**no errors in the page's console**.

| # | Problem | Status | How it was checked |
|---|---|---|---|
| 1 | Gemini, Groq and OpenRouter stuck on "starting" when LiteLLM took over 30 s to start | ✅ Fixed — Jarvis keeps checking (up to 5 minutes) and marks them ready as soon as LiteLLM answers | Code reviewed; LiteLLM started in time on the retest, so the slow path itself didn't run |
| 2 | Picking a model that isn't ready silently answered with Claude | ✅ Fixed — the menu says who is really answering: "Groq · starting → Claude" | Simulated in the browser |
| 3 | Calendar filled in 9:00 AM even when that had passed, and saved past entries that never reminded you | ✅ Fixed — suggests the next whole hour today (12:00 at 11:42), and a past time is refused: "That time has already passed — pick a later one." | Tested |
| 4 | "Sessions, usage & more ↓" covered the text box and mic on a phone-size window | ✅ Fixed — not shown at phone width (the panels follow the text box there) | Tested at 400 px |
| 5 | No tab icon, and a 404 error on every load | ✅ Fixed — `index.html` links `favicon.svg` | Tested: no console errors at all |
| 6 | The setup screen didn't close with Esc | ✅ Fixed — Esc works like Cancel (not on the first-run screen) | Tested |
| 7 | A typed question ran in every open Jarvis window (paid twice) | ✅ Fixed — your text box answers in its own window; popup questions and routines go to one window | Tested with two windows: answered once |
| 8 | Model menu cut off on narrow screens ("Auto · Cl…") | ✅ Fixed — short names at phone width ("Auto"); full text on hover | Tested at 400 px |
| 9 | Copy put `##` and `**` on the clipboard | ✅ Fixed — copies formatted text for Word/Docs and clean plain text for WhatsApp/Notepad | Tested: plain text has no symbols |
| 10 | Main text box had no label for screen readers | ✅ Fixed — labelled "Ask Jarvis" | Tested |
| 11 | Text smaller than 10 px ("now" tag, "%" signs) | ✅ Fixed — 10.5 px and at least 10 px | Tested: none under 10 px left |
| 12 | Garbled characters in the log | ✅ Mostly not a bug — the log is correct UTF-8; it only looked garbled when read with Windows PowerShell 5.1. The one real case (a character split between two chunks of output) is fixed in `scripts/start.mjs` | Code reviewed |
| 13 | Page 8 px wider than a phone screen | ✅ Fixed — the orb's spinning ring of text is clipped at phone width | Tested: 0 px overflow |

Also tidied: an unused variable in `bridge/chrome.mjs`, and a duplicated
`alwaysLoad` setting in `bridge/panels.mjs` and `bridge/assistant.mjs`.

## Second round (26 Nov)

| # | Problem | Status | How it was checked |
|---|---|---|---|
| 14 | Calendar after 11 PM suggested 11:00 PM (already past) and refused its own suggestion | ✅ Fixed — suggests 9:00 AM tomorrow | Tested at a simulated 11:30 PM: 27 Nov, 9:00 AM |
| 15 | With the bridge stopped, "Link" stayed green and System Status said LIVE (old numbers) until you asked something | ✅ Fixed — Link turns red with "restart Jarvis" on hover; System Status says PAUSED | Tested with the bridge stopped and started again |
| 16 | The "Cannot reach the bridge" message stayed on screen under the next good answer | ✅ Fixed — a new request clears the old error | Code |
| 17 | That error message was technical (ports, `npm start`) | ✅ Fixed — plain words; the port details only when the port is the real cause | Code |
| 18 | The setup city ("for weather when location is off") was never used | ✅ Fixed — used when Windows location is off, before the internet provider's rough guess. A brief Windows location lapse keeps the last known place; it gets 20 s instead of 10 | Windows location tested: Namakkal, 212 m |

Checked and **not bugs** (earlier report was wrong):
- **"Another session made tools always load"**: those settings were already
  in the committed code before tool search was turned on, and the 36% Claude
  saving was measured with them in place. Nothing was undone.
- **"Weather city jumps"**: Windows location places this PC in Namakkal now;
  the earlier Tambaram reading was where the PC was then.
- **The page after the bridge restarts**: it reconnects by itself, and the
  next question is answered normally.

## Third round (26 Nov)

| # | Problem | Status | How it was checked |
|---|---|---|---|
| 19 | A question typed while the bridge was down was lost | ✅ Fixed — it goes back into the text box; Enter retries it | Tested with the bridge stopped |
| 20 | The Agent timeline said "Done" after a failed request | ✅ Fixed — a red "Failed" step | Tested |
| 21 | Reminders, "Hey Jarvis", the popup mic and circle-to-search went to every open window (spoken or answered twice) | ✅ Fixed — sent to one window (the newest); mute still goes to all | Tested: a reminder with two windows open reached one |
| 22 | Flow credits showed nothing after Flow's redesign (the reset date is gone from its menu) | ✅ Fixed — reads "250 Google Flow credits" | Tested |
| 23 | When Flow and the Gemini app both failed, the message said "with Google Flow" but gave only Gemini's reason | ✅ Fixed — both reasons | Code |
| 24 | A Flow failure said only "Timeout 15000ms exceeded" | ✅ Fixed — names the step ("typing the prompt" …); notices are cleared again just before typing | Code |

Checked live this round:
- **The LiteLLM slow-start fix:** forced the slow path; LiteLLM came up 28 s
  later and the models were enabled.
- **A real AI video:** Flow made a 4-second 720×1280 clip with sound in
  102 s; Gemini watched it and scored it 10/10 (on its backup model, since
  the first was busy). About 12 credits.
- **Gemini app videos:** "Create video" isn't in the Gemini app's menu at
  the moment. Flow is the main path, so this only matters if Flow fails.

## Fourth round (26 Nov)

| # | Problem | Status | How it was checked |
|---|---|---|---|
| 25 | Gemini app videos: "Create video" never found | ✅ Fixed — "More tools" now opens on hover, and the old click closed it again | Tested: Jarvis switches Gemini to video mode and sends the request |
| 26 | When the Gemini app answered with an error, Jarvis waited the full 9 minutes | ✅ Fixed — after Gemini's error reply ("I seem to be encountering an error…") it waits 90 s for a clip, then reports Gemini's words | Both of Gemini's error wordings matched; a normal reply doesn't |
| 27 | Commit `a46d0dc` on GitHub had another session's message | ✅ Fixed — now `57a2b75` "Fix popup lock-out, browse without the extension, voice by request" (same files). The old history is kept as the branch `backup/before-reword` | Pushed to jarvisv2 |

Checked live this round:
- **Remaking a clip that fails its check:** a clip deliberately checked
  against the wrong description failed (3/10, "a sleeping cat instead of a red
  sports car"); Jarvis remade it with the checker's fix and the remake passed
  (7/10). About 24 credits.
- **The Gemini app itself:** it answered both test requests with an error on
  Google's side, so no Gemini-app clip was made today. Flow, the main path,
  works.

Still open:
- **Automatic Groq key setup:** Groq has signed out of Jarvis's Chrome
  window. Sign in once (Setup → Groq → Sign in) and it can be tested.
- **Note on GitHub:** this project pushes to **jarvisv2** (`v2`); `origin`
  is the older **jarvis_v1**, which was not changed.

## Worth knowing
- **Two Claude sessions editing this folder at once** caused the wrong commit
  message on `a46d0dc`. Use one session at a time.
- **Known limits (not bugs):**
  - Groq's free plan allows about one question a minute.
  - The automatic Groq key setup once couldn't read a new key back.
  - An ordinary browser needs one click before Jarvis starts.

## Remaining lint warnings (deliberate, harmless)
- `no-control-regex` in `markdown.ts`, `profile.mjs` and `start.mjs`: they
  strip control characters on purpose.
- `whatsapp.mjs`: an emoji pattern.
- `orbs.tsx`: a shared constant beside components.
