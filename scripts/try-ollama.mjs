// One-off check of a provider through LiteLLM with a real tool:
//   JARVIS_LITELLM_PORT=4001 node scripts/try-ollama.mjs gemini "which apps are open"
// (provider: gemini, groq, openrouter, or local-test for the Ollama model)
import { query } from '@anthropic-ai/claude-agent-sdk'
import { checkBrain, proxyModel } from '../bridge/brain.mjs'
import { PROXY_URL, proxyKey, startProxy, stopProxy } from '../bridge/litellm.mjs'
import { pcServer } from '../bridge/pc.mjs'
import { identityPrompt } from '../bridge/profile.mjs'

const provider = process.argv[2] ?? 'local-test'
await checkBrain()
if (!(await startProxy({ force: true }))) {
  console.log('LiteLLM did not start')
  process.exit(1)
}
const t1 = Date.now()
const q = query({
  prompt: process.argv[3] ?? 'Which apps are open right now? Use the tool, then answer in one sentence.',
  options: {
    model: proxyModel(provider),
    env: { ...process.env, ANTHROPIC_BASE_URL: PROXY_URL, ANTHROPIC_AUTH_TOKEN: proxyKey(), ANTHROPIC_API_KEY: '', CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1', CLAUDE_CODE_MAX_RETRIES: '1', API_TIMEOUT_MS: '45000' },
    thinking: { type: 'disabled' },
    systemPrompt: identityPrompt() + 'Answer in one short sentence.',
    mcpServers: { jarvis_pc: pcServer({ allowWrites: false }) },
    tools: [],
    settingSources: [],
    maxTurns: 6,
    permissionMode: 'bypassPermissions',
  },
})
for await (const m of q) {
  const s = ((Date.now() - t1) / 1000).toFixed(1)
  if (m.type === 'assistant') {
    for (const c of m.message.content) {
      if (c.type === 'tool_use') console.log(`${s}s tool: ${c.name}`)
      if (c.type === 'text' && c.text.trim()) console.log(`${s}s says: ${c.text.trim().slice(0, 220)}`)
    }
  } else if (m.type === 'result') {
    console.log(`${s}s done (${m.subtype}${m.is_error ? ', ERROR' : ''})`)
  }
}
stopProxy()
