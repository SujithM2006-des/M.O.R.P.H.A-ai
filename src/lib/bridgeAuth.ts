import { BRIDGE_WS_URL } from '../config'

/**
 * The window's copy of the bridge's local key.
 *
 * The launcher (start-jarvis.bat, through scripts/splash.html) puts the key in
 * this page's address as ?k=... . The page takes it once, keeps it for this tab
 * (sessionStorage, so a reload still has it), and removes it from the address
 * bar. Nothing on the network hands the key out: a program that wants it must
 * read the user's own key file, the same as the popup and the wake listener do.
 */
const STORE = 'jarvis-bridge-key'
let cached: string | null = null

function readKey(): string | null {
  if (cached) return cached
  const url = new URL(location.href)
  const fromUrl = url.searchParams.get('k')
  if (fromUrl && /^[0-9a-f]{48}$/.test(fromUrl)) {
    cached = fromUrl
    url.searchParams.delete('k')
    history.replaceState(null, '', url.pathname + url.search + url.hash)
    try {
      sessionStorage.setItem(STORE, fromUrl)
    } catch {
      /* private window: the key lives only in this page's memory */
    }
    return cached
  }
  try {
    const kept = sessionStorage.getItem(STORE)
    if (kept && /^[0-9a-f]{48}$/.test(kept)) cached = kept
  } catch {
    /* storage blocked: no key kept */
  }
  return cached
}

/** The local key, or a message saying how to get one. */
export function bridgeKey(): string {
  const key = readKey()
  if (!key) {
    throw new Error('No bridge key: open JARVIS from its launcher (start-jarvis.bat), not the dev address.')
  }
  return key
}

/** fetch() to the bridge, with the local key on it. */
export async function bfetch(url: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers)
  headers.set('x-jarvis-token', bridgeKey())
  return fetch(url, { ...init, headers })
}

/** The WebSocket address, with the key in the query (a browser cannot set headers on it). */
export function bridgeSocketUrl(): string {
  const url = new URL(BRIDGE_WS_URL)
  url.searchParams.set('k', bridgeKey())
  return url.toString()
}
