/**
 * Undo for file changes JARVIS made — by voice, typed, offline or by the model.
 *
 * Every change is recorded as a group of steps (one request = one group):
 *   move / rename  {from, to}   undone by moving it back
 *   copy           {to}         undone by sending the copy to the Recycle Bin
 *   mkdir          {to}         undone by removing the folder, if still empty
 *   recycle        {from}       cannot be put back from here: the user is told
 *                               it is in the Recycle Bin (Restore puts it back)
 * Kept in ~/.jarvis/undo.json (the last 30), so it survives a restart.
 * "Undo" reverses the newest group that has not been undone yet.
 */

import { execFile } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, rmdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, join } from 'node:path'

const FILE = join(homedir(), '.jarvis', 'undo.json')
const KEEP = 30

function load() {
  try {
    const v = JSON.parse(readFileSync(FILE, 'utf8'))
    return Array.isArray(v) ? v : []
  } catch {
    return []
  }
}

function save(list) {
  try {
    mkdirSync(dirname(FILE), { recursive: true })
    writeFileSync(FILE, JSON.stringify(list.slice(-KEEP), null, 1))
  } catch {
    /* undo is a convenience; never a reason for the change itself to fail */
  }
}

/** Record one change (a group of steps). `label` is what was done, for the user. */
export function recordChange(steps, label = '') {
  const clean = (steps ?? []).filter((s) => s && s.op)
  if (!clean.length) return
  const list = load()
  list.push({ at: new Date().toISOString(), label, steps: clean })
  save(list)
}

/** The newest change not yet undone, or null. */
export function lastChange() {
  return load().filter((g) => !g.undone).at(-1) ?? null
}

const recycle = (path) =>
  new Promise((resolve, reject) => {
    const cmd =
      'Add-Type -AssemblyName Microsoft.VisualBasic; ' +
      'if ((Get-Item -LiteralPath $env:JARVIS_S).PSIsContainer) { ' +
      "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($env:JARVIS_S,'OnlyErrorDialogs','SendToRecycleBin') } else { " +
      "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($env:JARVIS_S,'OnlyErrorDialogs','SendToRecycleBin') }"
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', cmd],
      { env: { ...process.env, JARVIS_S: path }, windowsHide: true, timeout: 60_000 },
      (err) => (err ? reject(err) : resolve()),
    )
  })

/**
 * Bring a recycled file or folder back to where it was. Windows keeps each
 * deleted item's original folder (the Recycle Bin's "Original Location"
 * column) and the item itself as $R…; moving that back, and removing its $I…
 * record, is what Explorer's Restore does. Resolves true if it was restored.
 */
const restoreFromBin = (path) =>
  new Promise((resolve) => {
    const cmd = `
$want = $env:JARVIS_S
$dir = Split-Path -Parent $want
$name = Split-Path -Leaf $want
$stem = [IO.Path]::GetFileNameWithoutExtension($name)
$rb = (New-Object -ComObject Shell.Application).Namespace(10)
$hit = $null
foreach ($i in $rb.Items()) {
  if ($rb.GetDetailsOf($i, 1) -ieq $dir -and ($i.Name -ieq $name -or $i.Name -ieq $stem)) { $hit = $i }
}
if (-not $hit) { 'none'; exit }
Move-Item -LiteralPath $hit.Path -Destination $want -ErrorAction Stop
$rec = $hit.Path -replace '\\\\\\$R([^\\\\]+)$', '\\$I$1'
if ($rec -ne $hit.Path) { Remove-Item -LiteralPath $rec -Force -ErrorAction SilentlyContinue }
'ok'`
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', cmd],
      { env: { ...process.env, JARVIS_S: path }, windowsHide: true, timeout: 60_000 },
      (err, out) => resolve(!err && String(out).trim().endsWith('ok')),
    )
  })

function moveBack(from, to) {
  mkdirSync(dirname(from), { recursive: true })
  try {
    renameSync(to, from)
  } catch {
    cpSync(to, from, { recursive: true }) // another drive
    rmSync(to, { recursive: true, force: true })
  }
}

let undoneAt = 0
/** When "undo" last ran (ms): a command repeated after it is a real request again. */
export const lastUndoAt = () => undoneAt

/** Reverse the newest change. Returns what to say. */
export async function undoLast() {
  undoneAt = Date.now()
  const list = load()
  const i = list.findLastIndex((g) => !g.undone)
  if (i < 0) return "There's nothing of mine to undo."
  const group = list[i]
  const did = []
  const couldnt = []
  for (const s of [...group.steps].reverse()) {
    try {
      if (s.op === 'move' || s.op === 'rename') {
        if (!existsSync(s.to)) couldnt.push(`${basename(s.to)} isn't where I put it any more`)
        else if (existsSync(s.from)) couldnt.push(`something called ${basename(s.from)} is back in its old place`)
        else {
          moveBack(s.from, s.to)
          did.push(s.op === 'rename' ? `named it ${basename(s.from)} again` : `put ${basename(s.from)} back in ${basename(dirname(s.from))}`)
        }
      } else if (s.op === 'copy') {
        if (existsSync(s.to)) {
          await recycle(s.to)
          did.push(`sent the copy of ${basename(s.to)} to the Recycle Bin`)
        }
      } else if (s.op === 'mkdir') {
        if (existsSync(s.to)) {
          if (readdirSync(s.to).length) couldnt.push(`the folder ${basename(s.to)} has things in it now, so I left it`)
          else {
            rmdirSync(s.to)
            did.push(`removed the folder ${basename(s.to)}`)
          }
        }
      } else if (s.op === 'recycle') {
        if (existsSync(s.from)) couldnt.push(`something called ${basename(s.from)} is already back in its place`)
        else if (await restoreFromBin(s.from)) did.push(`brought ${basename(s.from)} back from the Recycle Bin`)
        else couldnt.push(`${basename(s.from)} isn't in the Recycle Bin any more (emptied?) — I couldn't bring it back`)
      }
    } catch (err) {
      couldnt.push(`${basename(s.to || s.from || '')}: ${err.message}`)
    }
  }
  group.undone = new Date().toISOString()
  save(list)
  if (!did.length && !couldnt.length) return 'That was already undone.'
  const first = did.length ? `Undone: ${did.join(', ')}.` : "I couldn't undo that."
  return couldnt.length ? `${first} ${couldnt.map((c) => c[0].toUpperCase() + c.slice(1)).join('. ')}.` : first
}

/** "undo", "undo that", "take it back", "put it back" … */
export const UNDO_RE = /^(?:\[.*?\]\s*)?(?:(?:hey |ok |okay )?(?:jarvis|j\.a\.r\.v\.i\.s\.?)[,\s]+)?(?:please\s+)?(?:undo|reverse|revert|take (?:it |that )?back|put (?:it |that )?back)(?:\s+(?:that|it|this|the last (?:change|thing|one)|what you (?:just )?did))?(?:\s+please)?[.!]*$/i
