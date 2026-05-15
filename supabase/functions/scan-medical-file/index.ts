import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const EXTRACTION_PROMPT =
  'You are a medical data extractor. Extract all medical information from ' +
  'this document and return ONLY a raw JSON object with no markdown, no ' +
  'explanation, just the JSON. The JSON must have these fields: ' +
  'diagnoses (array of strings), ' +
  'medications (array of strings), ' +
  'dates (array of strings), ' +
  'doctor_names (array of strings), ' +
  'lab_values (array of strings), ' +
  'symptoms (array of strings), ' +
  'summary (a short 2-3 sentence plain English summary of this document)'

// Safe base64 encoder that handles large files without stack overflow
function toBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer)
  let binary = ''
  const chunkSize = 8192
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize))
  }
  return btoa(binary)
}

// Split combined text into ~500-word chunks
function chunkText(text: string, maxWords = 500): string[] {
  const words = text.split(/\s+/).filter(Boolean)
  const chunks: string[] = []
  for (let i = 0; i < words.length; i += maxWords) {
    chunks.push(words.slice(i, i + maxWords).join(' '))
  }
  return chunks
}

async function getEmbedding(text: string): Promise<number[]> {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  })
  if (!res.ok) throw new Error(`Embedding API error: ${await res.text()}`)
  const data = await res.json()
  return data.data[0].embedding
}

function buildOpenAIContent(
  base64: string,
  mimeType: string,
  fileName: string,
  isPdf: boolean,
): unknown[] {
  // Chat Completions API content-type names differ from the Responses API:
  // PDFs use `file` (not `input_file`), images use `image_url`.
  const filePart = isPdf
    ? {
        type: 'file',
        file: {
          filename: fileName,
          file_data: `data:application/pdf;base64,${base64}`,
        },
      }
    : {
        type: 'image_url',
        image_url: { url: `data:${mimeType};base64,${base64}`, detail: 'high' },
      }

  return [filePart, { type: 'text', text: EXTRACTION_PROMPT }]
}

Deno.serve(async (req) => {
  // Parse once at the top so error handler can reference fileId
  let fileId: string | undefined

  try {
    // ── 1. Parse webhook payload ──────────────────────────────
    const payload = await req.json()
    const record = payload.record as {
      id: string
      user_id: string
      storage_path: string
      file_type: string
      file_name: string
      notes?: string | null
    }
    const { id, user_id, storage_path, file_type, file_name } = record
    const userNotes = (record.notes ?? '').trim()
    fileId = id

    // ── 2. Download file from Storage ─────────────────────────
    const { data: blob, error: downloadErr } = await supabase.storage
      .from('medical-files')
      .download(storage_path)

    if (downloadErr) throw new Error(`Storage download failed: ${downloadErr.message}`)

    const base64 = toBase64(await blob.arrayBuffer())

    // ── 3. Determine MIME type ────────────────────────────────
    const ft = (file_type ?? '').toLowerCase()
    const isPdf = ft.includes('pdf')
    let mimeType = 'image/jpeg' // default for images
    if (ft.includes('png')) mimeType = 'image/png'
    else if (ft.includes('gif')) mimeType = 'image/gif'
    else if (ft.includes('webp')) mimeType = 'image/webp'
    else if (ft.includes('/')) mimeType = ft // already a mime string

    // ── 4. Call gpt-4o ────────────────────────────────────────
    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'user',
            content: buildOpenAIContent(base64, mimeType, file_name, isPdf),
          },
        ],
        max_tokens: 2000,
      }),
    })

    if (!openaiRes.ok) throw new Error(`OpenAI API error: ${await openaiRes.text()}`)
    const openaiData = await openaiRes.json()
    const rawContent: string = openaiData.choices[0].message.content

    // ── 5. Parse extracted JSON ───────────────────────────────
    let extracted: Record<string, unknown>
    try {
      // Strip potential markdown fences if model misbehaves
      const cleaned = rawContent.replace(/^```json\s*/i, '').replace(/```\s*$/, '').trim()
      extracted = JSON.parse(cleaned)
    } catch {
      // Fallback: wrap raw text so we still store something useful
      extracted = {
        summary: rawContent,
        diagnoses: [],
        medications: [],
        dates: [],
        doctor_names: [],
        lab_values: [],
        symptoms: [],
      }
    }
    const extractedText = JSON.stringify(extracted)

    // ── 6. Build combined text block for chunking ─────────────
    const combinedText = [
      extracted.summary,
      ...((extracted.diagnoses as string[]) ?? []),
      ...((extracted.medications as string[]) ?? []),
      ...((extracted.symptoms as string[]) ?? []),
      ...((extracted.lab_values as string[]) ?? []),
      ...((extracted.dates as string[]) ?? []),
      ...((extracted.doctor_names as string[]) ?? []),
    ]
      .filter(Boolean)
      .join(' ')

    const chunks = chunkText(combinedText, 500)

    // Surface user-provided notes as their own chunk so RAG can find queries
    // like "what did I write about this file?" alongside the model summary.
    // Format chosen so the chat LLM can cite the date + filename when it
    // matches future symptom questions.
    if (userNotes) {
      const today = new Date().toISOString().split('T')[0]
      chunks.unshift(
        `Patient's own symptom notes (uploaded ${today}) attached to file "${file_name}": ${userNotes}`,
      )
    }

    // ── 7. Embed each chunk and insert into ai_chunks ─────────
    for (const chunk of chunks) {
      const embedding = await getEmbedding(chunk)
      const { error: insertErr } = await supabase.from('ai_chunks').insert({
        file_id: id,
        user_id,
        chunk_text: chunk,
        embedding,
      })
      if (insertErr) throw new Error(`ai_chunks insert failed: ${insertErr.message}`)
    }

    // ── 8. Mark file as done ──────────────────────────────────
    const { error: updateErr } = await supabase
      .from('files')
      .update({ extracted_text: extractedText, ai_scan_status: 'done' })
      .eq('id', id)

    if (updateErr) throw new Error(`files update failed: ${updateErr.message}`)

    return new Response(JSON.stringify({ success: true, chunks: chunks.length }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[scan-medical-file]', err)

    // Best-effort: mark file as failed
    if (fileId) {
      await supabase
        .from('files')
        .update({ ai_scan_status: 'failed' })
        .eq('id', fileId)
        .then() // fire-and-forget, don't await to avoid masking original error
    }

    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
