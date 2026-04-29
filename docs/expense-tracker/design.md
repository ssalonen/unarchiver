# Expense Tracker — UI & Data Sketch

Working draft. Five screens, each annotated with the skills, data, and model
calls that sit behind it. Goal: surface design decisions early, before any
code.

Notation:
- `data:` — what's read from / written to local storage
- `skill:` — a tool the LLM can call (only relevant on screens with chat / AI)
- `model:` — when an LLM call happens, and roughly what for

---

## 1. Import / Review

User drops a CSV or PDF statement; we parse, classify, and show a preview
before anything is committed to the ledger.

```
┌─────────────────────────────────────────────────────────────┐
│  Import statement                                           │
├─────────────────────────────────────────────────────────────┤
│  [ Drop file here  or  Browse... ]                          │
│  Supported: CSV, PDF (bank statements)                      │
│                                                             │
│  ── Preview (37 transactions found) ──────────────────────  │
│                                                             │
│   Date        Merchant            Amount   Category  ✓     │
│   2026-04-12  K-Market Töölö      -23,40   Groceries ✓     │
│   2026-04-12  HSL                  -2,95   Transport ✓     │
│   2026-04-13  Ravintola Sandro   -48,00   Dining    ?     │
│   2026-04-14  Spotify              -9,99   Subs      ✓     │
│   ...                                                       │
│                                                             │
│   3 need review · [ Auto-categorize all ]  [ Import 37 ]   │
└─────────────────────────────────────────────────────────────┘
```

- `data:` raw file → parsed `Transaction[]` (date, merchant, amount,
  raw_description). Nothing persisted until user clicks Import.
- `skill:` not chat-driven, but parsing pipeline calls:
  - `parse_csv(file)` / `parse_pdf(file)` → deterministic, no LLM
  - `categorize(transactions[])` → batch LLM call with merchant + amount
- `model:` one cheap LLM call per batch (Haiku-class). Returns
  `{tx_id, category, confidence}`. Confidence < threshold → flagged `?` for
  review.

Open question: do we cache merchant→category mappings locally so a second
import of the same merchant skips the LLM? (Probably yes — saves cost and
makes categorization deterministic across imports.)

---

## 2. Ledger

The default view. Flat, scannable list. Inline edits for category and notes.

```
┌─────────────────────────────────────────────────────────────┐
│  April 2026                          [ < Mar ]  [ May > ]   │
│  Spent: 1 842,30 €    Income: 3 200,00 €    Net: +1 357,70 │
├─────────────────────────────────────────────────────────────┤
│  Apr 14  Spotify              Subs        -9,99             │
│          📝 family plan, split with sibling                │
│  Apr 13  Ravintola Sandro     Dining     -48,00             │
│  Apr 12  K-Market Töölö       Groceries  -23,40             │
│  Apr 12  HSL                  Transport   -2,95             │
│  Apr 11  Salary               Income  +3 200,00             │
│  ...                                                        │
│                                                             │
│  [ + Add transaction ]   [ Import statement ]               │
└─────────────────────────────────────────────────────────────┘
```

- `data:` reads `transactions` table filtered by month. Writes on inline
  edit (category change, note edit).
- `skill:` none — pure CRUD view.
- `model:` none.

User notes live on the transaction row. Two reasons: (1) jogs memory later,
(2) feeds the chat agent better context when asked "what was that 48€
dinner?".

---

## 3. Category drill-down

Reached by tapping a category name anywhere. Shows the month's spend in that
category with a small trend strip.

```
┌─────────────────────────────────────────────────────────────┐
│  Dining · April 2026                                        │
│  312,40 €   (▲ 18% vs Mar · ▲ 34% vs 3-mo avg)             │
│                                                             │
│  ▁▂▃▅▂▁▃▅▇▃▂▁▂▅▇▂▁  daily spend                            │
│                                                             │
│  ── Transactions ──────────────────────────────────────────│
│   Apr 27  Ravintola Savoy           -94,00                  │
│   Apr 22  Wolt (Burger Place)       -28,50                  │
│   Apr 13  Ravintola Sandro          -48,00                  │
│   ...                                                       │
│                                                             │
│   [ Ask about this category ] ← opens chat pre-seeded       │
└─────────────────────────────────────────────────────────────┘
```

- `data:` aggregate query (sum by day, sum by month for last N months) +
  transaction list filtered by category+month.
- `skill:` none directly. The "Ask" button hands off to chat with context
  like *"User is viewing Dining, April 2026"* prepended.
- `model:` none until chat opens.

---

## 4. Chat

The interesting one. Conversational interface; the agent's tool calls are
visible as collapsible chips so the user can see *why* it answered the way
it did.

```
┌─────────────────────────────────────────────────────────────┐
│  Ask                                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  You: How come the restaurant bill is so high this month?   │
│                                                             │
│  ▸ called summary(category="Dining", month="2026-04")      │
│  ▸ called compare(category="Dining",                        │
│                    a="2026-04", b="2026-03")               │
│  ▸ called drill_down(category="Dining", month="2026-04")   │
│                                                             │
│  AI: You spent 312€ on dining in April vs 264€ in March    │
│      (+18%). Two outliers drove most of the gap:            │
│        • Ravintola Savoy on Apr 27 (94€) — your largest    │
│          single dining bill in 6 months                    │
│        • Three Wolt orders in week of Apr 21 (78€ total)   │
│      Without those, April would have been ≈140€, below     │
│      your 3-month average.                                  │
│                                                             │
│  You: Where could I save 10€/month to buy a 120€ gift in   │
│       a year?                                               │
│                                                             │
│  ▸ called find_savings(target=10, horizon_months=12)       │
│                                                             │
│  AI: Easiest candidates from your spend pattern:            │
│        • Spotify Family — 9,99€/mo (you noted you split    │
│          this — confirm sibling actually pays?)            │
│        • Wolt fees — averaging 12€/mo in delivery fees     │
│        • Two unused subs: ...                              │
│                                                             │
│  [ Type a question...                              ↵ ]     │
└─────────────────────────────────────────────────────────────┘
```

- `data:` reads transactions, notes, and AI memory file (see screen 5).
  Writes nothing to ledger directly — but may append to AI memory.
- `skill:` core toolset the LLM can call:
  - `summary(category?, month?)` → totals + counts
  - `compare(category?, period_a, period_b)` → deltas
  - `drill_down(category, month, limit?)` → transaction list
  - `find_recurring()` → subscriptions / recurring charges
  - `find_savings(target, horizon_months)` → ranked candidates
  - `read_notes(tx_ids[])` → user notes for a set of transactions
  - `read_memory()` / `write_memory(key, value)` → AI's own scratchpad
- `model:` Sonnet-class for the chat loop (tool selection + synthesis).
  Each turn: 1 model call → optional tool calls → 1 model call to
  synthesize. Aggregates fit easily; drill-downs are paginated to keep
  context bounded.

Design rule: **the agent never invents numbers**. If it can't justify a
figure from a tool result, it says so. Worth an eval later.

---

## 5. Goals & memory

Where savings targets live, and where the AI's persisted observations are
visible (and editable — user should always be able to delete what the AI
"remembers").

```
┌─────────────────────────────────────────────────────────────┐
│  Goals                                                      │
├─────────────────────────────────────────────────────────────┤
│   🎁 Sibling's birthday gift                               │
│      120€ by April 2027   ·   on track (saved 12€ so far)  │
│      Source: cancelled second Spotify account              │
│                                                             │
│   [ + New goal ]                                            │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  What the assistant remembers about you                    │
├─────────────────────────────────────────────────────────────┤
│   • Eats out ~8×/month, mostly Fri–Sat        [ forget ]   │
│   • Splits Spotify Family with sibling        [ forget ]   │
│   • Monthly take-home ≈ 3 200€                [ forget ]   │
│   • Saving for 120€ gift, April 2027          [ forget ]   │
│                                                             │
│   [ Clear all memory ]                                      │
└─────────────────────────────────────────────────────────────┘
```

- `data:` `goals` table + a local `ai_memory.json` file (or single-table
  key/value). Both fully user-visible and user-editable.
- `skill:` `read_memory()`, `write_memory()`, `list_goals()`,
  `update_goal_progress(goal_id, amount)`.
- `model:` no live model call on this screen, but every chat turn reads
  memory at the start and may propose a `write_memory` at the end.

---

## Data model (sketch)

```
transactions
  id, date, merchant, raw_description, amount, currency,
  category, confidence, note, source_file, imported_at

merchant_aliases               -- learned merchant → category cache
  merchant, category, source ("user" | "ai"), updated_at

goals
  id, title, target_amount, target_date, created_at,
  progress_amount, source_note

ai_memory                      -- single JSON blob or k/v rows
  key, value, created_at, last_used_at
```

Everything local. No accounts, no cloud sync in v1. (Opens the door to a
local-first sync layer later, but that's a v2 problem.)

---

## Build order

1. Import + ledger + categorization (screens 1, 2). Proves the data
   substrate.
2. Category drill-down (screen 3). Aggregates working.
3. Chat with `summary` / `compare` / `drill_down` only (screen 4, partial).
   Validates the tool-calling loop on a small skill set.
4. Goals + memory (screen 5) and the savings skills. Closes the loop from
   "insight" to "action".

Each step is shippable on its own.
