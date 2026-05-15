// Revise a short user-provided note into a clearer, friendlier version.
// Used by the "New folder" dialog in the Flutter app — the user types a
// rough sentence, taps "Revise with AI", and the returned text replaces
// their input. Kept intentionally tiny: one-shot prompt, no streaming,
// no history.

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_INPUT_CHARS = 800
const MAX_OUTPUT_TOKENS = 220

const SYSTEM_PROMPT = [
  'You revise short notes a person attaches to a medical-records folder.',
  'Rules:',
  '- Keep the user\'s intent and any facts/names they mention.',
  '- Tighten grammar, fix typos, and use a calm, clear tone.',
  '- 1–3 sentences. No bullet lists, no markdown, no quotes.',
  '- Do not add information that the user did not provide.',
  '- Reply with the revised note only — no preamble or explanation.',
].join('\n')

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const text: string = (body?.text ?? '').toString()
    const context: string | undefined = body?.context?.toString()

    const trimmed = text.trim()
    if (!trimmed) {
      return new Response(
        JSON.stringify({ error: 'Empty text.' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }
    if (trimmed.length > MAX_INPUT_CHARS) {
      return new Response(
        JSON.stringify({ error: `Text too long (max ${MAX_INPUT_CHARS} chars).` }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }

    const userPrompt = context
      ? `Context: ${context}\n\nNote to revise:\n${trimmed}`
      : `Note to revise:\n${trimmed}`

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
      console.error('[revise-note] OpenAI error:', err)
      return new Response(
        JSON.stringify({ error: 'AI service failed.' }),
        { status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }

    const data = await openaiRes.json()
    const revised: string = (data?.choices?.[0]?.message?.content ?? '').trim()
    if (!revised) {
      return new Response(
        JSON.stringify({ error: 'AI returned an empty response.' }),
        { status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ revised }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    console.error('[revise-note] failure:', e)
    return new Response(
      JSON.stringify({ error: 'Unexpected failure.' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    )
  }
})
