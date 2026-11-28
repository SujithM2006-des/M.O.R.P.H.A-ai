import { bfetch } from '../lib/bridgeAuth'
import { useEffect, useState, useSyncExternalStore } from 'react'
import { BRIDGE_HTTP_URL } from '../config'
import { useStore } from '../store'

/**
 * Everything a custom layout (CustomLayout.tsx) may use: live data and
 * actions, so a layout written by JARVIS from a picture works for real rather
 * than as a mock-up. Import from './kit' — nothing else in the app.
 */

export type Status = {
  time: number
  cpu: number
  cores: number
  cpuModel: string
  memUsed: number
  memTotal: number
  uptime: number
  host: string
  user: string
  /** Their first name, from JARVIS's memory; null if unknown. */
  name: string | null
  /** GPU 3D-engine use, 0–100; refreshed every 30 s. */
  gpu: number | null
  battery: number | null
  charging: boolean
  wifi: string | null
  signal: number | null
  diskFree: number | null
  diskTotal: number | null
  weather: {
    city: string
    temp: number
    feels: number
    humidity: number
    wind: number
    cond: string
    hi: number
    lo: number
    rain: number
  } | null
  reminders: { at: string; text: string; kind: string; repeat: string | null }[]
}

// ---------------------------------------------------------------------------
// Hiding stock parts
// ---------------------------------------------------------------------------

/** Stock parts a layout can replace. */
export type StockPart =
  | 'frame' | 'header' | 'telemetry' | 'dock' | 'suggestions' | 'scene'
  | 'scanlines' | 'caption' | 'hints' | 'transcript' | 'error'
  /** The "ACCESSING <tool>" badge at the top while a tool runs. */
  | 'toolbadge'
  /** The diagonal light sweeps (and the tool name riding them) while a tool runs. */
  | 'sweep'

let hidden: readonly string[] = []
const hiddenSubs = new Set<() => void>()

/** Set which stock parts are hidden (cl-hide-* classes, see hide.css). */
export function setHidden(parts: readonly string[]) {
  const root = document.documentElement
  for (const c of [...root.classList]) if (c.startsWith('cl-hide-')) root.classList.remove(c)
  for (const p of parts) root.classList.add(`cl-hide-${p}`)
  hidden = [...parts]
  hiddenSubs.forEach((f) => f())
}

/** The stock parts hidden right now — the app skips rendering them entirely. */
export function useHidden(): readonly string[] {
  return useSyncExternalStore(
    (f) => {
      hiddenSubs.add(f)
      return () => hiddenSubs.delete(f)
    },
    () => hidden,
  )
}

/**
 * Called at the top of a layout: the stock parts it replaces. Kept inside the
 * layout (not a second export) so the file holds nothing but the component —
 * which lets a new layout swap in live instead of reloading the page, which
 * used to cut off the conversation that asked for it.
 */
export function useHide(parts: readonly StockPart[]) {
  const key = parts.join(',')
  useEffect(() => {
    setHidden(key ? key.split(',') : [])
    return () => setHidden([])
  }, [key])
}

// The safety net (LayoutBoundary) is told to give a corrected layout another go.
const retrySubs = new Set<() => void>()
export function onLayoutRetry(fn: () => void) {
  retrySubs.add(fn)
  return () => retrySubs.delete(fn)
}
export function retryLayout() {
  retrySubs.forEach((f) => f())
}
let layoutError: string | null = null
export function reportLayoutError(message: string | null) {
  layoutError = message
}
export function lastLayoutError() {
  return layoutError
}

/** PC readings, weather and reminders from the bridge, refreshed every few seconds. */
export function useStatus(ms = 3000): Status | null {
  const [s, set] = useState<Status | null>(null)
  useEffect(() => {
    let alive = true
    const pull = async () => {
      try {
        const res = await bfetch(`${BRIDGE_HTTP_URL}/status`, { cache: 'no-store' })
        if (res.ok && alive) set(await res.json())
      } catch {
        /* bridge down: keep the last reading */
      }
    }
    void pull()
    const id = window.setInterval(pull, ms)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [ms])
  return s
}

/**
 * Is the bridge answering right now? Checked every 4 s. The panels keep
 * their last reading when it stops (so they don't go blank), which is why
 * this is separate: with the bridge stopped, "Link" stayed green and System
 * Status said LIVE until something was asked.
 */
export function useBridgeUp(): boolean {
  return useHealth().up
}

/**
 * The live state for the status chips, from the bridge's /health (every 4 s):
 *   up        the background service answers
 *   brain     'cloud' (online), 'local' (offline, on the local model) or 'none'
 *   listener  the background "Hey <name>" listener: 'listening', 'muted',
 *             'off' (the kill switch) or 'stopped' (not running)
 * One poll shared by every chip that reads it.
 */
export type Health = { up: boolean; brain: 'cloud' | 'local' | 'none'; listener: 'listening' | 'muted' | 'off' | 'stopped' }
let health: Health = { up: true, brain: 'cloud', listener: 'listening' }
const healthSubs = new Set<() => void>()
let healthTimer = 0
async function pollHealth() {
  let next: Health
  try {
    const r = await bfetch(`${BRIDGE_HTTP_URL}/health`, { cache: 'no-store', signal: AbortSignal.timeout(2500) })
    const j = (await r.json().catch(() => ({}))) as Partial<Health> & { brain?: string; listener?: string }
    next = {
      up: r.ok,
      brain: j.brain === 'local' || j.brain === 'none' ? j.brain : 'cloud',
      listener: j.listener === 'muted' || j.listener === 'off' || j.listener === 'stopped' ? j.listener : 'listening',
    }
  } catch {
    next = { ...health, up: false }
  }
  if (next.up !== health.up || next.brain !== health.brain || next.listener !== health.listener) {
    health = next
    healthSubs.forEach((f) => f())
  }
}
export function useHealth(): Health {
  const [, bump] = useState(0)
  useEffect(() => {
    const f = () => bump((n) => n + 1)
    healthSubs.add(f)
    if (healthSubs.size === 1) {
      void pollHealth()
      healthTimer = window.setInterval(pollHealth, 4000)
    }
    return () => {
      healthSubs.delete(f)
      if (!healthSubs.size) window.clearInterval(healthTimer)
    }
  }, [])
  return health
}

const muteSubs = new Set<() => void>()

/** Whether the microphone is muted (from the popup or by voice), refreshed every 2 s. */
export function useMuted(): boolean {
  const [m, set] = useState(false)
  const [bump, setBump] = useState(0)
  // Re-read at once after a tap on a mute button, not on the next 2 s tick.
  useEffect(() => {
    const f = () => setBump((b) => b + 1)
    muteSubs.add(f)
    return () => {
      muteSubs.delete(f)
    }
  }, [])
  useEffect(() => {
    let alive = true
    const pull = async () => {
      try {
        const res = await bfetch(`${BRIDGE_HTTP_URL}/popup/state`, { cache: 'no-store' })
        if (res.ok && alive) set(Boolean((await res.json()).muted))
      } catch {
        /* bridge down: keep the last reading */
      }
    }
    void pull()
    const id = window.setInterval(pull, 2000)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [bump])
  return m
}

/** This person's profile (setup screen): their name, the assistant's name, look and features. */
export type Profile = {
  configured: boolean
  name: string
  city: string
  assistant: string
  theme: string
  /** The centre orb's design (see orbs.tsx). */
  orb: string
  /** Gmail, Calendar & Drive through the claude.ai account (off by default: costs usage). */
  connectors?: boolean
  /** Ask before closing an app or sending a file to the Recycle Bin (on unless switched off). */
  askFirst?: boolean
  features: Record<string, boolean>
  /** Who made JARVIS. Fixed in the code; not part of anyone's settings. */
  creator: string
}

const profileSubs = new Set<() => void>()
let profileCache: Profile | null = null

/** Read the profile again (after setup saves it). */
export function refreshProfile() {
  profileCache = null
  profileSubs.forEach((f) => f())
}

/** The profile, or null until it has loaded. */
export function useProfile(): Profile | null {
  const [p, set] = useState<Profile | null>(profileCache)
  const [bump, setBump] = useState(0)
  useEffect(() => {
    const f = () => setBump((b) => b + 1)
    profileSubs.add(f)
    return () => {
      profileSubs.delete(f)
    }
  }, [])
  useEffect(() => {
    let alive = true
    bfetch(`${BRIDGE_HTTP_URL}/profile`, { cache: 'no-store' })
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        if (alive && j) {
          profileCache = j
          set(j)
        }
      })
      .catch(() => {})
    return () => {
      alive = false
    }
  }, [bump])
  return p
}

/** The AI models JARVIS can think with, for the model dropdown. */
export type Brains = {
  /** "auto" or a provider id, as picked in the dropdown. */
  choice: string
  /** The provider answering now (Auto's pick, or the fallback after a limit). */
  active: string | null
  activeLabel: string
  options: { id: string; label: string; unavailable: string }[]
}

const brainSubs = new Set<() => void>()

/** The model dropdown's state, refreshed every 5 s and at once after a change. */
export function useBrains(): Brains | null {
  const [b, set] = useState<Brains | null>(null)
  const [bump, setBump] = useState(0)
  useEffect(() => {
    const f = () => setBump((x) => x + 1)
    brainSubs.add(f)
    return () => {
      brainSubs.delete(f)
    }
  }, [])
  useEffect(() => {
    let alive = true
    const pull = async () => {
      try {
        const res = await bfetch(`${BRIDGE_HTTP_URL}/brains`, { cache: 'no-store' })
        if (res.ok && alive) set(await res.json())
      } catch {
        /* bridge down: keep the last reading */
      }
    }
    void pull()
    const id = window.setInterval(pull, 5000)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [bump])
  return b
}

/** Pick the model ("auto" or a provider id). */
export const setBrain = (choice: string) =>
  post('/brain', { choice }).then((ok) => {
    brainSubs.forEach((f) => f())
    return ok
  })

/** One AI's usage over a period. `input` includes new cache writes. */
export type UsageLine = { requests: number; input: number; output: number; cached: number; cost: number; limits: number }
/** One limit meter: "Session (5hr) 54%, resets at 3:40 PM". */
export type LimitMeter = { label: string; pct: number; detail?: string; resetsAt?: string | null }
export type Usage = {
  day: string
  today: Record<string, UsageLine>
  week: Record<string, UsageLine>
  /** Per connected AI: its limit meters (as the provider reports them) and a note. */
  limits: Record<string, { note: string | null; meters: LimitMeter[] }>
  brains: Brains
  labels: Record<string, string>
}

/** Model usage per AI (today and the last 7 days), refreshed every 10 s. */
export function useUsage(): Usage | null {
  const [u, set] = useState<Usage | null>(null)
  useEffect(() => {
    let alive = true
    const pull = async () => {
      try {
        const res = await bfetch(`${BRIDGE_HTTP_URL}/usage`, { cache: 'no-store' })
        if (res.ok && alive) set(await res.json())
      } catch {
        /* bridge down: keep the last reading */
      }
    }
    void pull()
    const id = window.setInterval(pull, 10_000)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [])
  return u
}

/** Open the setup screen (name, city, voice, look, features). */
export function openSetup() {
  window.dispatchEvent(new Event('jarvis-setup'))
}

/**
 * The assistant's name as it is said: the dots dropped ("J.A.R.V.I.S." ->
 * "JARVIS"), so speech reads it as one word. Same rule as bridge/profile.mjs.
 */
export function spokenName(n: string | null | undefined): string {
  const s = String(n ?? '')
    .replace(/\.+/g, '')
    .replace(/\s+/g, ' ')
    .trim()
  return s || 'MORPHA'
}

/** The assistant's name as it is written: a dot after every letter ("Friday" -> "F.R.I.D.A.Y."). */
export function dottedName(n: string | null | undefined): string {
  return spokenName(n)
    .toUpperCase()
    .split(' ')
    .map((w) => [...w].filter((c) => /[\p{L}\p{N}]/u.test(c)).join('.') + '.')
    .join(' ')
}

/** The assistant's name as a title (window, wordmark): dotted, "M.O.R.P.H.A.". */
export function assistantTitle(p: Profile | null): string {
  return dottedName(p?.assistant)
}

/** The assistant's name as said, in ordinary capitals: "Morpha", "Mr Bean". */
export function saidName(p: Profile | null): string {
  return spokenName(p?.assistant)
    .toLowerCase()
    .replace(/(^|\s)(\p{L})/gu, (_m, a: string, b: string) => a + b.toUpperCase())
}

/** saidName() for the current profile, kept up to date (for labels and hints). */
export function useSaidName(): string {
  return saidName(useProfile())
}

/** A calendar event: a reminder, pending or already past. */
export type CalEvent = { id: string; at: string; text: string; kind: string; repeat: string | null; done: boolean }

let scheduleBump = 0
const scheduleSubs = new Set<() => void>()
const bumpSchedule = () => {
  scheduleBump++
  scheduleSubs.forEach((f) => f())
}

/** Every calendar event (refreshed every 30 s, and at once after a change). */
export function useSchedule(): CalEvent[] {
  const [events, set] = useState<CalEvent[]>([])
  const [bump, setBump] = useState(scheduleBump)
  useEffect(() => {
    const f = () => setBump(scheduleBump)
    scheduleSubs.add(f)
    return () => {
      scheduleSubs.delete(f)
    }
  }, [])
  useEffect(() => {
    let alive = true
    const pull = async () => {
      try {
        const res = await bfetch(`${BRIDGE_HTTP_URL}/schedule`, { cache: 'no-store' })
        if (res.ok && alive) set((await res.json()).events ?? [])
      } catch {
        /* bridge down: keep the last list */
      }
    }
    void pull()
    const id = window.setInterval(pull, 30_000)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [bump])
  return events
}

/** Add an event at a local date and time ("2026-11-15T10:00"). Returns an error message, or null. */
export async function addEvent(at: string, text: string): Promise<string | null> {
  try {
    const res = await bfetch(`${BRIDGE_HTTP_URL}/schedule`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ at: new Date(at).toISOString(), text }),
    })
    const body = await res.json()
    bumpSchedule()
    return res.ok ? null : String(body.error ?? 'Could not save it.')
  } catch {
    return 'The app is not running.'
  }
}

/** Remove an event. */
export async function removeEvent(id: string): Promise<void> {
  try {
    await bfetch(`${BRIDGE_HTTP_URL}/schedule/delete`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id }),
    })
  } finally {
    bumpSchedule()
  }
}

/** The current time, ticking. */
export function useNow(ms = 1000): Date {
  const [now, set] = useState(() => new Date())
  useEffect(() => {
    const id = window.setInterval(() => set(new Date()), ms)
    return () => window.clearInterval(id)
  }, [ms])
  return now
}

export type JarvisPhase = 'offline' | 'boot' | 'dormant' | 'waking' | 'listening' | 'thinking' | 'tooling' | 'speaking'

/** JARVIS's live state: phase, voice level (0–1), the caption being heard,
 *  the conversation so far, and the tool at work. */
export function useJarvis() {
  const phase = useStore((s) => s.phase) as JarvisPhase
  const level = useStore((s) => s.level)
  const caption = useStore((s) => s.caption)
  const turns = useStore((s) => s.turns)
  const activeTool = useStore((s) => s.activeTool)
  const error = useStore((s) => s.error)
  return { phase, level, caption, turns, activeTool, error }
}

/**
 * Sessions: separate conversations, each with its own agent, running side by
 * side. Requests go to the one on screen (`active`); the others carry on in
 * the background and show `busy` while they work.
 */
export function useSessions() {
  const sessions = useStore((s) => s.sessions)
  const active = useStore((s) => s.activeSession)
  return { sessions, active }
}
export const newSession = () => useStore.getState().newSession()
export const switchSession = (id: string) => useStore.getState().switchSession(id)
export const closeSession = (id: string) => useStore.getState().closeSession(id)

/**
 * The chat view: the session on screen shown as a chat (full transcript,
 * written answers with formatting) instead of the orb. Turned on by a typed
 * request for written content or a long written answer; off with the orb.
 */
export function useChat(): boolean {
  return useStore((s) => Boolean(s.sessions.find((x) => x.id === s.activeSession)?.chat))
}
export const setChat = (on: boolean) => useStore.getState().setChat(on)

export type { Turn } from '../store'

/**
 * Thumbs up / down on an answer (again, or null, to take it back). Kept on
 * the turn and sent to the bridge, which remembers recent thumbs-down notes
 * so the same mistake isn't repeated. `reason`: optional, for a thumbs down.
 */
export function rateAnswer(turnId: string, vote: 'up' | 'down' | null, request: string, reply: string, reason = '') {
  useStore.getState().setFeedback(turnId, vote)
  return post('/feedback', { vote, request, reply, reason })
}

/** Ask again for a different answer: the old exchange goes, the request is resent. */
export function retryAnswer(userTurnId: string, request: string) {
  useStore.getState().dropFrom(userTurnId)
  return ask(`[Retry] ${request}`)
}

/** The user's past requests, oldest first (for ↑/↓ in the text box). */
export function usePromptHistory(): string[] {
  return useStore((s) => s.promptHistory)
}

/** Stop the answer being made in the session on screen (voice, generation, tokens). */
export function stopAnswer() {
  window.dispatchEvent(new Event('jarvis-stop'))
}

/** Read a written answer aloud (code blocks skipped); stop with stopReading(). */
export function readAloud(text: string) {
  window.dispatchEvent(new CustomEvent('jarvis-read', { detail: text }))
}
export function stopReading() {
  window.dispatchEvent(new Event('jarvis-read-stop'))
}

/** Whether the session on screen is working on a request. */
export function useSessionBusy(): boolean {
  return useStore((s) => Boolean(s.sessions.find((x) => x.id === s.activeSession)?.busy))
}

/** A short word for the phase, for a status pill. */
export const phaseLabel: Record<JarvisPhase, string> = {
  // Not started yet: the browser holds sound back until the first click or
  // key, and that click starts him. "Offline", in red, read as broken.
  offline: 'Tap to start',
  boot: 'Starting',
  // At rest and ready. (It said "Online", which read as the internet status -
  // and stayed "Online" when the internet was gone. That has its own pill now.)
  dormant: 'Ready',
  waking: 'Listening',
  listening: 'Listening',
  thinking: 'Thinking',
  tooling: 'Working',
  speaking: 'Speaking',
}

/** "Good morning" / "Good afternoon" / "Good evening". */
export function greeting(d: Date = new Date()): string {
  const h = d.getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
}

const post = (path: string, body?: unknown) =>
  bfetch(`${BRIDGE_HTTP_URL}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  }).then(
    (r) => r.ok,
    () => false,
  )

/**
 * Send a typed request, exactly as if it were spoken — to this window only.
 * It used to go through the bridge, which hands typed requests to every open
 * window, so with two open (or a browser tab too) each one answered it and
 * Claude was paid twice. The bridge is the fallback for when this window
 * cannot take it itself (still starting).
 */
export const ask = (text: string): Promise<boolean> => {
  const t = text.trim()
  if (!t) return Promise.resolve(false)
  const local = (window as unknown as { __jarvisAsk?: (text: string) => boolean }).__jarvisAsk
  if (local?.(t)) return Promise.resolve(true)
  return post('/popup/ask', { text: t })
}
/** Files that can be attached: documents, pictures, voice clips, videos. */
export const ATTACH_ACCEPT =
  'image/*,video/*,audio/*,.pdf,.docx,.pptx,.xlsx,.doc,.ppt,.xls,.txt,.md,.csv,.json,.py,.java,.c,.cpp,.js,.ts,.html,.css'

/** The most files one request can carry (the bridge takes ten). */
export const MAX_ATTACH = 10

/**
 * Attach files to a request from this window: each is uploaded to the bridge
 * (a page cannot hand over file paths), then made ready there exactly as the
 * popup's files are - a video becomes stills plus a transcript of what is said,
 * Office files become text. Returns the block that goes under the request (""
 * if nothing could be attached) and any problems, for showing.
 */
export async function attachFiles(files: File[]): Promise<{ block: string; problems: string[] }> {
  const paths: string[] = []
  const problems: string[] = []
  for (const f of files.slice(0, MAX_ATTACH)) {
    try {
      const r = await bfetch(`${BRIDGE_HTTP_URL}/upload`, {
        method: 'POST',
        headers: { 'content-type': 'application/octet-stream', 'x-file-name': encodeURIComponent(f.name || 'pasted-image.png') },
        body: f,
      })
      const j = (await r.json().catch(() => ({}))) as { path?: string; error?: string }
      if (r.ok && j.path) paths.push(j.path)
      else problems.push(`${f.name}: ${j.error ?? `upload failed (${r.status})`}`)
    } catch {
      problems.push(`${f.name}: the app's background service is not answering`)
    }
  }
  if (!paths.length) return { block: '', problems }
  try {
    const r = await bfetch(`${BRIDGE_HTTP_URL}/attach`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ paths }),
    })
    const j = (await r.json().catch(() => ({}))) as { block?: string; problems?: string[] }
    return { block: j.block ?? '', problems: [...problems, ...(j.problems ?? [])] }
  } catch {
    return { block: '', problems: [...problems, "the app's background service is not answering"] }
  }
}

/** A request with its files as a person would say it: "summarise this 📎 report.pdf". */
export function shownRequest(text: string): string {
  return String(text ?? '')
    .replace(/\n\n\[Attached files: ([^\]\n]*)\][\s\S]*$/, (_m, names: string) => ` 📎 ${names.split(' | ').join(', ')}`)
    .trim()
}

/** Start listening now (or, if already listening, stand by). */
export const listen = () => post('/popup/mic')
/** Mute or unmute the microphone (toggles without an argument). */
export const mute = (on?: boolean) =>
  post('/popup/mute', on === undefined ? {} : { on }).then((ok) => {
    muteSubs.forEach((f) => f())
    return ok
  })
/** Circle to Search. */
export const circle = () => post('/circle')
/** Open the onscreen popup. */
export const openPopup = () => post('/popup/show')

export type LaunchId = 'chrome' | 'files' | 'whatsapp' | 'code' | 'spotify' | 'terminal' | 'settings' | 'calculator' | 'notepad'
/** Open one of the dock apps. */
export const launch = (app: LaunchId) => post('/launch', { app })
