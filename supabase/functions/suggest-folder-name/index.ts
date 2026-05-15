// Picks a short, human-readable folder name for the auto-created chat
// folder when a user uploads a file inside the chat. Takes the filename
// plus whatever conversation context is available and returns 2–4 words
// the home-screen "Chat Folders" section will use as the folder title.

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_OUTPUT_TOKENS = 30

const SYSTEM_PROMPT = [
  'You name folders for a personal medical records app.',
  'Given a filename plus optional user message and conversation history,',
  'return a short, descriptive folder name in 2–4 words.',
  'Rules:',
  '- Reflect the medical topic of the user\'s questions or the file\'s content.',
  '- Title Case, no quotes, no markdown, no trailing punctuation.',
  '- Never use literal words like "Chat", "Conversation", "Upload", "File", or dates.',
  '- Examples: "Heart Symptoms", "Allergy Tests", "Annual Checkup", "Back Pain",',
  '  "Lab Results", "Pediatric Visit", "Diabetes Follow Up", "Fatigue Workup".',
  '- Reply with the folder name only — no preamble, no explanation.',
].join('\n')

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const fileName: string = (body?.file_name ?? '').toString().trim()
    const message: string = (body?.message ?? '').toString().trim()
    const history: { role: string; content: string }[] = Array.isArray(body?.history)
      ? body.history
      : []

    if (!fileName && !message && history.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Need at least a filename, message, or history.' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }

    const recent = history.slice(-6)
      .map((m) => `${m.role}: ${m.content}`)
      .join('\n')
      .slice(0, 1500)

    const userPrompt = [
      fileName ? `Filename: ${fileName}` : null,
      message ? `User message in this turn: ${message}` : null,
      recent ? `Recent conversation:\n${recent}` : null,
    ].filter(Boolean).join('\n\n')

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        temperature: 0.4,
        max_tokens: MAX_OUTPUT_TOKENS,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: userPrompt },
        ],
      }),
    })
    if (!openaiRes.ok) {
      const err = await openaiRes.text()
      console.error('[suggest-folder-name] OpenAI error:', err)
      return new Response(
        JSON.stringify({ error: 'AI service failed.' }),
        { status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }
    const data = await openaiRes.json()
    let name: string = (data?.choices?.[0]?.message?.content ?? '').trim()
    // Defensive cleanup — strip surrounding quotes / trailing periods.
    name = name.replace(/^["'`]+|["'`]+$/g, '').replace(/[.!?]+$/, '').trim()
    // Hard cap to avoid runaway titles even if the model misbehaves.
    if (name.length > 40) name = name.slice(0, 40).trim()
    if (!name) {
      return new Response(
        JSON.stringify({ error: 'Empty name.' }),
        { status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }
    return new Response(
      JSON.stringify({ name }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    console.error('[suggest-folder-name] failure:', e)
    return new Response(
      JSON.stringify({ error: 'Unexpected failure.' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    )
  }
})
