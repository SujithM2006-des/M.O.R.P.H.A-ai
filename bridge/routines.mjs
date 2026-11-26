/**
 * Named routines: a name for several requests said in one go — "study mode" ->
 * close YouTube, open Notion, volume down. Saved in ~/.jarvis/named-routines.json
 * (NOT routines.json: that is extras.mjs's timed routines — "every day at 7,
 * brief me" — and sharing it crashed the bridge and could overwrite them).
 *
 *   "save a routine called study mode: open notion, close youtube, volume down"
 *   "study mode"  /  "run study mode"  /  "start my study mode routine"
 *   "what routines do I have"  /  "delete the study mode routine"
 *
 * These are understood without a model (server.mjs), so they work offline and
 * on every AI alike; the AI can also save one from looser wording (tools in
 * assistant.mjs).
 */

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

const FILE = join(homedir(), '.jarvis', 'named-routines.json')

const norm = (s) =>
  String(s ?? '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N} ]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()

export function listRoutines() {
  try {
    const v = JSON.parse(readFileSync(FILE, 'utf8'))
    return Array.isArray(v) ? v.filter((r) => r && r.name && Array.isArray(r.steps)) : []
  } catch {
    return []
  }
}

function write(list) {
  mkdirSync(dirname(FILE), { recursive: true })
  writeFileSync(FILE, JSON.stringify(list, null, 2))
}

/** Split "open notion, close youtube and then volume down" into steps. */
export function splitSteps(s) {
  return String(s)
    .split(/\s*(?:,|;|\n|\band then\b|\bthen\b|\bafter that\b)\s*|\s+and\s+(?=(?:open|close|start|launch|play|pause|turn|set|mute|unmute|lock|search|remind|tell|show|read|what|go|move|copy|zip|create|make)\b)/i)
    .map((x) => x.trim().replace(/^and\s+/i, ''))
    .filter(Boolean)
    .slice(0, 12)
}

export function saveRoutine(name, steps) {
  const n = norm(name).replace(/\s+routine$/, '')
  if (!n) throw new Error('A routine needs a name.')
  const list = (Array.isArray(steps) ? steps : splitSteps(steps)).map((x) => String(x).trim()).filter(Boolean).slice(0, 12)
  if (!list.length) throw new Error('A routine needs at least one step.')
  const all = listRoutines().filter((r) => norm(r.name) !== n)
  all.push({ name: n, steps: list, saved: new Date().toISOString() })
  write(all)
  return { name: n, steps: list }
}

export function deleteRoutine(name) {
  const n = norm(name).replace(/\s+routine$/, '')
  const all = listRoutines()
  const left = all.filter((r) => norm(r.name) !== n)
  if (left.length === all.length) return false
  write(left)
  return true
}

/** The routine this request asks to run ("study mode", "run study mode"), or null. */
export function matchRoutine(text) {
  const t = norm(String(text).replace(/^\[.*?\]\s*/, ''))
    .replace(/^(?:hey |ok |okay )?(?:jarvis|j a r v i s) /, '')
    .replace(/^(?:please )?(?:run|start|do|begin|activate|switch to|go into|turn on) /, '')
    .replace(/^(?:my |the )/, '')
    .replace(/ routine$/, '')
    .replace(/ please$/, '')
  if (!t) return null
  return listRoutines().find((r) => norm(r.name) === t) ?? null
}

/**
 * A routine command: save / list / delete. Returns what to say, or null if
 * the request is not one.
 */
export function routineCommand(text) {
  const t = String(text).replace(/^\[.*?\]\s*/, '').trim().replace(/[.!?]+$/, '')
  let m
  if ((m = /^(?:please\s+)?(?:save|create|make|add|set up|remember)\s+(?:a\s+|new\s+|a new\s+)?routine\s+(?:called|named)\s+["“]?(.+?)["”]?\s*(?::|\s+that\s+(?:will\s+)?|\s+to\s+|\s+which\s+|\s+where you\s+|\s+-\s+)\s*(.+)$/is.exec(t))) {
    const r = saveRoutine(m[1], m[2])
    return `Saved the "${r.name}" routine: ${r.steps.join('; ')}. Say "${r.name}" to run it.`
  }
  if (/^(?:what|which|list|show)(?:\s+(?:are|me))?\s+(?:my|the|all)?\s*routines(?:\s+do i have)?$|^(?:what|which) routines do i have$/i.test(t)) {
    const all = listRoutines()
    if (!all.length) return 'You have no routines yet. Say, for example: "save a routine called study mode: open Notion, close YouTube, volume down".'
    return `Your routines: ${all.map((r) => `${r.name} (${r.steps.length} step${r.steps.length === 1 ? '' : 's'})`).join(', ')}.`
  }
  if ((m = /^(?:please\s+)?(?:delete|remove|forget)\s+(?:the\s+|my\s+)?(?:routine\s+(?:called\s+|named\s+)?)?["“]?(.+?)["”]?(?:\s+routine)?$/i.exec(t)) && listRoutines().some((r) => norm(r.name) === norm(m[1]))) {
    deleteRoutine(m[1])
    return `Deleted the "${norm(m[1])}" routine.`
  }
  return null
}
