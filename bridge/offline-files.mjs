/**
 * Multi-step file commands without a model — for offline, where the small
 * local model could not follow "open my downloads and create a new folder in
 * it and cut the neo browser setup and paste it in the new folder" (it made a
 * PDF instead).
 *
 * The sentence is split into steps ("and", "then", commas), and each step must
 * be one this understands — open a folder, create a folder (named or not),
 * cut / copy / move a file, paste it. "It", "there" and "the new folder" refer
 * to the folder in play. Files are found by their approximate name ("neo
 * browser setup" finds NeoBrowserSetup.exe). The whole plan is checked before
 * anything happens: if any step isn't understood, nothing is done and the
 * request goes on to the model — never half a job.
 */

import { cpSync, existsSync, mkdirSync, readdirSync, renameSync, rmSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join } from 'node:path'

const KNOWN = {
  downloads: 'Downloads', download: 'Downloads', documents: 'Documents', document: 'Documents', docs: 'Documents',
  desktop: 'Desktop', pictures: 'Pictures', picture: 'Pictures', photos: 'Pictures', music: 'Music',
  videos: 'Videos', video: 'Videos',
}
const KNOWN_RE = Object.keys(KNOWN).join('|')

/** A known folder's real path (OneDrive may hold Desktop / Documents / Pictures). */
function known(name, home) {
  const dir = KNOWN[name]
  if (!dir) return null
  for (const p of [join(home, 'OneDrive', dir), join(home, dir)]) if (existsSync(p)) return p
  return null
}

const squash = (s) => String(s).toLowerCase().replace(/\.[a-z0-9]{1,5}$/, '').replace(/[^a-z0-9]/g, '')
const clean = (s) =>
  String(s ?? '')
    .trim()
    .replace(/^(the|my|a|an|that|this)\s+/, '')
    .replace(/\s+(file|folder|app|installer)$/, '')
    .trim()

/** The entry in `dir` whose name best matches `wanted` ("neo browser setup"), or null. */
function findIn(dir, wanted, { folders = false } = {}) {
  const want = squash(clean(wanted))
  const words = clean(wanted).toLowerCase().split(/\s+/).filter((w) => w.length > 1)
  if (!want) return null
  let best = null
  let bestScore = 0
  let names = []
  try {
    names = readdirSync(dir)
  } catch {
    return null
  }
  for (const name of names) {
    const full = join(dir, name)
    let isDir
    try {
      isDir = statSync(full).isDirectory()
    } catch {
      continue
    }
    if (folders !== isDir) continue
    const n = squash(name)
    let score
    if (n === want) score = 100
    else if (n.includes(want)) score = 80 - Math.min(20, n.length - want.length)
    else score = (words.filter((w) => n.includes(w)).length / Math.max(1, words.length)) * 60
    if (score > bestScore) {
      bestScore = score
      best = full
    }
  }
  return bestScore >= 40 ? best : null
}

/** A free name: "New folder", "New folder (2)" … */
function freeName(dir, name, taken = new Set()) {
  let n = name
  for (let i = 2; existsSync(join(dir, n)) || taken.has(join(dir, n)); i++) n = `${name} (${i})`
  return n
}

/** Split into steps; null if any step is not one of ours. */
export function plan(text) {
  const t = String(text)
    .toLowerCase()
    .replace(/^\[.*?\]\s*/, '')
    .replace(/^(?:hey|hi|hello|ok|okay)?\s*(?:jarvis|j\.a\.r\.v\.i\.s\.?)[,\s]+/, '')
    .replace(/[.!?]+$/, '')
    .replace(/\b(?:please|can you|could you|for me)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const parts = t
    .split(/\s*(?:,|;|\band then\b|\bthen\b|\band\b)\s*/)
    .map((s) => s.trim())
    .filter(Boolean)
  const steps = []
  for (const s of parts) {
    let m
    if ((m = /^(?:open|go to|go into|show)\s+(?:the\s+|my\s+)?([a-z]+)(?:\s+folder)?$/.exec(s)) && KNOWN[m[1]]) {
      steps.push({ op: 'open', place: m[1] })
    } else if ((m = /^(?:create|make|add)\s+(?:a\s+)?(?:new\s+)?folder(?:\s+(?:called|named)\s+(.+?))?(?:\s+(?:in|inside|on|at)\s+(.+))?$/.exec(s))) {
      steps.push({ op: 'mkdir', name: m[1]?.trim() || null, place: m[2]?.trim() || null })
    } else if ((m = new RegExp(`^(cut|move|copy)\\s+(.+?)(?:\\s+(?:from|in)\\s+(?:the\\s+|my\\s+)?(${KNOWN_RE}))?(?:\\s+(?:to|into|in to|inside)\\s+(.+))?$`).exec(s))) {
      steps.push({ op: m[1] === 'copy' ? 'copy' : 'move', what: m[2].trim(), from: m[3] || null, to: m[4]?.trim() || null })
    } else if ((m = /^paste\s+(?:it|them|that|this)?\s*(?:in|into|to|inside|at)\s+(.+)$/.exec(s))) {
      steps.push({ op: 'paste', to: m[1].trim() })
    } else {
      return null
    }
  }
  // Worth it only for file work (a lone "open downloads" is the other shortcut's).
  return steps.some((x) => x.op !== 'open') ? steps : null
}

/**
 * Run a multi-step file command. `open(path)` shows a folder (the PC tool).
 * Returns what to say, or null when it is not such a command (or a step
 * could not be resolved — then nothing has been changed).
 */
export async function offlineFileSteps(text, { open = async () => {}, home = homedir() } = {}) {
  const steps = plan(text)
  if (!steps) return null
  let here = null // the folder in play
  let made = null // the folder just created (exists only once this runs)
  let held = null // a cut / copied file waiting for "paste"
  const planned = new Set()
  const place = (s) => {
    const p = clean(s)
    if (!p || /^(it|there|here|this|that)$/.test(p)) return here
    if (/\bnew( folder)?$/.test(p) && made) return made // "the new folder" (clean() drops "folder")
    if (KNOWN[p]) return known(p, home)
    // A folder inside the one in play ("the projects folder").
    return here ? findIn(here, p, { folders: true }) : null
  }
  // Dry run first: everything must resolve before anything changes.
  const todo = []
  for (const st of steps) {
    if (st.op === 'open') {
      here = known(st.place, home)
      if (!here) return null
      todo.push({ op: 'open', dir: here })
    } else if (st.op === 'mkdir') {
      const base = st.place ? place(st.place) : (here ?? known('desktop', home))
      if (!base) return null
      const name = st.name ? st.name.replace(/[<>:"/\\|?*]/g, '').trim() : 'New folder'
      if (!name) return null
      const dir = join(base, freeName(base, name, planned))
      planned.add(dir)
      todo.push({ op: 'mkdir', dir })
      here = made = dir
    } else if (st.op === 'paste') {
      if (!held) return null
      const to = place(st.to)
      if (!to) return null
      todo.push({ op: held.copy ? 'copy' : 'move', src: held.src, to })
      held = null
    } else {
      // cut / move / copy: the file is looked for where it was asked, else in the
      // folder opened first, else Downloads.
      const fromDir = st.from ? known(st.from, home) : (todo.find((x) => x.op === 'open')?.dir ?? known('downloads', home))
      const src = fromDir && findIn(fromDir, st.what)
      if (!src) return null
      if (!st.to) {
        held = { src, copy: st.op === 'copy' }
        continue
      }
      const to = place(st.to)
      if (!to) return null
      todo.push({ op: st.op, src, to })
    }
  }
  if (held) return null // cut but never pasted: unclear what was wanted
  // Do it.
  const said = []
  for (const x of todo) {
    if (x.op === 'open') {
      await open(x.dir)
      said.push(`opened ${basename(x.dir)}`)
    } else if (x.op === 'mkdir') {
      mkdirSync(x.dir, { recursive: true })
      said.push(`made the folder "${basename(x.dir)}"`)
    } else {
      const dest = join(x.to, freeName(x.to, basename(x.src)))
      if (x.op === 'copy') cpSync(x.src, dest, { recursive: true })
      else {
        try {
          renameSync(x.src, dest)
        } catch {
          cpSync(x.src, dest, { recursive: true }) // another drive
          rmSync(x.src, { recursive: true, force: true })
        }
      }
      said.push(`${x.op === 'copy' ? 'copied' : 'moved'} ${basename(x.src)} into "${basename(x.to)}"`)
    }
  }
  return `Done: ${said.join(', ')}.`
}
