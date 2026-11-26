/**
 * Ollama, only while JARVIS needs it.
 *
 * Ollama's installer starts it at every sign-in and leaves it running all day,
 * whether JARVIS is on or not. JARVIS only needs it for the offline model, so:
 *   - the installed models are read from disk (no server needed to know them),
 *   - the server is started, hidden, when the local model is about to answer
 *     (internet gone, or "Local" picked) and stopped when it is not needed,
 *   - and it is stopped with JARVIS (the bridge exiting, or the ON/OFF switch).
 * Its process id is kept in ~/.jarvis/ollama.pid, so a server JARVIS started
 * is recognised (and stopped) even after the bridge restarts.
 */

import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const URL_BASE = process.env.JARVIS_OLLAMA_URL ?? 'http://127.0.0.1:11434'
const PID_FILE = join(homedir(), '.jarvis', 'ollama.pid')
const MODELS_DIR = process.env.OLLAMA_MODELS || join(homedir(), '.ollama', 'models')

/** Models installed on disk ("qwen3:4b-instruct"), without asking the server. */
export function installedModels() {
  const root = join(MODELS_DIR, 'manifests')
  const out = []
  try {
    for (const host of readdirSync(root)) {
      for (const ns of readdirSync(join(root, host))) {
        for (const model of readdirSync(join(root, host, ns))) {
          for (const tag of readdirSync(join(root, host, ns, model))) {
            if (!statSync(join(root, host, ns, model, tag)).isFile()) continue
            const name = ns === 'library' ? `${model}:${tag}` : `${ns}/${model}:${tag}`
            out.push(host === 'registry.ollama.ai' ? name : `${host}/${name}`)
          }
        }
      }
    }
  } catch {
    /* Ollama not installed, or no models yet */
  }
  return out
}

/** The Ollama program, if installed. */
function exe() {
  const local = join(process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'), 'Programs', 'Ollama', 'ollama.exe')
  if (existsSync(local)) return local
  const found = spawnSync('where.exe', ['ollama'], { encoding: 'utf8', windowsHide: true })
  return found.status === 0 ? found.stdout.split(/\r?\n/)[0].trim() || null : null
}

const up = () =>
  fetch(`${URL_BASE}/api/version`, { signal: AbortSignal.timeout(1500) }).then(
    (r) => r.ok,
    () => false,
  )

const ourPid = () => {
  try {
    return Number.parseInt(readFileSync(PID_FILE, 'utf8'), 10) || null
  } catch {
    return null
  }
}

let starting = null

/**
 * Make sure the server is answering (start it, hidden, if not). Resolves true
 * once it answers; false if Ollama is not installed or would not start.
 */
export function startOllama() {
  return (starting ??= (async () => {
    if (await up()) return true
    const program = exe()
    if (!program) return false
    const child = spawn(program, ['serve'], { windowsHide: true, stdio: 'ignore' })
    child.on('error', () => {})
    if (child.pid) writeFileSync(PID_FILE, String(child.pid))
    console.log('[jarvis] started Ollama for the offline model')
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 500))
      if (await up()) return true
    }
    return false
  })().finally(() => {
    starting = null
  }))
}

/**
 * Stop the Ollama server — the one JARVIS started, or (`all`) every Ollama
 * process including its tray app. Synchronous, so it also works on exit.
 */
export function stopOllama({ all = false } = {}) {
  const pid = ourPid()
  if (pid) spawnSync('taskkill.exe', ['/T', '/F', '/PID', String(pid)], { windowsHide: true, stdio: 'ignore' })
  if (all) {
    for (const name of ['ollama app.exe', 'ollama.exe', 'ollama_llama_server.exe']) {
      spawnSync('taskkill.exe', ['/F', '/IM', name], { windowsHide: true, stdio: 'ignore' })
    }
  }
  rmSync(PID_FILE, { force: true })
  if (pid || all) console.log('[jarvis] stopped Ollama')
}

/**
 * Ollama's installer (and its updates) put "Ollama.lnk" in the Startup
 * folder, so it ran all day from sign-in. JARVIS starts it when needed, so
 * that shortcut is put aside — into ~/.jarvis/startup-off, never deleted (put
 * it back there to have Ollama start with Windows again). Checked at every
 * bridge start, in case an update brought it back.
 */
export function parkOllamaStartup() {
  try {
    const startup = join(process.env.APPDATA ?? join(homedir(), 'AppData', 'Roaming'), 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup')
    const lnk = join(startup, 'Ollama.lnk')
    if (!existsSync(lnk)) return false
    const away = join(homedir(), '.jarvis', 'startup-off')
    mkdirSync(away, { recursive: true })
    renameSync(lnk, join(away, 'Ollama.lnk'))
    console.log('[jarvis] Ollama no longer starts with Windows (JARVIS starts it when needed)')
    return true
  } catch {
    return false
  }
}

/** True if a server JARVIS started is (thought to be) running. */
export const ollamaIsOurs = () => Boolean(ourPid())
