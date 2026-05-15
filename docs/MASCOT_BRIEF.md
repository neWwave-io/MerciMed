# MerciMed Mascot Brief — "Mercie"

Hand this file to your illustrator. Everything below is the brief; the recommendation at the end tells you who to send it to.

---

## Context

MerciMed is a mobile app for Cambodian families to store their medical records and chat with an AI assistant called **Mercie**. The app is designed for parents, grandparents, and kids — warmth and trust matter more than clinical precision.

The mascot lives as a small character inside a **64 px circular floating button** in the bottom navigation, between HOME and PROFILE. Today that button is a generic teal circle with two sparkle marks; we want to replace it with a character that signals "friendly health companion."

## Brand & palette

Pull colours directly from `mercimed/lib/shared/theme/app_theme.dart`:

| Token | Hex | Use |
|---|---|---|
| `primaryDark` | `#1A2E35` | Mascot ring, outlines |
| `teal` | `#2D6B6B` | FAB background (the circle the mascot lives inside) |
| `muted` | `#6B8A8A` | Soft secondary |
| `background` (gradient start) | `#E6F0F5` | App background top |
| `backgroundEnd` | `#CCE0D6` | App background bottom |

The mascot's body colour should NOT clash with the teal FAB background. Soft pinks, creams, and pale yellows are good; pure white reads sterile.

## Tone

- Warm, calm, gently playful. NOT cute-aggressive (no anime sparkle eyes).
- Reads as friendly across ages 5 → 75.
- Quiet personality — Mercie listens before responding.
- Visual restraint: think Headspace's blob characters, not Duolingo's Duo.

## Cultural notes

- Respectful of Khmer identity but **not religious**. Avoid Buddhist iconography, multi-headed nagas (which read as temple/royal), apsara dancers (royal court symbol), and anything tied to the royal palette of gold-on-red.
- Lotus and folk symbols (krama, peacock) are safe and well-loved.
- The mascot should not require explanation to a Cambodian user — if a grandmother in Battambang sees it and asks "what's that supposed to be?", we've failed.

---

## Concept (the one we want)

**Pisey the Lotus Bud**

A round, pale-pink closed lotus bud with a soft smile and two small leafy arms. Sits inside the existing dark-teal circular FAB. The bud has visible petal layers but stays closed at rest.

Reference visuals (please review before sketching):
- Headspace character work — [Behance gallery](https://www.behance.net/gallery/65940425/Headspace)
- Wysa's penguin coach — [wysa.com](https://www.wysa.com/) (how a small chat-companion can carry a whole brand)
- Lotus in modern Cambodian design — [Southeast Asia Globe — Lotus fashion](https://southeastasiaglobe.com/lotus-flower-luxury-fashion/)
- Duolingo Duo's evolution — [Apple Developer post](https://developer.apple.com/news/?id=e2e1faj4) (only for "how a cartoon body softens a friendly character" — Mercie should be MUCH calmer than Duo)

Personality details to communicate visually:
- Eyes are two small black dots with a single highlight pixel — not anime, not cartoon.
- Mouth is a single subtle curve, closed.
- Petals are slightly translucent at the edges (suggesting freshness, not stiff plastic).
- A soft blush on each petal, hand-painted feel.

---

## Deliverables

### Phase 1 — Static SVG (must-have)

1. **Idle pose** at 128 × 128 px (SVG, inside a transparent square).
   - Body fills ~80% of the canvas.
   - Designed to sit inside a 64 × 64 circular container in-app — so the silhouette must be legible at 32 px.
2. **3 face variants** for user-testing (same body, different expressions: calm, smiling, concerned). Smaller deliverable — just the face crop, ~64 × 64 each.

### Phase 2 — Rive animation (preferred for v1.0)

Convert the static character to a [Rive](https://rive.app) file with **three states**:

1. **Idle breathing** — gentle scale 1.0 → 1.04 → 1.0 over ~2.4 s, loops forever.
2. **Tap response** — single petal layer "blooms" open (1 frame to ~0.35 s), then closes (~0.35 s). Triggered when the user taps the FAB.
3. **Notification bounce** — quick 12 px hop with a soft squash on landing (~0.5 s total). Triggered when the AI has a response ready while the user is on another tab.

Export as a single `.riv` file under 80 KB. Ship to `mercimed/assets/mercie.riv`.

### File specs

- SVG: clean paths, no embedded raster, single root `<svg>` element with `viewBox="0 0 128 128"`, no inline JS, no external font dependencies (convert text to paths).
- Rive: one artboard called `Mercie`, three state-machine inputs: `idle` (bool, default true), `tap` (trigger), `notification` (trigger).
- License: full ownership transfer to MerciMed / neWwave, or perpetual unlimited-use commercial license. No attribution required.

---

## Where it lives in code

When the assets arrive, ship them to:
- `mercimed/assets/mercie.svg` (Phase 1)
- `mercimed/assets/mercie.riv` (Phase 2)

The swap point is already prepared by the engineering team in `mercimed/lib/shared/widgets/app_bottom_nav.dart` — look for the comment `// MASCOT SWAP POINT`. The engineer wiring it in will register the asset in `pubspec.yaml` and replace the sparkle Icon with `Rive` (or `SvgPicture.asset`) without other changes needed.

Add to pubspec.yaml when ready:
```yaml
flutter:
  assets:
    - assets/mercie.riv
    - assets/mercie.svg
```

Optional dep when adopting Rive: `rive: ^0.13.0` (or latest).

---

## Fallback concepts (in case Pisey doesn't test well)

These were considered and ranked. If user testing on Pisey returns lukewarm reactions, fall back in this order:

1. **Mercie the Blob Bunny** — culture-neutral pastel teal blob with rabbit ears and a stethoscope-loop tail. Lowest risk, fastest to ship. References: Wysa penguin, [Calm characters](https://www.calm.com/).
2. **Krama Cloud** — puffy cloud wearing a small red-and-white krama scarf. Khmer identity through folk garment, not religion. Risk: "tourist souvenir" feel if the checker is overdone.
3. **Neary the Naga Hatchling** — chubby one-headed cartoon naga. High upside, high cultural risk — only ship after explicit user validation.

Do NOT brief the illustrator on all four at once — pick Pisey, prototype Pisey, test Pisey, then revisit.

---

## Budget & timing

- Static SVG (Phase 1): **$300–500 USD**, 5–7 days.
- Rive conversion (Phase 2): **$250–400 USD**, 3–5 days, after Phase 1 sign-off.
- Total: **$550–900 USD**, ~2 weeks calendar time.

## Who to brief

In ranked order:

1. **Mooncake Studio (Phnom Penh)** — local studio, strong character work. Search Behance for "Cambodia mascot" to find recent work.
2. **Dribbble — Hire a Designer** filtered to "character/mascot" + Southeast Asia: <https://dribbble.com/designers/hire-a-designer>
3. **Khmer illustrators on Behance** — search "Cambodia illustrator" and filter by character/branding.
4. **Rive animators** specifically for Phase 2: <https://riveanimator.com>.

Send this brief, the three reference URLs above, and the AppTheme palette. Ask for two rough concepts in their first pass before committing to a final.

---

## User testing checklist

Before final sign-off:

- [ ] Show static SVG to 5 Khmer-speaking families (mix of urban Phnom Penh + rural province).
- [ ] Ask: "What is this character? What does it do?" — no leading.
- [ ] Confirm no one reads religious or royal symbolism into it.
- [ ] Confirm kids (5–10) find it approachable, not scary.
- [ ] Confirm grandparents (60+) find it dignified, not childish.
- [ ] If 4/5 reactions are positive on both spectrums, ship. Otherwise iterate one round.
