import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── helpers ──────────────────────────────────────────────────────────────────

async function getEmbedding(text: string): Promise<number[]> {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  })
  if (!res.ok) throw new Error(`Embedding error: ${await res.text()}`)
  const data = await res.json()
  return data.data[0].embedding
}

async function saveChatMessages(userId: string, userMsg: string, assistantMsg: string) {
  await supabase.from('chat_messages').insert([
    { user_id: userId, role: 'user', content: userMsg },
    { user_id: userId, role: 'assistant', content: assistantMsg },
  ])
}

// ── main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS })
  }

  try {
    const {
      user_id,
      message,
      history = [],
    }: { user_id: string; message: string; history: { role: string; content: string }[] } =
      await req.json()

    // ── 2. Embed user message ─────────────────────────────────
    const embedding = await getEmbedding(message)

    // ── 3. RAG: top 8 chunks (own + approved family) ──────────
    const { data: chunks, error: chunksErr } = await supabase.rpc('match_chunks', {
      query_embedding: embedding,
      requesting_user_id: user_id,
      match_count: 8,
    })
    if (chunksErr) console.error('[chat] match_chunks error:', chunksErr.message)

    const ragContext = ((chunks ?? []) as { chunk_text: string }[])
      .map((c) => c.chunk_text)
      .join('\n\n')

    // ── 4. Fetch hospitals + doctors ──────────────────────────
    const [{ data: hospitals }, { data: doctors }] = await Promise.all([
      supabase.from('hospitals').select('name, address, phone, specialties'),
      supabase.from('doctors').select('name, specialty, phone'),
    ])

    const hospitalsText = ((hospitals ?? []) as Record<string, unknown>[])
      .map(
        (h) =>
          `• ${h.name} — ${h.address} — ${h.phone} — Specialties: ${(h.specialties as string[])?.join(', ')}`,
      )
      .join('\n')

    const doctorsText = ((doctors ?? []) as Record<string, string>[])
      .map((d) => `• Dr. ${d.name} — ${d.specialty} — ${d.phone}`)
      .join('\n')

    // ── 5. Build system prompt ────────────────────────────────
    // web_search_preview is passed as a tool — OpenAI decides when to use it
    const systemPrompt = `You are MerciMed, a personal medical assistant for a private group of users.
You have access to the patient's medical history extracted from their uploaded documents. Use it to give personalized, context-aware answers.
You also have access to a web search tool — use it whenever the question requires up-to-date or external information.

When the user describes symptoms:
- Check if their history shows related past conditions
- Assess whether they should see a doctor
- If yes, recommend a specific doctor and hospital from the list below
- Always remind them you are not a substitute for professional medical advice

Patient medical history (from their records):
${ragContext || 'No medical records found.'}

Available hospitals and doctors:
${hospitalsText || 'No hospitals on file.'}
${doctorsText || 'No doctors on file.'}`

    // ── 6. Call gpt-4o with streaming + built-in web search ───
    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o',
        stream: true,
        max_tokens: 1000,
        tools: [{ type: 'web_search_preview' }],
        messages: [
          { role: 'system', content: systemPrompt },
          ...history,
          { role: 'user', content: message },
        ],
      }),
    })

    if (!openaiRes.ok) throw new Error(`OpenAI error: ${await openaiRes.text()}`)

    // ── 7. Stream SSE back to Flutter ─────────────────────────
    const encoder = new TextEncoder()
    const decoder = new TextDecoder()

    const sseStream = new ReadableStream({
      async start(controller) {
        const reader = openaiRes.body!.getReader()
        let fullResponse = ''

        try {
          while (true) {
            const { done, value } = await reader.read()
            if (done) break

            const text = decoder.decode(value, { stream: true })

            for (const line of text.split('\n')) {
              const trimmed = line.trim()
              if (!trimmed.startsWith('data: ')) continue

              const payload = trimmed.slice(6)
              if (payload === '[DONE]') {
                // ── 8. Save both messages after full stream ────
                await saveChatMessages(user_id, message, fullResponse)
                controller.enqueue(encoder.encode('data: [DONE]\n\n'))
                controller.close()
                return
              }

              try {
                const parsed = JSON.parse(payload)
                // Only forward text content tokens — skip tool_call deltas
                const token: string | undefined = parsed.choices?.[0]?.delta?.content
                if (token) {
                  fullResponse += token
                  controller.enqueue(
                    encoder.encode(`data: ${JSON.stringify({ token })}\n\n`),
                  )
                }
              } catch {
                // skip malformed SSE chunks
              }
            }
          }
        } finally {
          reader.releaseLock()
        }

        // Fallback: save if stream ended without explicit [DONE]
        if (fullResponse) await saveChatMessages(user_id, message, fullResponse)
        controller.enqueue(encoder.encode('data: [DONE]\n\n'))
        controller.close()
      },
    })

    return new Response(sseStream, {
      headers: {
        ...CORS_HEADERS,
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    })
  } catch (err) {
    console.error('[chat]', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
  }
})
