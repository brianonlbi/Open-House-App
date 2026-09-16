# Household Finance Tracker — working notes

Read this before changing anything. It holds the decisions already made so a
later session extends the design instead of inventing a second one.

## What this is

A local-only household finance tracker for one couple. One HTML file, opened
from a desktop shortcut, reading bank and credit card statement exports off the
same Mac. No hosting, no accounts, no cloud, no deployment. Financial data never
leaves the machine.

## Hard rules

- **One HTML file.** `finances.html` holds all markup, CSS and JS. No build
  step, no bundler, no `npm install`. Third-party code only from a CDN
  (pdf.js is the one anticipated case). It must stay readable in a text editor.
- **No server-side code.** `start.command` runs `python3 -m http.server` purely
  as a launcher so the page gets a real origin. Nothing else runs on a server.
- **Nothing sensitive in git.** `.gitignore` blocks the data file, its backup,
  `config.json`, and every statement format. The only committed data is the
  anonymized fixtures under `tests/samples/`. This applies to prose too: do
  not write real merchant names, account numbers, card last-fours, or actual
  dollar totals into this file, test names, or code comments. Findings from
  real data belong here as *lessons*, never as *ledgers*.
- **Deterministic categorization.** Rules and overrides only. No model decides
  what a transaction is. "How much on gas" must return the same number every
  time it is asked.
- **Never send transactions off the machine.** The optional AI layer receives
  the *question* plus the category and account names, and returns a query
  descriptor. The math always runs locally. See "Optional NL layer" below.

## Files

| File | Purpose |
| --- | --- |
| `finances.html` | The whole app. |
| `start.command` | Double-clickable launcher. Serves this folder on 127.0.0.1:8777 and opens the app. |
| `finances-data.json` | The source of truth. Gitignored. Created on first run. |
| `finances-data.backup.json` | Previous version, written before every save. One level of undo. Gitignored. |
| `config.json` | Optional, holds the Anthropic API key. Gitignored. |
| `tests/tests.html` | Test page. Open at `localhost:8777/tests/tests.html`. |
| `tests/samples/` | Anonymized statement rows the parser tests run against. Committed. |

## How it runs

`start.command` binds the server to `127.0.0.1` only — nothing on the local
network can reach it. It reuses an already-running server on port 8777 rather
than failing.

The app must be reached over `http://localhost:8777`, never `file://`. On a
`file://` origin Chrome blocks IndexedDB and the File System Access API is
unavailable; the app detects this and says so.

## Persistence

The app asks for the **project folder**, not the data file. A directory handle
is what allows writing `finances-data.backup.json` next to the data file, and
later allows reading a `statements/` subfolder.

Four modes, tracked in `state.mode`:

| Mode | Meaning |
| --- | --- |
| `none` | Nothing connected yet. Empty state offers to connect. |
| `folder` | Directory handle live. Reads and writes `finances-data.json` directly. |
| `cache` | Handle remembered but permission lapsed (normal after a browser restart). Data is intact in IndexedDB; a banner asks for one click to reconnect. |
| `manual` | File loaded by hand, no handle. Saving means "Export data file". For browsers without the File System Access API. |

**Write order on every save**, and it matters: copy the existing
`finances-data.json` to `finances-data.backup.json` *first*, then write the new
version, then refresh the IndexedDB cache. A bad write is always one rename away
from undone.

**On reconnect**, disk wins unless the cached copy has a newer `updated`
timestamp, in which case the cache is flushed to disk. This is the only place
the two copies can disagree.

IndexedDB (`household-finances` / `kv`) holds three keys:
`projectDirHandle`, `dataCache`, `theme`. The cache exists so a reload is never
a blank page and so nothing is lost when permission lapses.

## Data model

`finances-data.json`:

```jsonc
{
  "schema_version": 1,
  "created": "ISO timestamp",
  "updated": "ISO timestamp",
  "accounts":    [ { "id": "...", "label": "...", "institution": "...", "kind": "..." } ],
  "categories":  [ "Gas", "Groceries", ... ],
  "rules":       [ { "match": "SOME GAS CO", "category": "Gas", "note": "..." } ],
  "overrides":   { "<transaction id>": { "category": "...", "type": "..." } },
  "column_maps": { "<source key>": { "date": "Post Date", "amount": "Amount", ... } },
  "transactions": [ /* see below */ ]
}
```

A transaction:

| Field | Notes |
| --- | --- |
| `id` | The dedup hash. See below. |
| `date` | ISO `YYYY-MM-DD`. |
| `amount` | Signed number. **Negative is money out.** |
| `description` | Raw text from the statement. **Never modified, ever.** |
| `account` | Account id, matching `accounts[].id`. |
| `category` | Assigned by rule or override. `Uncategorized` when nothing matches. |
| `type` | `expense`, `income`, or `transfer`. |
| `source_file` | Filename of the import it came from. |
| `notes` | Free text, user's own. Seeded from the issuer's Memo column when present. |

Parsers also attach three fields that are *about the import*, not about the money:

| Field | Notes |
| --- | --- |
| `post_date` | ISO. When the charge settled, vs `date` when it happened. `date` drives every total; `post_date` is for reconciling against a statement. |
| `issuer_type` | The issuer's own row type, verbatim (`Sale`, `Payment`, `Fee`, `Return`). Authoritative about what a row *is*. |
| `issuer_category` | The issuer's category guess. **Kept for reference, never trusted.** See below. |

Two invariants hold everything together:

1. **Raw description is immutable.** Parsers may read it to derive other fields;
   nothing rewrites it.
2. **Every derived field is recomputable from the raw data.** Change a rule and
   the whole history re-derives. Never bake a rule's result in as the only copy.

`migrate()` repairs old or hand-edited files rather than rejecting them — a
missing or wrong-typed array or object is replaced with an empty one, and
`created` is never overwritten. Bump `SCHEMA_VERSION` and extend `migrate()`
together whenever the shape changes.

### Dedup

`id` is a stable hash of `account + date + amount + description` **plus an
occurrence index**. Importing skips any row whose id is already present. Every
import reports **X rows read, Y imported, Z skipped as duplicates** — statements
overlap at the edges and the same file will get re-imported by accident.

**The occurrence index is not optional.** Real statements contain rows that are
identical in every field and are still two different purchases — the first
import of the Chase card had two $26.00 charges at the same merchant on the same
day, and two $25.00 tolls on another day. Hashing only the four fields would
have silently swallowed one of each. The index counts identical tuples in file
order, so those become distinct ids, while re-importing the same file reproduces
the same sequence and therefore still dedups perfectly.

The one case this does not cover: two *overlapping* exports that disagree about
how many copies of an identical row exist in the overlap. That would import the
extra copy. It has not been observed, and the alternative — silently dropping
real transactions — is worse.

The hash is cyrb53 run twice with different seeds, giving ~106 bits. A 32-bit
hash collides at these row counts often enough to lose a transaction. It is
synchronous on purpose so parsers stay pure (`crypto.subtle` is async).

Because the hash covers the raw description, re-parsing the same file always
produces the same ids. A parser change that alters the description would orphan
existing rows; treat that as a migration, not a bug fix.

## Categorization

Rules first, AI never. A rule maps a case-insensitive substring of the raw
description to a category. Rules live in the data file and are edited in the UI.
No match means `Uncategorized`, and the UI shows the backlog count.

**Do not use the issuer's category column as our category.** It is stored as
`issuer_category` for reference and shown in the import preview, but it is not
deterministic. In the first real import, Chase filed the same gas station as
`Groceries` 30 times and `Gas` 10 times — so the user's own example question,
"how much do we spend on gas," cannot be answered from the issuer's labels at
all. That inconsistency is the reason rules exist. `issuer_category` is useful
as a *suggestion* when building the rules list, and as nothing more.

When suggesting rules from merchant names, normalise conservatively. Strip only
per-transaction noise — bare store numbers (`497`, `#3830`), phone numbers, and
mixed alphanumeric transaction ids (`AL8JZT9V22`). Never strip whole alphabetic
words; they are the merchant identity. Note also that one merchant can appear
under several spellings — the first real import had one auto shop billing as
both `SOME SHOP CAR CARE CENTE` and `SOME SHOP CARCARE CENTER`, and together
they were the largest single line of spending. Substring rules handle that
well; exact-match rules would have split it in two and hidden it.

Manual overrides are keyed by transaction id and beat rules. When the user
recategorizes something, offer to turn it into a rule.

### Transfers and refunds — the thing that makes homemade finance apps lie

Paying the Amex from checking is not $3,000 of spending. The checking debit and
the card's own transactions are the same money counted twice.

- Internal movement is `type: "transfer"` and is **excluded from every spending
  total**.
- When the issuer says outright what a row is, believe it. Chase marks card
  payments `Type: Payment`; those become `transfer` at parse time. This is not
  silent auto-classification — the import preview states how many there are and
  what they total, and importing is the user's confirmation.
- For everything else, detect likely transfers by matching a debit in one
  account against a credit of the same amount in another within a few days —
  then **ask for confirmation**. Never auto-classify silently.

How much this matters, measured on the first real import — 23 months of one
credit card: the card payments summed to more than half of what was actually
spent. Counting them as income rather than excluding them as transfers
**understated real spending by over 50%**. This is not an edge case; it is the
single largest source of error in a homemade finance app.
- A refund reduces its category's total. It is not income.

Any total shown anywhere in the UI excludes transfers. If a new aggregation is
added, it excludes transfers too.

## Parser conventions

Each institution gets its own small parser. Keep them uniform:

- One entry per institution in `PARSERS`, keyed by a stable lowercase id
  (`chase_card`, …). The id is also the fixture filename prefix.
- Signature: `parse(text, filename, accountId) => { transactions, problems, flipped }`.
  Pure — no DOM, no state, no network. That is what makes it testable.
  `problems` carries rows that could not be read, with line numbers, so the
  import preview can report them instead of dropping them silently.
- Each parser also exposes `matches(header)` so `detectParser()` can identify a
  dropped file by its header row alone.
- Output the normalized shape above, with `category` left empty; categorization
  is a separate pass so it re-runs when rules change.
- **Normalize the sign at the parser boundary.** Some issuers report charges as
  positive. The parser converts to "negative is money out" so nothing
  downstream has to know which bank it came from. Chase already matches our
  convention, but the parser *verifies* rather than assuming: if more than 80%
  of `Sale` rows come in positive it inverts the file and sets `flipped`, which
  the import preview surfaces. Never trust a sign convention you have not
  checked — importing a year of expenses backwards is silent and ruinous.
- Dates to ISO `YYYY-MM-DD` at the parser boundary too.
- Do not trim, case-fold or clean `description`. Copy it verbatim.
- Unknown CSV shape: show the user the columns, let them map once, save the
  mapping under `column_maps` keyed by a signature of the header row.

Formats, in priority order: CSV (the main path), QFX/OFX (cleaner, worth it if
cheap), PDF (best effort via pdf.js from CDN — show extracted rows for review
before import, never import silently).

## Tests

`tests/tests.html`, opened at `localhost:8777/tests/tests.html`. No runner to
install; it is the same "just open it" model as the app.

It loads `finances.html?test=1` in a hidden iframe. That flag makes the app skip
`start()`, so **running tests never touches the real data file, the folder
permission, or the cache**. The app exposes its pure functions on
`window.__finance`; add each new parser to that object so the test page can
exercise it.

Every parser gets its own block asserting: row count, description kept verbatim,
sign convention, ISO dates, and that parsing the same fixture twice yields
identical ids. The template is in the comment at the bottom of the run function.

## Optional NL layer (build step 8)

The app must be **fully useful with no API key**. Structured filters and preset
questions cover the common cases; the NL box is additive.

When `config.json` holds a key, the question plus the category and account
*names* go to the API, which returns a JSON query descriptor — date range,
categories, accounts, aggregation, threshold. The app executes that descriptor
against local data. The model translates the question; this machine does the
math. Transactions are never sent. Always display the answer, the matching
transactions, and the filter that produced them.

## Interface principles

- Dense and scannable, closer to a spreadsheet than a consumer finance app.
  No oversized cards, no decorative illustrations. Works at full width on 27".
- Numbers right-aligned, monospaced, tabular figures (`.num`).
- **Every number is clickable** and drills into the transaction list filtered to
  exactly what it is made of. No number in this app is a mystery. This is the
  whole point — honor it in every new view.
- Dark mode via `prefers-color-scheme`, overridable by the theme button, stored
  in IndexedDB.

## Build order

Working vertical slices, stopping after each so the user can try it.

1. ✅ HTML shell, launcher, data file load/save, empty state.
2. ✅ One CSV parser for one account, plus dedup, importing into the data model.
3. ⬜ Transaction table with filters. Useful from here on.
4. ⬜ Categorization rules and the overrides UI.
5. ⬜ Transfer and refund handling.
6. ⬜ Overview dashboard with drill-down.
7. ⬜ Preset questions.
8. ⬜ Optional natural language layer.

Update `buildSteps()` in `finances.html` (the `doneThrough` constant) as each
slice lands, and tick the box here.

## Decisions made

**First account: the main checking account.** Chosen deliberately over a credit
card — checking is where paychecks land and where card payments originate, so
building it first means transfers and card payments are visible from the start
rather than being retrofitted at step 5. Institution and column layout are
pinned once the first sample export arrives.

**The category list is derived from real data, not a template.** After the first
import, rank merchants by total dollars, show the user the top ones, and have
them name a category for each. Two reasons this is better than shipping a
standard list: the categories end up matching how this household actually
spends, and the same pass produces the initial rules list for free — naming a
category for a gas station *is* that station’s `→ Gas` rule.

So: do not hardcode a category list anywhere. `categories` stays empty until it
is built from the user's own transactions, and it stays editable afterwards.

**First account in practice: the Chase card, not checking.** The bank site was
unavailable, so a Chase Visa went first. Checking is still wanted, and until it
lands the card payments have only one visible side.

**Import is staged, never immediate.** Dropping a file parses it and shows a
review panel — format, row counts, date range, type breakdown, what will be
treated as a transfer or refund, unreadable rows, and a preview table. Nothing
touches the data file until the user clicks Import. That panel is where "let me
confirm" lives; keep it honest as parsers are added.

**Accounts are inferred from the filename**, e.g. `Chase1234_Activity_*.csv` →
id `chase-1234`, label `Chase …1234`. The label is editable in the review panel
before the first import creates the account.

## Open questions — ask, do not assume

- **The checking account export.** Still needed: it is the other side of all 22
  card payments, and the only place income appears. Chase checking CSV has a
  different header from the card (`Details, Posting Date, Description, Amount,
  Type, Balance, Check or Slip #`), so it needs its own parser.
- **How to treat interest and fees.** Currently plain expenses. They are the
  single largest recurring line in the card data — larger than any merchant —
  so ask whether they want their own category rather than landing in a
  merchant bucket.
- **Whether a given pattern is a transfer.** Always confirm before classifying.
- **Anything that would send data off the machine.** Ask first, every time.
