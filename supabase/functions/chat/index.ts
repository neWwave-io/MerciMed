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

async function saveChatMessages(
  userId: string,
  conversationId: string | null,
  userMsg: string,
  assistantMsg: string,
) {
  // Stagger the timestamps by 1ms so the client can sort the pair
  // deterministically (user before assistant on the same turn).
  const now = Date.now()
  await supabase.from('chat_messages').insert([
    {
      user_id: userId,
      conversation_id: conversationId,
      role: 'user',
      content: userMsg,
      created_at: new Date(now).toISOString(),
    },
    {
      user_id: userId,
      conversation_id: conversationId,
      role: 'assistant',
      content: assistantMsg,
      created_at: new Date(now + 1).toISOString(),
    },
  ])
  // Bump the conversation's updated_at so it sorts to the top of the
  // list — and assign a title from the first user message if missing.
  if (conversationId) {
    const { data: existing } = await supabase
      .from('conversations')
      .select('title')
      .eq('id', conversationId)
      .maybeSingle()
    const update: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    }
    if (!existing?.title) {
      update.title = userMsg.length > 48
        ? `${userMsg.substring(0, 45).trim()}…`
        : userMsg
    }
    await supabase
      .from('conversations')
      .update(update)
      .eq('id', conversationId)
  }
}

// ── main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS })
  }

  try {
    const {
      user_id,
      conversation_id = null,
      message,
      history = [],
    }: {
      user_id: string
      conversation_id?: string | null
      message: string
      history: { role: string; content: string }[]
    } = await req.json()

    // ── 1b. Pull out attached-file markers + clean message ────
    // The client embeds [[file:Name.pdf]] markers when the user attaches
    // files to a message. The persisted row keeps them (so the bubble
    // renders preview cards), but the model gets a clean prose version.
    const attachmentMatches = [
      ...message.matchAll(/\[\[file:([^\]]+)\]\]/g),
    ]
    const attachmentNames = attachmentMatches
      .map((m) => m[1].trim())
      .filter((n) => n.length > 0)
    const cleanUserMessage = message
      .replaceAll(/\[\[file:[^\]]+\]\]/g, '')
      .replaceAll(/\n{3,}/g, '\n\n')
      .trim()

    // ── 2. Embed user message ─────────────────────────────────
    // Use the cleaned message (no markers) so the embedding is semantically
    // about the user's actual question.
    const embeddingInput = cleanUserMessage.length > 0
      ? cleanUserMessage
      : (attachmentNames.length > 0
          ? `Discussion about uploaded file ${attachmentNames.join(', ')}`
          : message)
    const embedding = await getEmbedding(embeddingInput)

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

    // ── 4. Fetch hospitals + doctors + file inventory ─────────
    const [
      { data: hospitals },
      { data: doctors },
      { data: ownedFiles },
    ] = await Promise.all([
      supabase.from('hospitals').select('name, address, phone, specialties'),
      supabase.from('doctors').select('name, specialty, phone'),
      // Inventory of the user's own files so the LLM can answer meta
      // questions like "what records do you have on me?" without needing a
      // similarity hit on a specific chunk.
      supabase
        .from('files')
        .select('file_name, file_type, ai_scan_status, notes, extracted_text, created_at, folder_id, folders(name)')
        .eq('user_id', user_id)
        .order('created_at', { ascending: true })
        .limit(50),
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

    // ── 4b. Resolve attached files (their full extracted content) ──
    // The user just attached these to THIS message. We give the model the
    // full extracted JSON for each so it can analyse the file directly,
    // not just rely on chunk-level RAG hits.
    let attachmentsBlock = ''
    if (attachmentNames.length > 0) {
      const { data: attachedRows } = await supabase
        .from('files')
        .select(
          'file_name, file_type, ai_scan_status, extracted_text, notes, created_at, folder_id, folders(name)',
        )
        .eq('user_id', user_id)
        .in('file_name', attachmentNames)
        .order('created_at', { ascending: false })

      // Dedupe by file_name, keep the most recent row per name.
      const seen = new Set<string>()
      const unique: Record<string, unknown>[] = []
      for (const r of (attachedRows ?? []) as Record<string, unknown>[]) {
        const key = (r.file_name as string).toLowerCase()
        if (seen.has(key)) continue
        seen.add(key)
        unique.push(r)
      }

      const formatted = unique.map((a) => {
        const lines: string[] = []
        const date = ((a.created_at as string) ?? '').split('T')[0]
        const folder = (a.folders as { name?: string } | null)?.name
        lines.push(`### ${a.file_name}`)
        const meta: string[] = []
        meta.push(`uploaded ${date}`)
        if (folder) meta.push(`folder "${folder}"`)
        lines.push(`(${meta.join(' • ')})`)
        const note = (a.notes as string | null)?.trim()
        if (note) lines.push(`User's own symptom note: ${note}`)
        const status = a.ai_scan_status as string
        const ex = a.extracted_text as string | null
        if (status === 'done' && ex && ex.trim().length > 0) {
          lines.push('Extracted medical content (JSON from AI scan):')
          lines.push(ex)
        } else {
          lines.push(
            `(Scan status: ${status}. Content not yet extracted — answer based on the filename and any user note above, and let the user know the deep scan is still running.)`,
          )
        }
        return lines.join('\n')
      })

      attachmentsBlock = formatted.join('\n\n---\n\n')
    }

    // Per-file inventory rows now include the AI-extracted summary +
    // headline medical fields so the model can answer questions about a
    // file even when the user doesn't explicitly attach it via marker and
    // RAG doesn't fire on the question. Multi-line per file.
    const inventoryText = ((ownedFiles ?? []) as Record<string, unknown>[])
      .map((f) => {
        const folderName = (f.folders as { name?: string } | null)?.name
        const date = (f.created_at as string).split('T')[0]
        const ext = ((f.file_type as string | null) ?? '').toLowerCase()
        const kind = ext.includes('pdf')
          ? 'PDF'
          : ext.startsWith('image/')
              ? 'image'
              : 'file'
        const status = f.ai_scan_status
        const note = (f.notes as string | null)?.trim()
        const lines: string[] = []
        const head: string[] = [
          `• "${f.file_name}" (${kind})`,
          `uploaded ${date}`,
          folderName ? `in folder "${folderName}"` : null,
          status !== 'done' ? `[scan ${status}]` : null,
        ].filter(Boolean) as string[]
        lines.push(head.join(' '))
        if (note) lines.push(`  • user note: ${note}`)

        const ex = (f.extracted_text as string | null) ?? ''
        if (status === 'done' && ex.trim().length > 0) {
          try {
            const parsed = JSON.parse(ex) as Record<string, unknown>
            const summary = (parsed.summary as string | undefined)?.trim()
            const arr = (key: string) => {
              const v = parsed[key]
              if (!Array.isArray(v) || v.length === 0) return ''
              return v.map((x) => `${x}`).join(', ')
            }
            const diagnoses = arr('diagnoses')
            const medications = arr('medications')
            const symptoms = arr('symptoms')
            const labs = arr('lab_values')
            const doctors = arr('doctor_names')

            if (summary) lines.push(`  • summary: ${summary}`)
            if (diagnoses) lines.push(`  • diagnoses: ${diagnoses}`)
            if (symptoms) lines.push(`  • symptoms: ${symptoms}`)
            if (medications) lines.push(`  • medications: ${medications}`)
            if (labs) lines.push(`  • labs: ${labs}`)
            if (doctors) lines.push(`  • doctors: ${doctors}`)
          } catch (_) {
            // extracted_text wasn't valid JSON — fall back to a snippet.
            lines.push(`  • extract: ${ex.substring(0, 280)}`)
          }
        }
        return lines.join('\n')
      })
      .join('\n\n')

    // ── 5. Build system prompt ────────────────────────────────
    const systemPrompt = `You are MerciMed, a personal medical assistant for a private group of users. This conversation is a FRESH session — treat yourself as a brand-new agent that has only seen the messages in this single conversation thread.

Memory rules:
- You DO know the patient's records (uploaded files, their notes, scan extractions, hospitals, doctors) because those are shared across the patient's whole account.
- You DO NOT know anything the user said or asked in any OTHER conversation. Never reference, summarise, or compare with "previous chats" or "earlier sessions" — only what is in this thread's message history shown to you below.
- If the user asks about a previous chat ("what did we talk about last time?"), say you only have this conversation open and ask them to bring up the question fresh, or offer to look at their records.

You have access to the patient's medical history extracted from their uploaded documents AND any personal symptom notes they attached at upload time. Use both to give personalized, context-aware answers.

Formatting: respond in plain prose only. NEVER use markdown — no **bold**, no *italics*, no #headers, no - bullets, no \`backticks\`. The client renders raw text, so any markdown markers will appear as literal characters and look broken.

ALWAYS cite files by their EXACT filename (copy it character-for-character from the inventory below — do not paraphrase, abbreviate, or rename them). If multiple files informed the answer, name them all. When you reference a past episode, mention the file's date too. Phrase it naturally inside your sentences (e.g. "Your Report_Sophia_Martinez.pdf from May 14 showed…"). The client renders a tappable preview card under your message for every file you name correctly.

Safety on chest symptoms: any complaint involving the chest — pain, tightness, pressure, heaviness, squeezing, discomfort — is a red flag, even when surrounded by soft language ("a bit", "kind of", "slight"). Do NOT downgrade it. Pair it with dizziness, shortness of breath, sweating, jaw/arm pain, or fainting and treat the whole report as urgent. Lead with: "This sounds urgent — please seek care immediately." Then cite any related past records, then recommend the nearest emergency department / hospital from the list, and remind them to call emergency services if symptoms worsen.

Triage symptoms before recommending care:

1) MILD self-manageable symptoms (mild headache, mild fatigue, tiredness, feeling a little dizzy, sore muscles, mild cold/cough, brief nausea, low-grade tiredness):
   - DO NOT recommend a doctor or hospital.
   - Offer 2–4 concrete, actionable tips (hydrate, rest, light meals, short walk, etc.).
   - Suggest checking back if symptoms persist >48 hours or worsen.

2) MODERATE symptoms (persistent for several days, sleep disruption, recurring pain, dizziness with episodes, mild fever):
   - Ask 2–3 short follow-up questions (when did it start? how often? any pattern? anything that helps / makes it worse?).
   - Then suggest seeing a primary care doctor if a pattern emerges. Recommend a doctor/hospital from the lists below only if appropriate.

3) SERIOUS / red-flag symptoms (chest pain, shortness of breath, fainting, severe abdominal pain, vision changes, slurred speech, weakness on one side, very high fever, severe bleeding, suicidal thoughts):
   - Treat it as urgent. Ask the user to seek care immediately, and recommend the closest relevant hospital/doctor from the list below.
   - If immediately life-threatening, tell them to call emergency services right away — don't only recommend a clinic.

Across all cases:
- Use the patient's own history first; surface similar past notes with the file name and date when relevant.
- Always remind them you are not a substitute for professional medical advice — but keep it brief, not at the end of every reply.

When the user asks a meta question like "what records do you have on me?", "which files do you know about?", or "what have I uploaded?", answer using the "Patient's uploaded documents" inventory below — do NOT say there are no records when the inventory is non-empty. Mention each by name so the client can render preview cards.

${
  attachmentsBlock
    ? `=== FILES THE USER ATTACHED TO THIS MESSAGE ===
The user attached the following file(s) directly in this message. Your reply MUST focus exclusively on these. Cite each attached file by its EXACT filename — the client renders a preview card under your reply for every file name you mention.

STRICT RULE: do NOT mention, name, list, or cite any OTHER file from the broader inventory below. Even if a similar file exists, ignore it for this turn. The only exception is when the user explicitly asks for a comparison ("compare this to my last one", "is this different from before?", "show me a pattern across my records") — only then may you reference one (1) other file by name, and only if directly relevant.

${attachmentsBlock}

=== END OF ATTACHED FILES ===
`
    : ''
}Patient's uploaded documents (inventory, ordered oldest first — present them in this same order so the most recent upload appears last):
${inventoryText || 'No files uploaded yet.'}

Patient medical content (from RAG over their files and personal notes):
${ragContext || 'No specific chunks matched the current question, but rely on the inventory above for meta questions.'}

Available hospitals (use only when triage above calls for it):
${hospitalsText || 'No hospitals on file.'}

Available doctors (use only when triage above calls for it):
${doctorsText || 'No doctors on file.'}`

    // ── 6. Call gpt-4o with streaming ─────────────────────────
    // (web_search_preview is a Responses-API tool; not supported in Chat
    // Completions. Keeping the call simple — RAG context above carries
    // the patient's history.)
    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o',
        stream: true,
        max_tokens: 1000,
        messages: [
          { role: 'system', content: systemPrompt },
          ...history,
          {
            role: 'user',
            content: cleanUserMessage.length > 0
              ? cleanUserMessage
              : (attachmentNames.length > 0
                  ? `Please review the attached file${attachmentNames.length > 1 ? 's' : ''}: ${attachmentNames.join(', ')}`
                  : message),
          },
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
                await saveChatMessages(user_id, conversation_id, message, fullResponse)
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
        if (fullResponse) await saveChatMessages(user_id, conversation_id, message, fullResponse)
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
