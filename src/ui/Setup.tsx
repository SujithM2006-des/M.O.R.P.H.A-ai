import { bfetch } from '../lib/bridgeAuth'
import { useEffect, useState } from 'react'
import { BRIDGE_HTTP_URL } from '../config'
import {
  currentOfflineVoice,
  currentRate,
  currentVoiceName,
  isNatural,
  NATURAL,
  previewVoice,
  setVoiceProfile,
  STANDARD_VOICES,
} from '../lib/tts'
import { assistantTitle, dottedName, refreshProfile, saidName, spokenName, useProfile, type Profile } from '../custom/kit'

/** "JARVIS" -> "Jarvis", for showing how the name is said. */
const nameWord = (s: string) => s.toLowerCase().replace(/(^|\s)(\p{L})/gu, (_m, a, b) => a + b.toUpperCase())
import { ORBS, Orb } from '../custom/orbs'
import './setup.css'

/**
 * Setup: who this copy of JARVIS works for, and how it looks and sounds.
 *
 * Opens by itself the first time (no ~/.jarvis/profile.json yet), and again
 * from the sidebar's Profile button. The creator line at the bottom comes from
 * the bridge, where it is fixed in the code — it is not a setting.
 */

/**
 * The interface's blue turned by `deg`, with the same matrix as CSS
 * hue-rotate() — so each swatch shows exactly the colour the interface (and
 * the popup, which uses the same maths) will take.
 */
function turned(hex: string, deg: number) {
  const n = parseInt(hex.slice(1), 16)
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255]
  const a = (deg * Math.PI) / 180
  const c = Math.cos(a)
  const s = Math.sin(a)
  const ch = (v: number) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')
  return (
    '#' +
    ch(r * (0.213 + c * 0.787 - s * 0.213) + g * (0.715 - c * 0.715 - s * 0.715) + b * (0.072 - c * 0.072 + s * 0.928)) +
    ch(r * (0.213 - c * 0.213 + s * 0.143) + g * (0.715 + c * 0.285 + s * 0.14) + b * (0.072 - c * 0.072 - s * 0.283)) +
    ch(r * (0.213 - c * 0.213 - s * 0.787) + g * (0.715 - c * 0.715 + s * 0.715) + b * (0.072 + c * 0.928 + s * 0.072))
  )
}

// In hue order round the wheel. Hues must match bridge/profile.mjs and
// scripts/popup.ps1.
const THEMES: { id: string; label: string; hue: number; swatch: string }[] = [
  ['blue', 'Blue', 0],
  ['indigo', 'Indigo', 30],
  ['purple', 'Purple', 70],
  ['magenta', 'Magenta', 115],
  ['crimson', 'Crimson', 150],
  ['orange', 'Orange', 180],
  ['amber', 'Amber', 200],
  ['yellow', 'Yellow', 220],
  ['lime', 'Lime', -110],
  ['green', 'Green', -60],
  ['teal', 'Teal', -25],
].map(([id, label, hue]) => ({ id: id as string, label: label as string, hue: hue as number, swatch: turned('#3fb6ff', hue as number) }))

/** From the bridge's /accounts: connected or not (null: still checking), and sign-ins in progress. */
type Accounts = Record<'gemini' | 'groq' | 'openrouter' | 'chatgpt', { connected: boolean | null }> & {
  /** Claude through Claude Code: optional, Jarvis works on the free AIs without it. */
  claude?: { connected: boolean; plan: string | null; expired: boolean; off?: boolean }
  running: boolean
  jobs: Record<string, { state: string; note: string }>
}

/** The AI accounts in setup: sign in once, JARVIS sets up the rest. `key`: it gets a key (can be disconnected). */
const ACCOUNTS: { id: 'gemini' | 'groq' | 'openrouter' | 'chatgpt'; label: string; what: string; key: boolean }[] = [
  { id: 'gemini', label: 'Gemini', what: 'Google — also AI videos in the Gemini app and Google Flow', key: true },
  { id: 'groq', label: 'Groq', what: 'Free, very fast answers', key: true },
  { id: 'openrouter', label: 'OpenRouter', what: 'Free models from many makers', key: true },
  { id: 'chatgpt', label: 'ChatGPT', what: 'Pictures of your story characters (Disconnect to switch accounts)', key: true },
]

const FEATURES: { id: string; label: string; note: string }[] = [
  { id: 'pc', label: 'PC control', note: 'Open apps, manage files, run commands' },
  { id: 'browser', label: 'Browser', note: 'Read and act in your Chrome' },
  { id: 'whatsapp', label: 'WhatsApp', note: 'Send messages and files' },
  { id: 'camera', label: 'Camera', note: 'See through your webcam when asked' },
]

/** The interface colour: a hue turn from the stock blue (none for blue). */
function applyTheme(id: string | undefined) {
  const hue = THEMES.find((t) => t.id === id)?.hue ?? 0
  const root = document.documentElement
  if (hue) {
    root.style.setProperty('--theme-hue', `${hue}deg`)
    root.dataset.themeHue = '1'
  } else {
    root.style.removeProperty('--theme-hue')
    delete root.dataset.themeHue
  }
}

export function Setup() {
  const profile = useProfile()
  const who = saidName(profile)
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<Profile | null>(null)
  const [voice, setVoice] = useState('')
  const [rate, setRate] = useState(1)
  // AI provider keys: what is saved (masked, "••••1234") and what was typed
  // here (a new key, or null to remove one). Never shown in full.
  // Which AI accounts are connected (and any sign-in in progress).
  const [accounts, setAccounts] = useState<Accounts | null>(null)
  /** The account being disconnected right now ('' when none). */
  const [leaving, setLeaving] = useState('')
  // ChatGPT's sign-in has been looked at (even if the answer was "unknown",
  // with JARVIS's Chrome window closed): stop showing "Checking…".
  const [checked, setChecked] = useState(false)
  // The check-up's results (null until run).
  const [checkItems, setCheckItems] = useState<{ name: string; ok: boolean; note: string }[] | null>(null)
  const [checking, setChecking] = useState(false)
  const [keyInput, setKeyInput] = useState<Record<string, string | null>>({})
  const [voices, setVoices] = useState<{ name: string; lang: string }[]>([])
  /** The voice picked for offline here ('' = unchanged). */
  const [offVoice, setOffVoice] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState('')

  // First run: open by itself. Always: keep the chosen colour applied.
  useEffect(() => {
    if (!profile) return
    applyTheme(profile.theme)
    // The window's title (title bar, taskbar) is the assistant's name too. The
    // popup and scripts find this window by it (they read the same profile).
    document.title = assistantTitle(profile)
    if (!profile.configured) setOpen(true)
  }, [profile])

  useEffect(() => {
    const f = () => setOpen(true)
    window.addEventListener('jarvis-setup', f)
    return () => window.removeEventListener('jarvis-setup', f)
  }, [])

  // Fresh copy of the profile each time the screen opens.
  useEffect(() => {
    if (open && profile) {
      setForm({ ...profile, assistant: dottedName(profile.assistant), features: { ...profile.features } })
      setVoice('')
      setOffVoice('')
      setRate(Math.round(currentRate() * 20) / 20)
      setKeyInput({})
      // The keys first (quick), then ChatGPT's sign-in too (a few seconds).
      bfetch(`${BRIDGE_HTTP_URL}/accounts`, { cache: 'no-store' })
        .then((r) => (r.ok ? r.json() : null))
        .then((a) => a && setAccounts(a))
        .catch(() => {})
      setChecked(false)
      bfetch(`${BRIDGE_HTTP_URL}/accounts?check=1`, { cache: 'no-store' })
        .then((r) => (r.ok ? r.json() : null))
        .then((a) => a && setAccounts(a))
        .catch(() => {})
        .finally(() => setChecked(true))
      setError('')
      setSaving('')
    }
  }, [open, profile])

  // Esc closes it like Cancel (the calendar already did; this didn't). Not on
  // the first-run screen, which has nothing to go back to.
  useEffect(() => {
    if (!open || !profile?.configured) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || saving) return
      speechSynthesis.cancel()
      applyTheme(profile?.theme)
      setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, profile, saving])

  // The voices installed on the PC (the offline ones) arrive asynchronously in Chrome.
  useEffect(() => {
    if (!open) return
    const load = () =>
      setVoices(speechSynthesis.getVoices().filter((v) => v.localService).map((v) => ({ name: v.name, lang: v.lang })))
    load()
    speechSynthesis.addEventListener('voiceschanged', load)
    return () => speechSynthesis.removeEventListener('voiceschanged', load)
  }, [open])

  if (!open || !form) return null
  const firstRun = !profile?.configured

  // The account list: "Sign in" runs the sign-in in JARVIS's window (the
  // bridge fetches the key itself); its progress shows until it is done.
  const loadAccounts = async (check = false) => {
    try {
      const r = await bfetch(`${BRIDGE_HTTP_URL}/accounts${check ? '?check=1' : ''}`, { cache: 'no-store' })
      if (r.ok) setAccounts(await r.json())
    } catch {
      /* JARVIS not running: the list stays as it was */
    }
  }
  const signIn = async (id: string) => {
    try {
      await bfetch(`${BRIDGE_HTTP_URL}/keys/auto`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ providers: [id] }),
      })
    } catch {
      setError(`${who} is not running, so that sign-in could not start.`)
      return
    }
    await loadAccounts()
    const poll = window.setInterval(async () => {
      try {
        const s = await (await bfetch(`${BRIDGE_HTTP_URL}/accounts`, { cache: 'no-store' })).json()
        setAccounts(s)
        if (!s.running) window.clearInterval(poll)
      } catch {
        /* try again next tick */
      }
    }, 2000)
  }
  // Disconnect: a key is removed; ChatGPT is signed out in JARVIS's window
  // (so another account can be signed in).
  const disconnect = async (id: string) => {
    setLeaving(id)
    if (id === 'chatgpt') {
      await bfetch(`${BRIDGE_HTTP_URL}/accounts/chatgpt/logout`, { method: 'POST' }).catch(() => {})
    } else {
      await bfetch(`${BRIDGE_HTTP_URL}/keys`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ [id]: null }),
      }).catch(() => {})
    }
    await loadAccounts()
    setLeaving('')
  }
  // Claude card: Disconnect stops Morpha using Claude; its Claude Code sign-in is
  // kept, so Connect brings it back. Nothing is signed out of Claude itself.
  const toggleClaude = async (off: boolean) => {
    setLeaving(off ? 'claude' : 'claude-on')
    await bfetch(`${BRIDGE_HTTP_URL}/accounts/claude`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ off }),
    }).catch(() => {})
    await loadAccounts()
    setLeaving('')
  }
  const set = (patch: Partial<Profile>) => setForm({ ...form, ...patch })
  const runCheckup = async () => {
    setChecking(true)
    try {
      const r = await bfetch(`${BRIDGE_HTTP_URL}/checkup`, { cache: 'no-store' })
      if (r.ok) setCheckItems((await r.json()).items)
      else setCheckItems([{ name: who, ok: false, note: `The check-up failed (${r.status}).` }])
    } catch {
      setCheckItems([{ name: who, ok: false, note: `${who} isn't running — start it, then check again.` }])
    } finally {
      setChecking(false)
    }
  }

  // The same sentence for every voice, so they can be compared fairly.
  // Said as a word ("Jarvis"), never letter by letter.
  const sample = `Hello! I'm ${nameWord(spokenName(form.assistant))}, your personal assistant. How can I help you today?`
  // Each language's voices say it in that language, so they can be judged
  // as they will sound.
  const me = nameWord(spokenName(form.assistant))
  const SAMPLES: Record<string, string> = {
    Tamil: `வணக்கம்! நான் ${me}, உங்கள் தனிப்பட்ட உதவியாளர். இன்று நான் உங்களுக்கு எப்படி உதவலாம்?`,
    Hindi: `नमस्ते! मैं ${me} हूँ, आपका निजी सहायक। आज मैं आपकी कैसे मदद कर सकता हूँ?`,
    Malayalam: `നമസ്കാരം! ഞാൻ ${me}, നിങ്ങളുടെ സ്വകാര്യ സഹായി. ഇന്ന് ഞാൻ നിങ്ങളെ എങ്ങനെ സഹായിക്കട്ടെ?`,
    Telugu: `నమస్కారం! నేను ${me}, మీ వ్యక్తిగత సహాయకుడిని. ఈ రోజు నేను మీకు ఎలా సహాయం చేయగలను?`,
  }
  const sampleFor = (language: string) => SAMPLES[language] ?? sample
  const sampleOf = (name: string) =>
    sampleFor(STANDARD_VOICES.find((v) => NATURAL + v.id === name)?.language ?? 'English')

  // The two picks: online (any voice) and offline (a voice on the PC). The PC
  // voice that would be used offline if none was picked is shown as chosen.
  const online = voice || currentVoiceName()
  const offline =
    offVoice || currentOfflineVoice() || (voices.find((v) => /david|mark|george|ravi/i.test(v.name)) ?? voices[0])?.name || ''
  const short = (name: string) =>
    isNatural(name)
      ? (() => {
          const s = STANDARD_VOICES.find((v) => NATURAL + v.id === name)
          return s ? `${s.name} (${s.language})` : name.slice(NATURAL.length).replace(/Neural$/, '')
        })()
      : name.replace(/^(Microsoft|Google)\s+/, '').replace(/\s+-\s+.*$/, '').replace(/\s+Desktop$/, '')

  // Skip: keep the defaults. It still counts as set up, so this screen does
  // not come back by itself; the sidebar's Profile button reopens it.
  const save = async (skip = false) => {
    setError('')
    if (!skip && !form.name.trim()) return setError('Please enter your name — or skip for now.')
    speechSynthesis.cancel()
    setSaving('Saving…')
    try {
      const res = await bfetch(`${BRIDGE_HTTP_URL}/profile`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(skip ? { ...form, skip: true } : form),
      })
      const body = await res.json()
      if (!res.ok) {
        setSaving('')
        return setError(String(body.error ?? 'Could not save.'))
      }
      if (!skip) setVoiceProfile({ voice: voice || null, offlineVoice: offVoice || undefined, rate })
      // Keys typed here (or removed): saved on this PC only.
      const typed = Object.fromEntries(Object.entries(keyInput).filter(([, v]) => v === null || (v ?? '').trim()))
      if (!skip && Object.keys(typed).length) {
        setSaving('Saving the AI keys and starting the translator…')
        await bfetch(`${BRIDGE_HTTP_URL}/keys`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(typed),
        }).catch(() => {})
      }
      applyTheme(body.theme)
      refreshProfile()
      if (body.restarting) {
        setSaving('Turning features on and off — back in a few seconds…')
        window.setTimeout(() => setOpen(false), 3500)
      } else {
        setOpen(false)
      }
    } catch {
      setSaving('')
      setError(`${who} is not running, so this could not be saved.`)
    }
  }

  return (
    <div className="su-backdrop" role="dialog" aria-modal="true" aria-labelledby="su-title">
      <div className="su-card">
        <header className="su-head">
          <div className="su-ring" aria-hidden="true"><i /></div>
          <div>
            <h2 id="su-title">{firstRun ? 'Welcome — let’s set you up' : `Customize ${dottedName(profile?.assistant)}`}</h2>
            <p>{firstRun ? 'A few details so your assistant knows who it works for.' : 'Change any of this whenever you like.'}</p>
          </div>
        </header>

        <div className="su-body">
          <div className="su-row2">
            <label className="su-field">
              <span>Your name</span>
              <input value={form.name} maxLength={40} autoFocus placeholder="What should it call you?" onChange={(e) => set({ name: e.target.value })} />
            </label>
            <label className="su-field">
              <span>Your city</span>
              <input value={form.city} maxLength={60} placeholder="For weather when location is off" onChange={(e) => set({ city: e.target.value })} />
            </label>
          </div>

          <div className="su-row2">
            <label className="su-field">
              <span>Assistant’s name</span>
              {/* Written with a dot after every letter (tidied when you leave the
                  box); said as one word. */}
              <input
                value={form.assistant}
                maxLength={40}
                placeholder="M.O.R.P.H.A."
                onChange={(e) => set({ assistant: e.target.value })}
                onBlur={() => set({ assistant: dottedName(form.assistant) })}
              />
              <small>
                Shown as {dottedName(form.assistant)} · say “Hey {nameWord(spokenName(form.assistant))}”, “Hello{' '}
                {nameWord(spokenName(form.assistant))}” or just “{nameWord(spokenName(form.assistant))}” to call
                {spokenName(form.assistant).toLowerCase() === 'jarvis' ? '' : ' (“Hey Jarvis” works too)'}.
              </small>
            </label>
          </div>

          <div className="su-field">
            <span>Voice — click one to hear it and choose it</span>
            {/* The two picks at a glance. */}
            <div className="su-vpicks">
              <div className="su-vpick">
                <small>When online</small>
                <strong>{short(online)}</strong>
              </div>
              <div className="su-vpick">
                <small>When offline</small>
                <strong>{offline ? short(offline) : '—'}</strong>
              </div>
            </div>

            <small className="su-vgroup">Works online · natural voices, two per language</small>
            <div className="su-voices su-voices-std" role="listbox" aria-label="Online voices">
              {STANDARD_VOICES.map((v) => {
                const key = NATURAL + v.id
                const chosen = online === key
                return (
                  <button
                    key={v.id}
                    type="button"
                    role="option"
                    aria-selected={chosen}
                    title={`${v.name} — ${v.language}, ${v.gender.toLowerCase()} (${v.id})`}
                    className={`su-voice ${chosen ? 'su-on' : ''}`}
                    onClick={() => {
                      setVoice(key)
                      previewVoice(key, sampleFor(v.language), rate)
                    }}
                  >
                    <span className="su-play" aria-hidden="true">▶</span>
                    <span className="su-vname">{v.name}</span>
                    <small>
                      {v.language} · {v.gender}
                    </small>
                  </button>
                )
              })}
            </div>

            <small className="su-vgroup">Works offline · voices on this PC</small>
            <div className="su-voices" role="listbox" aria-label="Offline voices">
              {voices.length === 0 && <small className="su-novoice">Loading the voices on this PC…</small>}
              {voices.map((v) => {
                const chosen = offline === v.name
                const alsoOnline = online === v.name
                return (
                  <div key={v.name} className={`su-voice su-voice-off ${chosen ? 'su-on' : ''}`}>
                    <button
                      type="button"
                      role="option"
                      aria-selected={chosen}
                      title={v.name}
                      className="su-vmain"
                      onClick={() => {
                        setOffVoice(v.name)
                        previewVoice(v.name, sample, rate)
                      }}
                    >
                      <span className="su-play" aria-hidden="true">▶</span>
                      <span className="su-vname">{short(v.name)}</span>
                      <small>{v.lang}</small>
                    </button>
                    {/* The same voice online too, if that is what you want. */}
                    <button
                      type="button"
                      className={`su-vboth ${alsoOnline ? 'su-on' : ''}`}
                      aria-pressed={alsoOnline}
                      title={alsoOnline ? 'Used online as well' : 'Use this voice online as well'}
                      onClick={() => {
                        setOffVoice(v.name)
                        setVoice(v.name)
                        previewVoice(v.name, sample, rate)
                      }}
                    >
                      {alsoOnline ? '✓ Online too' : 'Use online too'}
                    </button>
                  </div>
                )
              })}
            </div>
            <small>
              Each says: “{sample}” — in its own language. With no internet (or if the online voice fails), the offline voice speaks.
            </small>
          </div>

          <div className="su-field">
            <span>Speech speed — {rate.toFixed(2)}×</span>
            <div className="su-rate">
              <small>Slower</small>
              <input
                type="range"
                min={0.6}
                max={1.8}
                step={0.05}
                value={rate}
                aria-label="Speech speed"
                onChange={(e) => setRate(Number(e.target.value))}
                // Let go (mouse, touch or keys) and hear the new speed.
                onPointerUp={() => previewVoice(online, sampleOf(online), rate)}
                onKeyUp={() => previewVoice(online, sampleOf(online), rate)}
              />
              <small>Faster</small>
              <button type="button" className="su-ghost su-reset" onClick={() => setRate(1)}>
                Normal
              </button>
            </div>
          </div>

          <div className="su-field">
            <span>Centre orb</span>
            <div className="su-orbs" role="radiogroup" aria-label="Centre orb">
              {ORBS.map((o) => {
                const on = (form.orb || 'reactor') === o.id
                return (
                  <button
                    key={o.id}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    className={`su-orb ${on ? 'su-on' : ''}`}
                    onClick={() => set({ orb: o.id })}
                  >
                    <Orb id={o.id} phase="dormant" level={0} className="orb-preview" />
                    <b>{o.label}</b>
                  </button>
                )
              })}
            </div>
          </div>

          <div className="su-field">
            <span>Colour</span>
            <div className="su-themes">
              {THEMES.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  className={`su-theme ${form.theme === t.id ? 'su-on' : ''}`}
                  style={{ ['--sw' as string]: t.swatch }}
                  aria-pressed={form.theme === t.id}
                  onClick={() => {
                    set({ theme: t.id })
                    applyTheme(t.id)
                  }}
                >
                  <i />
                  {t.label}
                </button>
              ))}
            </div>
          </div>

          <div className="su-field">
            <span>AI accounts</span>
            <small>
              No Claude subscription needed: {who} thinks with Gemini, OpenRouter or Groq — all free — and uses Claude
              too if you have it. Leave the model on Auto and it switches by itself when one is unavailable or at its
              limit. ChatGPT draws story characters. A window opens to sign in; {who} sets up the rest. Nothing to copy or
              paste.
            </small>
            {/* Nothing to think with yet: say so plainly, before the list. */}
            {accounts && !accounts.claude?.connected && !accounts.gemini?.connected && !accounts.openrouter?.connected && !accounts.groq?.connected && (
              <p className="su-acc-need">
                Sign in to at least one below — Gemini or OpenRouter is best (free, and they can use all of JARVIS's tools).
              </p>
            )}
            <ul className="su-accounts">
              {/* Claude: shown, not signed in from here (that's done in Claude Code). */}
              <li className={accounts?.claude?.connected ? 'su-acc-on' : ''}>
                <span className="su-acc-name">
                  <b>Claude</b>
                  <small>
                    {accounts?.claude?.connected
                      ? `Your Claude${accounts.claude.plan && accounts.claude.plan !== 'API key' ? ` ${accounts.claude.plan[0].toUpperCase()}${accounts.claude.plan.slice(1)}` : ''} plan, through Claude Code — used first on Auto`
                      : accounts?.claude?.off
                        ? 'Turned off here — the free AIs answer. Your Claude Code sign-in is kept, so Connect brings Claude back.'
                        : accounts?.claude?.expired
                          ? 'Signed out — sign in again in Claude Code to use it. Until then the free AIs answer.'
                          : 'Optional. With a Claude plan, sign in once in Claude Code. Without it the free AIs answer.'}
                  </small>
                </span>
                {leaving === 'claude' || leaving === 'claude-on' ? (
                  <span className="su-acc-wait">
                    <i />
                    {leaving === 'claude' ? 'Disconnecting…' : 'Connecting…'}
                  </span>
                ) : accounts?.claude?.connected ? (
                  <span className="su-acc-done">
                    <span className="su-acc-ok">✓ Connected</span>
                    <button type="button" className="su-acc-off" onClick={() => void toggleClaude(true)}>
                      Disconnect
                    </button>
                  </span>
                ) : accounts?.claude?.off ? (
                  <span className="su-acc-done">
                    <span className="su-acc-opt">Off</span>
                    <button type="button" className="su-google" onClick={() => void toggleClaude(false)}>
                      Connect
                    </button>
                  </span>
                ) : (
                  <span className="su-acc-opt">Optional</span>
                )}
              </li>
              {ACCOUNTS.map((a) => {
                const job = accounts?.jobs?.[a.id]
                const busy = job && (job.state === 'working' || job.state === 'waiting')
                const connected = accounts?.[a.id]?.connected
                return (
                  <li key={a.id} className={connected ? 'su-acc-on' : ''}>
                    <span className="su-acc-name">
                      <b>{a.label}</b>
                      <small>{busy || job?.state === 'failed' ? job.note : a.what}</small>
                    </span>
                    {busy ? (
                      <span className="su-acc-wait">
                        <i />
                        Signing in…
                      </span>
                    ) : leaving === a.id ? (
                      <span className="su-acc-wait">
                        <i />
                        {a.id === 'chatgpt' ? 'Signing out…' : 'Disconnecting…'}
                      </span>
                    ) : connected ? (
                      <span className="su-acc-done">
                        <span className="su-acc-ok">✓ Connected</span>
                        {a.key && (
                          <button type="button" className="su-acc-off" onClick={() => void disconnect(a.id)}>
                            Disconnect
                          </button>
                        )}
                      </span>
                    ) : connected === null && a.id === 'chatgpt' && !checked ? (
                      <span className="su-acc-wait">
                        <i />
                        Checking…
                      </span>
                    ) : (
                      <button type="button" className="su-google" disabled={!!accounts?.running} onClick={() => void signIn(a.id)}>
                        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
                          <path fill="#4285F4" d="M22.5 12.3c0-.8-.1-1.5-.2-2.3H12v4.3h5.9a5 5 0 0 1-2.2 3.3v2.7h3.6c2-1.9 3.2-4.7 3.2-8z" />
                          <path fill="#34A853" d="M12 23c3 0 5.5-1 7.3-2.7l-3.6-2.7c-1 .7-2.2 1.1-3.7 1.1-2.9 0-5.3-1.9-6.2-4.5H2.1V17A11 11 0 0 0 12 23z" />
                          <path fill="#FBBC05" d="M5.8 14.2a6.6 6.6 0 0 1 0-4.4V7H2.1a11 11 0 0 0 0 10l3.7-2.8z" />
                          <path fill="#EA4335" d="M12 5.4c1.6 0 3 .6 4.2 1.6l3.1-3.1A11 11 0 0 0 2.1 7l3.7 2.8C6.7 7.3 9.1 5.4 12 5.4z" />
                        </svg>
                        Sign in
                      </button>
                    )}
                  </li>
                )
              })}
            </ul>
          </div>

          <div className="su-field">
            <span>Features</span>
            <div className="su-feats">
              {FEATURES.map((f) => (
                <label key={f.id} className={`su-feat ${form.features[f.id] !== false ? 'su-on' : ''}`}>
                  <input
                    type="checkbox"
                    checked={form.features[f.id] !== false}
                    onChange={(e) => set({ features: { ...form.features, [f.id]: e.target.checked } })}
                  />
                  <b>{f.label}</b>
                  <small>{f.note}</small>
                </label>
              ))}
              {/* Off by default: their many tools are sent with every request. */}
              <label className={`su-feat ${form.connectors ? 'su-on' : ''}`}>
                <input type="checkbox" checked={form.connectors === true} onChange={(e) => set({ connectors: e.target.checked })} />
                <b>Gmail, Calendar & Drive</b>
                <small>
                  {accounts?.claude && !accounts.claude.connected
                    ? 'Needs a Claude plan (these come through your Claude account) — off without one'
                    : 'Through your Claude account — uses more of your Claude usage'}
                </small>
              </label>
              <label className={`su-feat ${form.askFirst !== false ? 'su-on' : ''}`}>
                <input type="checkbox" checked={form.askFirst !== false} onChange={(e) => set({ askFirst: e.target.checked })} />
                <b>Ask before closing or deleting</b>
                <small>Closing an app or sending a file to the Recycle Bin waits for your yes (unless you asked plainly)</small>
              </label>
            </div>
          </div>

          <div className="su-field">
            <span>Check-up</span>
            <small>Microphone, internet, AI, offline model and the wake word listener — what's wrong and how to fix it. You can also say "health check".</small>
            <div className="su-check">
              <button type="button" className="su-ghost" disabled={checking} onClick={() => void runCheckup()}>
                {checking ? 'Checking…' : 'Run check-up'}
              </button>
              {checkItems && (
                <ul className="su-check-list">
                  {checkItems.map((i) => (
                    <li key={i.name} className={i.ok ? 'su-check-ok' : 'su-check-bad'}>
                      <b>{i.ok ? '✓' : '!'} {i.name}</b>
                      <small>{i.note}</small>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>

          {error && <p className="su-error" role="alert">{error}</p>}
        </div>

        <footer className="su-foot">
          <span className="su-credit">{assistantTitle(profile)} · created by <b>{profile?.creator ?? 'Sujith M'}</b></span>
          <span className="su-actions">
            {saving && <span className="su-saving">{saving}</span>}
            {firstRun ? (
              <button type="button" className="su-ghost" disabled={Boolean(saving)} onClick={() => void save(true)}>
                Skip for now
              </button>
            ) : (
              <button
                type="button"
                className="su-ghost"
                onClick={() => {
                  speechSynthesis.cancel()
                  applyTheme(profile?.theme)
                  setOpen(false)
                }}
              >
                Cancel
              </button>
            )}
            <button type="button" className="su-save" disabled={Boolean(saving)} onClick={() => void save()}>
              {firstRun ? 'Start' : 'Save'}
            </button>
          </span>
        </footer>
      </div>
    </div>
  )
}
