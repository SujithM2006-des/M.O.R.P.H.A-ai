# Restoring J.A.R.V.I.S. from the backup

This project is backed up, with its full history, at
**https://github.com/SujithM2006-des/JARVIS_BACKUP** (branch `main`). The
branch `local-only` adds the files kept out of the main project (such as
`scripts/try-ollama.mjs`).

## Get it back

```bat
git clone https://github.com/SujithM2006-des/JARVIS_BACKUP.git jarvis-main
cd jarvis-main
npm install
```

Then:

1. **Your settings and memory** are not on GitHub (the backup repository is
   public, so private data never goes there). Restore them from the local zip
   `Downloads\jarvis final\jarvis-settings-and-data.zip` — its `RESTORE.txt`
   says where each part goes (`%USERPROFILE%\.jarvis`, `Pictures\Jarvis`,
   `Videos\Jarvis`).
2. **AI keys**: copy `.env.example` to `.env.local` and fill it in, or sign in
   again from J.A.R.V.I.S.'s Customize screen (Gemini, OpenRouter, Groq).
3. **The "Hey Jarvis" listener and offline speech**: see README.md, "The Hey
   Jarvis wake word and the desktop switch".
4. Start it: `start-jarvis.bat` (or `npm start -- --writes`). Say "health
   check" — it lists anything still missing and how to fix it.

## Or install it the easy way

The setup file builds the same J.A.R.V.I.S. onto any Windows PC:
https://github.com/SujithM2006-des/JARVIS_INSTALLER — or build it from
`installer\` here (`installer\build.ps1`).

## What is where

| What | Where |
|---|---|
| Code, history, installer | GitHub: JARVIS_BACKUP (and jarvisv2) |
| Files kept out of the project | GitHub: JARVIS_BACKUP, branch `local-only` |
| Settings, memory, reminders, routines, Flow characters, videos | Local: `Downloads\jarvis final\jarvis-settings-and-data.zip` |
| AI keys and logins | Local only (never on GitHub) |
| The whole folder, as it was | Local: `Downloads\jarvis final\jarvis-main.zip` |
