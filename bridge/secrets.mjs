/**
 * Secrets at rest: encrypted with Windows' own per-account encryption (DPAPI,
 * CurrentUser), so a copied ~/.jarvis folder or a leaked backup is useless on
 * another PC or under another Windows account. Decrypted only in memory, by
 * this process, when needed.
 *
 * It does not stop a program already running as the same Windows user - that
 * one could ask Windows to decrypt too - but it closes the "someone got a copy
 * of the files" hole, which is the common one.
 *
 * Off Windows there is no DPAPI: protect() returns null and the caller keeps
 * the plain form.
 */

import { execFileSync } from 'node:child_process'

// Ties the encryption to this app as well as the account: another program of
// the same user cannot decrypt it by accident.
const ENTROPY = "[Text.Encoding]::UTF8.GetBytes('morpha-secrets-v1')"
const PRELUDE =
  'Add-Type -AssemblyName System.Security; [Console]::OutputEncoding = [Text.Encoding]::UTF8; ' +
  '$in = [Console]::In.ReadToEnd().Trim(); '

/** Run a short PowerShell script with `input` on stdin (never on the command line). */
function ps(script, input) {
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', PRELUDE + script], {
    input,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 30_000,
  }).trim()
}

/** Encrypt text for this Windows account; base64, or null where there is no DPAPI. */
export function protect(text) {
  if (process.platform !== 'win32') return null
  const b64in = Buffer.from(String(text), 'utf8').toString('base64')
  return ps(
    `[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Convert]::FromBase64String($in), ${ENTROPY}, 'CurrentUser'))`,
    b64in,
  )
}

/** Decrypt what protect() made. Throws if it cannot (another account or PC). */
export function unprotect(b64) {
  const out = ps(
    `[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($in), ${ENTROPY}, 'CurrentUser'))`,
    String(b64),
  )
  return Buffer.from(out, 'base64').toString('utf8')
}
