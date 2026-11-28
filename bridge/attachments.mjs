import { execFile } from 'node:child_process'
import { createWriteStream, existsSync } from 'node:fs'
import { copyFile, mkdir, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { homedir, tmpdir } from 'node:os'
import { basename, dirname, extname, isAbsolute, join, relative, resolve as resolvePath } from 'node:path'
import { fileURLToPath } from 'node:url'
import { findTool } from './creator.mjs'
import { protectedProblem, ps } from './pc.mjs'

/**
 * Files handed to the onscreen popup (📎, drag and drop, paste) for him to
 * work with — "summarise this PDF", "what's in this photo", "fix this code".
 *
 * Each file is copied into the temp folder, which his file tools are allowed to
 * read (policy.mjs: workspace + temp only), so the user's own folders stay
 * closed to them. There, the Read tool shows images and PDFs as they are and
 * reads text and code. Word, Excel and PowerPoint it cannot open, so those are
 * turned into a .txt beside the copy. The copies are cleared after a day.
 */

const ROOT = join(tmpdir(), 'jarvis-attach')
/** Files the main window uploads (it cannot hand over paths): kept here, briefly. */
export const UPLOAD_DIR = join(ROOT, 'uploads')
const MAX_FILES = 10
const MAX_BYTES = 30 * 1024 * 1024
/** Videos are bigger: up to 500 MB (only stills and the speech are kept from them). */
export const MAX_VIDEO_BYTES = 500 * 1024 * 1024
const KEEP_MS = 24 * 60 * 60 * 1000

const OFFICE = new Set(['.docx', '.pptx', '.xlsx'])
/** Images the model reads directly; the rest are converted to PNG first. */
const IMAGE_OK = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp'])
const IMAGE_CONVERT = new Set(['.bmp', '.tif', '.tiff', '.ico'])
const OLD_OFFICE = new Set(['.doc', '.ppt', '.xls'])
const AUDIO = new Set(['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.oga', '.opus', '.webm', '.flac'])
/** Videos (.webm may be either: one with no picture is treated as audio). */
const VIDEO = new Set(['.mp4', '.mov', '.m4v', '.mkv', '.avi', '.wmv', '.3gp', '.webm', '.mpeg', '.mpg', '.flv'])

const PY = join(homedir(), '.jarvis', 'wake-venv', 'Scripts', 'python.exe')
const TRANSCRIBE = join(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'transcribe.py')

/** A program's output, whatever its exit code (ffmpeg -i "fails" by design). */
function runAny(file, args, timeoutMs) {
  return new Promise((res) => {
    execFile(file, args, { timeout: timeoutMs, windowsHide: true, maxBuffer: 32 * 1024 * 1024 }, (err, stdout, stderr) =>
      res({ ok: !err, stdout: String(stdout ?? ''), stderr: String(stderr ?? ''), why: err?.killed ? 'took too long' : err?.message }),
    )
  })
}

const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`

/**
 * A video, made readable: the model cannot watch one, but it can look at
 * pictures and read text. So: stills from across it (4 for a short clip, 6
 * otherwise) and what is said in it, transcribed offline (Whisper when
 * installed, else Vosk - scripts/transcribe.py; the first 10 minutes).
 * Returns the items, or null when the file has no picture (an audio .webm).
 */
async function videoItems(copy, name, sub) {
  const ff = findTool('ffmpeg')
  if (!ff) {
    return [{ name, path: copy, note: 'video - ffmpeg is not installed, so it could not be opened; say so and suggest running the setup file again' }]
  }
  const probe = (await runAny(ff, ['-hide_banner', '-i', copy], 30_000)).stderr
  if (!/Stream #[^\n]*Video:/.test(probe)) return null
  const d = probe.match(/Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/)
  const secs = d ? Number(d[1]) * 3600 + Number(d[2]) * 60 + Number(d[3]) : 0
  const items = []

  const n = secs && secs <= 20 ? 4 : 6
  for (let i = 0; i < n; i++) {
    const t = secs ? ((i + 0.5) * secs) / n : i
    const jpg = join(sub, `frame-${i + 1}.jpg`)
    const r = await runAny(ff, ['-hide_banner', '-loglevel', 'error', '-y', '-ss', t.toFixed(2), '-i', copy, '-frames:v', '1', '-vf', 'scale=768:-2', '-q:v', '4', jpg], 60_000)
    if (r.ok && existsSync(jpg)) items.push({ name: `${name}, still at ${clock(t)}`, path: jpg, note: 'image - a frame from the video' })
  }

  if (/Stream #[^\n]*Audio:/.test(probe) && existsSync(PY)) {
    const wav = join(sub, 'speech.wav')
    const a = await runAny(ff, ['-hide_banner', '-loglevel', 'error', '-y', '-i', copy, '-t', '600', '-vn', '-ac', '1', '-ar', '16000', '-sample_fmt', 's16', wav], 180_000)
    if (a.ok && existsSync(wav)) {
      const t = await runAny(PY, ['-I', TRANSCRIBE, wav], 15 * 60_000)
      const words = t.ok ? t.stdout.trim() : ''
      const txt = join(sub, 'what-is-said.txt')
      await writeFile(txt, words || '(no speech was recognised in it)', 'utf8')
      items.push({
        name: `${name}, what is said`,
        path: txt,
        note: `transcript of the video's speech${secs > 600 ? ' (first 10 minutes)' : ''}, made offline - it may have mistakes`,
      })
      await rm(wav, { force: true })
    }
  }
  items.push({
    name,
    path: copy,
    note:
      `the video itself (${secs ? clock(secs) + ' long' : 'length unknown'}) - Read cannot open a video: use its stills ` +
      'and transcript above; pass this path to edit_video if they want it edited',
  })
  return items
}

// Office Open XML is a zip of XML parts: read the text out of the parts that
// hold it. Paths arrive through env vars (see ps() in pc.mjs), never the script.
const EXTRACT = String.raw`
Add-Type -AssemblyName System.IO.Compression.FileSystem
$NL = [string][char]10; $TAB = [string][char]9
$z = [IO.Compression.ZipFile]::OpenRead($env:JARVIS_SRC)
function Read-Part($e) { $r = New-Object IO.StreamReader($e.Open()); $t = $r.ReadToEnd(); $r.Close(); $t }
function Num($e) { [int]([regex]::Match($e.FullName, '(\d+)\.xml$').Groups[1].Value) }
function Plain($x) { [Net.WebUtility]::HtmlDecode(($x -replace '<[^>]+>', '')) }
$out = New-Object Text.StringBuilder
try {
  switch ($env:JARVIS_EXT) {
    '.docx' {
      $x = Read-Part ($z.GetEntry('word/document.xml'))
      # Tables first: a cell's last paragraph ends the cell (tab), a row ends
      # the line — so a table reads as rows and columns, not run-on text.
      $x = $x -replace '</w:p>\s*</w:tc>', $TAB -replace '</w:tr>', $NL
      $x = $x -replace '</w:p>', $NL -replace '<w:tab/>', $TAB -replace '<w:br/>', $NL
      [void]$out.Append((Plain $x))
    }
    '.pptx' {
      $slides = $z.Entries | Where-Object { $_.FullName -match '^ppt/slides/slide\d+\.xml$' } | Sort-Object { Num $_ }
      $i = 0
      foreach ($s in $slides) {
        $i++
        $x = (Read-Part $s) -replace '</a:p>', $NL
        [void]$out.Append("--- Slide $i ---" + $NL + (Plain $x) + $NL)
      }
    }
    '.xlsx' {
      $ss = @()
      $e = $z.GetEntry('xl/sharedStrings.xml')
      if ($e) { $ss = @([regex]::Matches((Read-Part $e), '<si>(.*?)</si>', 'Singleline') | ForEach-Object { Plain $_.Groups[1].Value }) }
      $sheets = $z.Entries | Where-Object { $_.FullName -match '^xl/worksheets/sheet\d+\.xml$' } | Sort-Object { Num $_ }
      foreach ($sh in $sheets) {
        [void]$out.Append("--- Sheet $(Num $sh) ---" + $NL)
        foreach ($row in [regex]::Matches((Read-Part $sh), '<row[^>]*>(.*?)</row>', 'Singleline')) {
          $vals = foreach ($c in [regex]::Matches($row.Groups[1].Value, '<c([^>]*?)(?:/>|>(.*?)</c>)', 'Singleline')) {
            $attr = $c.Groups[1].Value; $inner = $c.Groups[2].Value
            $v = [regex]::Match($inner, '<v>(.*?)</v>').Groups[1].Value
            if ($attr -match 't="s"' -and $v -ne '') { $ss[[int]$v] }
            elseif ($attr -match 't="inlineStr"') { Plain $inner }
            else { [Net.WebUtility]::HtmlDecode($v) }
          }
          [void]$out.Append((($vals | ForEach-Object { "$_" }) -join $TAB) + $NL)
        }
      }
    }
  }
} finally { $z.Dispose() }
[IO.File]::WriteAllText($env:JARVIS_OUT, $out.ToString(), (New-Object Text.UTF8Encoding $false))
`

// Old binary Office formats, converted with Office itself (read-only, hidden):
// .doc → .docx, .xls → .xlsx, .ppt → .pptx, then read like the new ones.
const UPGRADE = String.raw`
$src = $env:JARVIS_SRC; $out = $env:JARVIS_OUT
switch ($env:JARVIS_EXT) {
  '.doc' {
    $app = New-Object -ComObject Word.Application; $app.Visible = $false; $app.DisplayAlerts = 0
    try { $d = $app.Documents.Open($src, $false, $true); $d.SaveAs2($out, 16); $d.Close($false) } finally { $app.Quit() }
  }
  '.xls' {
    $app = New-Object -ComObject Excel.Application; $app.Visible = $false; $app.DisplayAlerts = $false
    try { $w = $app.Workbooks.Open($src, 0, $true); $w.SaveAs($out, 51); $w.Close($false) } finally { $app.Quit() }
  }
  '.ppt' {
    $app = New-Object -ComObject PowerPoint.Application
    try { $p = $app.Presentations.Open($src, -1, 0, 0); $p.SaveAs($out, 24); $p.Close() } finally { $app.Quit() }
  }
}
if (-not (Test-Path -LiteralPath $out)) { throw 'conversion produced nothing' }
`

const CONVERT = String.raw`
Add-Type -AssemblyName System.Drawing
$img = [Drawing.Image]::FromFile($env:JARVIS_SRC)
try { $img.Save($env:JARVIS_OUT, [Drawing.Imaging.ImageFormat]::Png) } finally { $img.Dispose() }
`

/** Remove copies older than a day. Never throws. */
async function sweep() {
  const now = Date.now()
  // The prepared copies, and (one level down) the window's uploads.
  for (const base of [ROOT, UPLOAD_DIR]) {
    try {
      for (const d of await readdir(base)) {
        if (base === ROOT && d === 'uploads') continue
        const p = join(base, d)
        const s = await stat(p).catch(() => null)
        if (s && now - s.mtimeMs > KEEP_MS) await rm(p, { recursive: true, force: true }).catch(() => {})
      }
    } catch {
      /* nothing there yet */
    }
  }
}

/**
 * Copy the files somewhere he can read them and describe each.
 * @param {string[]} paths absolute paths from the popup
 * @returns {Promise<{ items: { name: string, path: string, note: string }[], problems: string[] }>}
 */
export async function prepareAttachments(paths) {
  void sweep()
  const items = []
  const problems = []
  const list = (Array.isArray(paths) ? paths : []).map((p) => String(p ?? '').trim()).filter(Boolean)
  if (list.length > MAX_FILES) problems.push(`more than ${MAX_FILES} files: only the first ${MAX_FILES} were attached`)
  const dir = join(ROOT, String(Date.now()))
  await mkdir(dir, { recursive: true })

  for (const src of list.slice(0, MAX_FILES)) {
    const name = basename(src)
    try {
      if (!isAbsolute(src)) throw new Error('not a full path')
      // Chosen by the user themselves: any folder, but never a private or credential one.
      const bad = protectedProblem(src, { userChosen: true })
      if (bad) throw new Error(bad)
      const info = await stat(src)
      if (!info.isFile()) throw new Error('it is a folder, not a file')
      const ext = extname(name).toLowerCase()
      if (VIDEO.has(ext) ? info.size > MAX_VIDEO_BYTES : info.size > MAX_BYTES) {
        throw new Error(VIDEO.has(ext) ? 'it is larger than 500 MB' : 'it is larger than 30 MB')
      }
      // A numbered sub-folder per file, so two files with the same name coexist.
      const sub = join(dir, String(items.length + 1))
      await mkdir(sub, { recursive: true })
      const copy = join(sub, name)
      await copyFile(src, copy)

      // A video: stills and its speech (an audio-only .webm falls through to audio).
      const video = VIDEO.has(ext) ? await videoItems(copy, name, sub) : null
      if (video) {
        items.push(...video)
      } else if (OFFICE.has(ext)) {
        const txt = `${copy}.txt`
        await ps(EXTRACT, { SRC: copy, OUT: txt, EXT: ext }, 60_000)
        items.push({ name, path: txt, note: `the text of ${name}, extracted` })
      } else if (IMAGE_CONVERT.has(ext)) {
        const png = `${copy}.png`
        await ps(CONVERT, { SRC: copy, OUT: png }, 30_000)
        items.push({ name, path: png, note: 'image' })
      } else if (IMAGE_OK.has(ext)) {
        items.push({ name, path: copy, note: 'image' })
      } else if (ext === '.pdf') {
        items.push({ name, path: copy, note: 'PDF' })
      } else if (AUDIO.has(ext)) {
        items.push({
          name,
          path: copy,
          note:
            'audio recording — not readable with Read: use transcribe_audio on it for what is said, ' +
            'or voice_analyze if they asked to change your voice',
        })
      } else if (OLD_OFFICE.has(ext)) {
        // Upgrade with Office, then extract like a modern file. Without
        // Office (or if it fails), say so plainly.
        const modern = `${copy}x`
        const since = new Date().toISOString()
        try {
          // Office automation can hang on a dialog it cannot show (activation,
          // first run) — measured on this PC: Word never returned. Kept short.
          await ps(UPGRADE, { SRC: copy, OUT: modern, EXT: ext }, 40_000)
          const txt = `${modern}.txt`
          await ps(EXTRACT, { SRC: modern, OUT: txt, EXT: `${ext}x` }, 60_000)
          items.push({ name, path: txt, note: `the text of ${name}, extracted` })
        } catch {
          // A stuck conversion leaves a hidden Office process behind; close
          // the window-less ones this attempt started (never the user's own).
          await ps(
            "Get-Process WINWORD, EXCEL, POWERPNT -ErrorAction SilentlyContinue | " +
              'Where-Object { -not $_.MainWindowTitle -and $_.StartTime -ge [datetime]$env:JARVIS_SINCE } | ' +
              'Stop-Process -Force -ErrorAction SilentlyContinue',
            { SINCE: since },
            15_000,
          ).catch(() => {})
          items.push({
            name,
            path: copy,
            note:
              `old ${ext} format that Microsoft Office could not convert here (it may be waiting on an ` +
              `activation or first-run prompt) — ask them to save it as ${ext}x or PDF`,
          })
        }
      } else {
        items.push({ name, path: copy, note: 'file' })
      }
    } catch (err) {
      problems.push(`${name}: ${err.code === 'ENOENT' ? 'not found' : err.message}`)
    }
  }
  return { items, problems }
}

/**
 * The files part of a request: what goes under the user's words. Each video's
 * stills and transcript are listed as their own items, so the header names the
 * files themselves (one entry per original file).
 */
export function attachmentBlock({ items, problems }) {
  const originals = [...new Set(items.map((i) => i.name.replace(/, (still at [\d:]+|what is said)$/, '')))]
  return [
    `[Attached files: ${originals.join(' | ') || 'none'}]`,
    ...items.map((i) => `- ${i.name} (${i.note}): ${i.path}`),
    ...problems.map((p) => `- Could not attach ${p}`),
    'Open every attached document and image with the Read tool before answering — images and ' +
      'PDFs show as they are, Word/Excel/PowerPoint arrive as extracted text, a video arrives as ' +
      'stills plus a transcript of what is said (audio and video files themselves cannot be read). ' +
      'Then do what I asked with them. Never read file paths aloud.',
  ].join('\n')
}

/** The request as the model receives it: their words, then the files. */
export function composeWithAttachments(text, att) {
  if (!att.items.length && !att.problems.length) return text
  const ask = text || 'Have a look at what I have attached and tell me briefly what it is.'
  return `${ask}\n\n${attachmentBlock(att)}`
}

/**
 * A file uploaded by the main window, streamed to UPLOAD_DIR under its own
 * folder. The name is reduced to a safe file name; the size is capped while
 * it streams. Returns its path (only ever inside UPLOAD_DIR).
 */
export async function saveUpload(req, rawName) {
  void sweep()
  let name = basename(String(rawName ?? '').replace(/[\\/]+/g, '/')).replace(/[<>:"|?*\u0000-\u001f]/g, '_').trim()
  if (!name || name === '.' || name === '..') name = 'upload'
  const ext = extname(name).toLowerCase()
  const limit = VIDEO.has(ext) ? MAX_VIDEO_BYTES : MAX_BYTES
  const dir = join(UPLOAD_DIR, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`)
  await mkdir(dir, { recursive: true })
  const path = join(dir, name.slice(0, 120))
  await new Promise((res, rej) => {
    let size = 0
    const out = createWriteStream(path)
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > limit) {
        req.destroy()
        out.destroy()
        rej(new Error(`it is larger than ${limit / 1024 / 1024} MB`))
      }
    })
    req.on('error', rej)
    out.on('error', rej)
    out.on('finish', res)
    req.pipe(out)
  })
  return path
}

/** True only for a file the window uploaded (its path is inside UPLOAD_DIR). */
export function isUpload(p) {
  const rel = relative(UPLOAD_DIR, resolvePath(String(p ?? '')))
  return Boolean(rel) && !rel.startsWith('..') && !isAbsolute(rel)
}

/** The same request as a person would describe it — for the popup and the journal. */
export function tidyAttached(text) {
  return String(text ?? '')
    .replace(/\n\n\[Attached files: ([^\]\n]*)\][\s\S]*$/, (_, names) => ` 📎 ${names.split(' | ').join(', ')}`)
    .trim()
}
