/**
 * Natural voices: Microsoft's online neural voices (edge-tts), for JARVIS's
 * own speech and the setup screen's voice list.
 *
 * The PC itself usually has only two or three voices (David, Mark, Zira).
 * These are hundreds more, in every language, free and without a key — they
 * need the internet, so the window falls back to a PC voice when offline.
 *
 * scripts/voice_server.py does the work and stays running, so a sentence costs
 * only its synthesis (well under a second) instead of a Python start-up.
 */

import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PYTHON = join(homedir(), '.jarvis', 'wake-venv', 'Scripts', 'python.exe')
const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'voice_server.py')
const OUT = join(tmpdir(), 'jarvis-voice')

let proc = null
let seq = 0
const waiting = new Map()
let listCache = null

/** Can natural voices be used here at all (edge-tts installed)? */
export const naturalAvailable = () => existsSync(PYTHON) && existsSync(SCRIPT)

function helper() {
  if (proc && proc.exitCode === null) return proc
  proc = spawn(PYTHON, [SCRIPT], { stdio: ['pipe', 'pipe', 'ignore'], windowsHide: true })
  let buf = ''
  proc.stdout.setEncoding('utf8')
  proc.stdout.on('data', (d) => {
    buf += d
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i)
      buf = buf.slice(i + 1)
      let msg
      try {
        msg = JSON.parse(line)
      } catch {
        continue
      }
      const w = waiting.get(msg.id)
      if (!w) continue
      waiting.delete(msg.id)
      clearTimeout(w.timer)
      if (msg.error) w.reject(new Error(msg.error))
      else w.resolve(msg)
    }
  })
  // Gone (crashed, or the venv was removed): fail what was waiting; the next
  // request starts a fresh one.
  proc.on('exit', () => {
    for (const [, w] of waiting) {
      clearTimeout(w.timer)
      w.reject(new Error('the voice helper stopped'))
    }
    waiting.clear()
    proc = null
  })
  proc.on('error', () => {})
  return proc
}

function ask(req, ms) {
  if (!naturalAvailable()) return Promise.reject(new Error('natural voices are not installed'))
  return new Promise((resolve, reject) => {
    const id = ++seq
    const timer = setTimeout(() => {
      waiting.delete(id)
      reject(new Error('the voice took too long'))
    }, ms)
    waiting.set(id, { resolve, reject, timer })
    helper().stdin.write(JSON.stringify({ ...req, id }) + '\n')
  })
}

/** Every natural voice: [{id, name, lang, langName, gender}], fetched once. */
export async function naturalVoices() {
  if (listCache) return listCache
  const r = await ask({ op: 'list' }, 30_000)
  listCache = r.voices
  return listCache
}

/** "+20%" style, from a speed where 1 is the voice's normal pace. */
const ratePct = (rate) => {
  const n = Math.max(-50, Math.min(100, Math.round((Number(rate) || 1) * 100 - 100)))
  return `${n >= 0 ? '+' : ''}${n}%`
}

/** One sentence in a natural voice, as MP3 bytes. */
export async function naturalSay(text, voice, rate = 1) {
  if (!/^[a-z]{2,3}-[A-Za-z0-9]+-[A-Za-z0-9]+Neural$/.test(String(voice))) throw new Error('unknown voice')
  mkdirSync(OUT, { recursive: true })
  const out = join(OUT, `${Date.now()}-${++seq}.mp3`)
  await ask({ op: 'say', text: String(text).slice(0, 3000), voice, rate: ratePct(rate), out }, 30_000)
  try {
    return readFileSync(out)
  } finally {
    try {
      unlinkSync(out)
    } catch {
      /* already gone */
    }
  }
}

/** Start the helper ahead of the first sentence (and fetch the list). */
export function warmNaturalVoices() {
  if (naturalAvailable()) naturalVoices().catch(() => {})
}
