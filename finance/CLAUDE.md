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
| `tests/samples/` | Anonymized statement rows the parser tests run against. Committed. One `<parser id>-sample.csv` per institution. |

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
recategorizes something, offer to turn it into a rule — `offerRule()` does this
after an inline edit and after a bulk change, and accepting it deletes the
now-redundant overrides. A rule that covers a hundred rows is worth far more
than a hundred pinned rows, and the data file stays small.

`setOverride()` drops an override that merely agrees with the rules rather than
leaving a redundant one behind forever. Clearing a category clears the override
and hands the transaction back.

`resolveCategory(tx, data)` is the single source of truth, and its order is
fixed:

1. a manual override for that exact transaction id
2. the first matching rule
3. the issuer saying the row is interest or a fee → `Interest & Fees`
4. the issuer saying the row is internal movement → `Transfer`
5. `Uncategorized`

`recategorizeAll(data)` re-derives every category from scratch. Call it after an
import and after **any** rule or override change — that is what makes "change a
rule and the whole history updates" true rather than aspirational. Never write a
category anywhere except through this function.

On a deposit account (`kind` of `checking` or `savings`, which sets
`incomeWhenPositive`), money in that is not a transfer and not a refund is
`income`. On a credit card money in is a payment or a refund, never income, so
the flag stays false there. `totalsFor()` keeps income out of `spend` entirely —
income is not negative spending.

**Interest and fees get their own category** (`Interest & Fees`), by explicit
request. They are real expenses and stay in spending totals, but they are not
merchant spending, so burying them in a merchant bucket misrepresents both. Each
parser declares its own `feeTypes` because issuers name them differently — Chase
says `Fee`, Apple says `Interest`.

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

- **Parsers are declared, not written.** `makeCsvParser(spec)` builds one from a
  description of the export, so every institution shares one tested parse loop.
  Adding a card should be a dozen lines of declaration and a fixture — if it
  needs a bespoke loop, extend `makeCsvParser` so every format benefits.
- One entry per institution in `PARSERS`, keyed by a stable lowercase id
  (`chase_card`, `apple_card`, …). The id is also the fixture filename prefix
  and is stamped onto every transaction as `source_parser`.
- A declaration says: `label`, `institution`, `kind`, `required` columns, a `map`
  of our field → their column, `moneyOut` (`"negative"` if the issuer already
  signs money out negative, `"positive"` if purchases arrive positive and must
  be inverted), and which of the issuer's own row types mean `transferTypes`,
  `refundTypes` and `feeTypes`.
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
### Unknown formats: the column mapper

An unfamiliar CSV is not an error. `beginImportFromText` falls through to
`beginMapping`, which shows every column with an example value and lets the user
say which is which, once. The mapping is stored in `column_maps` under
`headerSignature(header)` — a hash of the lower-cased column names — so the next
file with the same columns is recognised with no prompt.

`detectParser(text, data)` checks built-in parsers first, then saved mappings. A
built-in always wins; a mapping can never shadow one.

A saved mapping is just a `makeCsvParser` spec plus `columns`, `accountLabel`
and `created`. `allParsers(data)` rebuilds them all so a mapped parser is a
first-class parser everywhere — including `resolveCategory`, which is why fees
on a mapped account still reach `Interest & Fees`. Mapped parser ids are
prefixed `map:`.

**Two money shapes.** One signed `amount` column, or a `debit`/`credit` pair
where the column itself carries the direction (Citi-issued store cards do this).
With a pair, magnitudes are taken and `amount = |credit| − |debit|`, so the sign
question does not arise and `moneyOut` does not apply. `splitAmounts` is true in
that case and the sign-verification pass is skipped.

**Guessing row-type roles must be token-based, never substring.** This bit a
real file: a bank type of `ACH_CREDIT` is a paycheck, but it contains "credit",
so a substring rule called it a refund and $3,200 of income turned into a
positive "expense" — spending for the account came out above zero. `ACH_DEBIT`
and `DEPOSIT` have the same problem with "transfer". `TYPE_GUESS` therefore
splits the value into word tokens and keeps the lists short, and bare `Credit`
is the only whole-value special case.

Lean towards leaving a row visible. A row in the wrong bucket that still shows
up is easy to spot and retick; one silently excluded from every total is not.
Everything here is a suggestion anyway — the panel shows each type with its row
count, and a live preview built with the real parser, before anything is saved.

The account name typed in the mapper becomes `accountLabel`, which
`inferAccount` prefers over anything derived from the filename. Without that a
mapped account comes out unnamed, and unnamed accounts do not match on the next
import — so every file makes a new account and nothing ever dedups.

Formats, in priority order: CSV (the main path), QFX/OFX (cleaner, worth it if
cheap), PDF (best effort via pdf.js from CDN — show extracted rows for review
before import, never import silently).

### The two formats so far

| | Chase card | Apple Card |
| --- | --- | --- |
| Money out | negative | **positive — inverted on import** |
| Post-date column | `Post Date` | `Clearing Date` |
| Clean merchant name | no | yes, `Merchant` |
| Who spent it | no | yes, `Purchased By` |
| Transfer type | `Payment` | `Payment` |
| Refund type | `Return` | `Credit` |
| Fee type | `Fee` | `Interest` |

The two issuers sign money in opposite directions. That is exactly why
`moneyOut` is declared per parser and then *verified* — never assume a new
institution matches either of these.

Apple also ships a `Merchant` column far cleaner than its `Description`, which
carries the full street address. Both are kept: `description` stays verbatim,
`merchant` holds the clean name. Rules match against **both**, the table shows
`merchant` when present, and a "raw descriptions" toggle reveals the underlying
text. When an issuer gives no merchant column, `merchant` is `""` and everything
falls back to the description.

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

### Overview dashboard

Every figure routes through `drillTo()`, which sets the transaction filters and
switches tabs. That is the contract: **no number on this page is a dead end.**
Tiles, chart columns, category rows and the uncategorized count all drill.

`switchView()` re-renders. Without it, categorizing on one tab leaves the
Overview showing pre-edit numbers, and a dashboard that disagrees with the table
behind it is worse than no dashboard at all.

**Partial months are compared like-for-like.** The newest month in an export is
nearly always incomplete. On the first real data the tile read "36% less than
last month" when the file only ran to the 14th — the truth was 7% *more*.
`totalsThroughDay()` clips the previous month to the same day, and the tile says
which days it compared. Never compare a part-month against a whole one.

`monthlySeries()` fills gaps: a month with no activity is a zero column, not a
missing one, or the time axis compresses and the trend lies about when things
happened.

#### Chart rules

The trend is a **column chart, one series, one colour**. Columns rather than a
line because each column is the click target for "show me that month".

Colours were validated with the dataviz skill's checker, not chosen by eye:

- `--chart-mark` is `#1d63d1` light / `#5690e8` dark. These are **not** the UI
  `--accent`, deliberately: a link is a text colour judged on WCAG contrast, a
  chart mark is judged on the OKLCH lightness band (0.43–0.77 light, 0.48–0.67
  dark). The dark accent `#6fa4ff` sits at L 0.721 and fails that band.
- The red/green `--pos`/`--neg` pair **fails CVD separation** (ΔE 5.1 deutan).
  That is fine for a signed number, which carries a minus sign and a value, and
  is why no chart mark is ever distinguished by red-versus-green alone. If a
  second series is ever added, separate it by something other than those two.
- Do not colour category bars by size or by category. One series, one colour —
  a value-ramp on nominal categories burns the only free channel restating the
  bar length.

Mark specs: columns capped at 24px with a 2px surface gap, 4px rounded cap and a
square foot on the baseline, hairline solid grid (never dashed), labels only on
the selected and the largest column, hit targets spanning the full slot, and a
hover tooltip. Month ticks are counted back from the newest month so the latest
is always labelled and the spacing stays even.

### Recurring charges

`recurringCharges(data, today)` finds what repeats: cadence, the day of the
month when there is one, the next expected date, and monthly and yearly cost.
It needs **no categories** — it works off dates and amounts alone, so it is
useful from the first import.

Three decisions hold it together:

- **Regularity, not frequency.** A shop visited weekly at varying prices is
  frequent, not subscribed. Gaps must land on a cadence at least 60% of the
  time, and anything shorter than 20 days must also have a steady amount —
  without that rule a gas station reads as an $800-a-year subscription and the
  forecast becomes noise.
- **The next charge is priced from the recent past, not the median.** Two years
  of history means prices drift. One real subscription had gone from $20 to $59;
  the all-time median said $44.25, which is a number that was never charged and
  never will be. `expected` is the median of the last three, `typical` stays for
  reference, and `rising` flags the gap.
- **Monthly vs every-four-weeks is decided by the day of the month.** They are
  two days apart as periods. A charge on "the 14th" is monthly; one every 28
  days walks backwards through the calendar. `addMonthsKeepingDay` clamps the
  31st to short months.

`active` means seen within 1.8 cadences. Stopped ones stay listed but are kept
out of the run-rate — a subscription that stopped may just have moved to another
card, which is worth noticing.

### Category colours

Eight categorical hues, fixed order, validated with the dataviz checker for both
surfaces (worst adjacent CVD ΔE 9.1 light / 8.4 dark).

`categorySlot()` assigns by a category's **position in `data.categories`** — its
insertion order — never by rank or current size. Colour follows the thing, not
its row number: if filtering repainted the survivors, someone who learned "Gas
is orange" would be misled. Past eight, categories take the neutral swatch
rather than cycling a hue that already means something else.

Identity rides a **dot beside the label**, never the chart marks. Magnitude bars
stay one colour — recolouring them by category would restate the bar length and
burn the only free channel. Text keeps text tokens.

### Building the category list

`uncategorizedGroups(data)` is the heart of step 4: uncategorized transactions
grouped by merchant, ranked by absolute total. Naming a category for a group
creates the rule, so the category list and the rules come out of one pass — this
is the "build it from my real data" decision made concrete.

Two helpers make that safe:

- `merchantKey(tx)` groups "the same shop". It prefers the issuer's clean
  `merchant` when there is one, so a shop groups across cards even when one
  issuer writes a street address into the description. It strips only bare store
  numbers, phone numbers and mixed alphanumeric transaction ids — never whole
  alphabetic words, which are the merchant's identity.
- `suggestMatch(rows)` proposes the rule text. It only ever takes a **leading
  run of words**, never a key reassembled from non-adjacent ones, because a rule
  must be a genuine substring of what it is meant to match. The shortest
  candidate that covers every row wins, and the result is verified before being
  offered.

**The suggested rule text is editable in the backlog, and that matters.** Real
data had one auto shop billing under two spellings that differ only by a space —
`SOME SHOP CAR CARE CENTE` and `SOME SHOP CARCARE CENTER`. They are two groups
and the conservative suggestion is the full string; shortening it by hand to
`SOME SHOP` catches both, and together they were the largest single line of
spending in the file. Do not try to merge such
groups automatically — collapsing on whitespace would merge unrelated merchants
too. Human judgement belongs exactly here.

`ruleHitCounts(data)` shows how many rows each rule actually claims, in rule
order, so a rule shadowed by an earlier one shows as 0 and can be spotted.

### Transaction view

**Every account gets its own card in the strip above the table**, showing that
account's row count, net spending and how much has been paid to it. Clicking one
filters the table to it; "All accounts" clears it.

**The cards obey every filter except the account one.** They originally showed
all-time totals, which meant setting a date range changed the table and the
footer while the largest numbers on the page silently kept saying something
else — the exact failure this app exists to avoid, and a user caught it within
minutes of first use. `filteredTransactions({ ignoreAccount: true })` is what
the cards read: every other filter applied, so each card answers "what did this
card do in the period I am looking at", and selecting one card does not zero
the others.

When any filter is active, a line under the strip names it in words
(`filterDescription()`) with a one-click escape. Totals that do not say what
they cover are how misleading numbers happen.

Totals sit **above** the table, next to the controls that change them, not in a
footer below a long table where they have to be hunted for. This is how "what do I have
going on with each card" gets answered, and it must keep working as accounts are
added — the strip wraps and nothing is hardcoded per institution.

The Account column appears only when viewing all accounts; it is noise once the
table is filtered to one.

Sorting is by clicking a column header, date descending by default, second click
reverses. Rendering is capped at `state.rowLimit` (500) with a "show all"
control so years of history stay responsive.

Money totals are rounded to cents in `totalsFor()`. Summing floats over hundreds
of rows drifts, and a total that should be zero must read as zero.

Category and notes are edited inline. Changing a category pins that one
transaction (an override) and offers a rule. Ticking rows gives a bulk bar that
sets them all at once, and then offers one rule if a single piece of text covers
the selection — which is looser than grouping by merchant key on purpose:
`Netflix` and `NETFLIX.COM` are different keys but one substring catches both.

Editing is a burst of small changes, so writes go through `scheduleSave()`,
which coalesces them after ~1.2s. Every write also rewrites the backup, and one
good backup beats a hundred near-identical ones.

**Every edit path must re-render through `preserveUI()`, never bare `render()`.**
A rebuild resets the page scroll and every scrolling panel in it. Categorizing
is a hundred small edits in a row, and scrolling back down after each one costs
more than the edit — the first real user hit this immediately and said it made
the job impossible.

`preserveUI` restores the page scroll, each scroll box (matched by position
within the active view, which is stable because the rebuild produces the same
structure), and focus (by an explicit `data-focus-key`). Two details matter:

- **Capture the focus key on the way out, not during the rebuild.** Enter blurs
  the field to commit it, so by the time the re-render runs `activeElement` is
  the body. Editors set `refocusKey` in their change handler.
- **Never call `select()` when restoring focus.** It has no `preventScroll`
  option and reveals its element unconditionally, a frame or two later — the
  exact jump this function exists to prevent. Use `setSelectionRange` instead.

In the backlog the row just categorized leaves the list, so the key that had
focus now belongs to the next merchant: typing carries straight down the list
with no mouse at all.

`saveNow()` calls `renderChrome()` rather than `render()`. A save changes the
header, the status bar and the data-file panel; rebuilding every view for it
threw the scroll away a second after each edit.

**Testing scroll behaviour needs care.** Playwright scrolls an element into
view before acting on it, so measuring before that happens tests the harness
rather than the app — an early version of this test "passed" at scroll position
zero, and separately "failed" against a position Playwright itself had set.
Focus the field first, then measure, then type with the keyboard only. The test
is checked both ways: it fails against the pre-fix file and passes after.
- Dark mode via `prefers-color-scheme`, overridable by the theme button, stored
  in IndexedDB.

### A card two people use

A warehouse card names the member on every row, and on a household card that is
the interesting question — who is this spending. The field was already captured
and mappable, and then thrown away: nothing displayed it and nothing filtered by
it. It now appears as a "By" column and a "Purchased by" filter, both only when
the data actually carries a name, because on a single-holder card they are dead
weight. The column shows first names: a dense table has no room for
"JENNIFER MARTIN" on every row, and the full name is in the title attribute.

The column hides once the table is filtered to one person, the same rule the
Account column already follows — a column whose every cell is identical is
noise.

Beware reading the per-person split before the payments are marked as transfers.
Whoever pays the bill has the payments credited against their name, so their
spending reads far lower than it is; on the first real card this made one
person's total look a third of the other's when the purchases were comparable.

### Bank exports do not say what their rows are

A credit-card export labels its own payments. A bank export often does not: a
checking statement is a flat list where paying a card, paying the mortgage and
buying groceries all look identical. On the first real bank export — two years of
statements, a couple of thousand rows — that gap was worth **tens of thousands
of dollars** of card payments counted as spending on top of the spending already
itemised on the cards themselves.

So **the `Transfer` category carries the meaning**. Name a row Transfer, by rule
or by hand, and `resolveType()` types it as a transfer: out of spending, out of
income, reported on its own. Everything else falls back to what the file said,
which is kept on the row as `parsed_type` and never overwritten. One idea, one
place, and it re-derives from scratch exactly like every other category —
deleting the rules puts every dollar back where the file had it, to the cent.

This is why `resolveCategory()` reads `parsed_type` rather than `type`: once a
rule can change the type, reading the current type would feed the function its
own output.

The import review says so outright when a file carries no row-type column at
all, because the failure is otherwise silent and enormous.

### An account's kind decides how a deposit is read

`incomeWhenPositive` was set only by the Kind dropdown, and Kind defaulted to
credit card. A checking account mapped without touching that dropdown read two
years of payroll as *refunds*, which net against spending. The headline number
came out as a plausible-looking figure that meant nothing at all: two years of
debits minus two years of pay. A wrong number that looks reasonable is worse
than a crash.

`guessKind()` now reads it off the columns: cheque numbers and running balances
belong to bank accounts, not cards. The guess sets `incomeWhenPositive` at the
moment the spec is built, not only when the dropdown is touched.

### A mapping says what format a file is, not which card it came from

Two store cards issued by the same bank export byte-identical columns. The
column mapper is keyed by a hash of the column names, so the mapping saved for
one silently claims the other, and its rows land on the wrong card with nothing
said. This is a real case from the user's own statements, and the account picker
alone was not enough: it was already sitting there, pre-filled with the wrong
account, looking like a decision that had been made correctly.

`fileLooksLikeAccount()` compares the filename against the account's name and,
when nothing matches, the review panel says out loud where the rows are heading
and how to send them somewhere else. It is a weak signal, so it only ever raises
the question — it never reassigns anything on its own.

### Reading the sign convention off a statement with no purchases on it

`guessMoneyOut()` normally learns from the purchases: most rows on a statement
are purchases, so if most amounts are positive the issuer signs money out
positive. A card that was only paid down over the period breaks that — it is
nothing but payments and zero-dollar interest lines, and reading those rows
directly gets the answer exactly backwards, since a payment moves the opposite
way from a purchase.

So when there are fewer than three rows to learn from, the guess is read off the
payments and inverted: money in signed negative means money out is positive. The
same logic protects the safety-net flip in the parser, which also has no
purchases to check against on such a file and correctly leaves it alone.

### Removing a bad import

A finance app that can only add is not trustworthy. Getting an import wrong is
easy — the wrong account, a column mapped to the wrong thing, a row type filed
as the wrong role — and the result is a ledger full of numbers pointing the
wrong way, which is worse than no numbers at all. The first real user messed up
an import within a day, and there was no way out. Two ways out exist now:

- **Undo this import** on the Last import panel takes back *exactly* the rows
  that one file added, by the ids recorded at commit time (`state.lastImport.ids`).
- **The Accounts panel** on the Data file tab removes a whole account and
  everything that came in on it.

Both are **two clicks, never one**: the first arms the action and says out loud
how many transactions will go, the second does it, and there is a "keep it"
escape. A destructive action must never be one stray click away, and it must
state the number before it happens. The backup file is written before every
save, so a removal is also recoverable from disk.

**Removal takes the saved column mapping with it.** This is the half that is
easy to miss. If the mapping was the mistake, removing the account alone fixes
nothing: the same file dropped in again is read by the same bad mapping,
silently, with no chance to correct it. `forgetMappingsFor()` drops any mapping
whose `accountLabel` slugs to the removed account's id, so the next file asks
the mapping question again. `undoImport()` does the same for an account its undo
emptied, and leaves the mapping alone when the account still has rows.

Overrides for removed rows go too, or they sit in the data file forever
pointing at transactions that no longer exist. **Rules stay**: they are not
account-specific and are still wanted.

**The sign radio cannot botch an import, and a test that assumes it can is
wrong.** The parser verifies the sign convention against the parsed rows — if
most non-transfer, non-fee rows come out positive it inverts everything and says
so in the review panel. So "pick the wrong sign on purpose" produces a *correct*
import. A botched-import test has to break something the app cannot second-guess:
declaring a row type the wrong role is the realistic one (every purchase filed
as a payment, and the card's spending vanishes into transfers).

**`migrate()` fills in an account's `kind`.** A hand-written or older data file
may not have one, and the Accounts panel shows it — a missing field there threw
during render and took the whole page down with it. Anything a screen reads off
an account must be repaired on load, not assumed.

## Build order

Working vertical slices, stopping after each so the user can try it.

1. ✅ HTML shell, launcher, data file load/save, empty state.
2. ✅ One CSV parser for one account, plus dedup, importing into the data model.
3. ✅ Transaction table with filters, separated by account.
4. ✅ Categorization rules, the backlog, and the overrides UI.
5. ⬜ Transfer and refund handling (cross-account matching). Needs the checking export.
   ➕ Recurring-charge detection, added out of order: the first real user asked
   for it within an hour of using the app, and it needs no categories to work.
6. ✅ Overview dashboard with drill-down.
7. ⬜ Preset questions. **Next.**
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

**Imports choose their account explicitly.** The filename is a guess, not a
decision. The review panel offers every existing account plus "New account…",
because several cards are in play and two may be the same institution. Changing
the account re-stages the import — the account is part of the dedup hash, so
every id changes with it.

**More accounts are coming**: three store cards, a personal checking account,
and a spouse's cards. Nothing may assume a fixed number of accounts or a single
person. Apple's `Purchased By` column is already captured as `purchased_by` for
exactly that reason.

**A spouse's cards are separate accounts**, decided explicitly. Each card is its
own account with its own card in the strip; "All accounts" is the household
view. Do not build a per-person grouping unless asked — `purchased_by` already
covers who spent what on a shared card.

**"Personal Account" is the checking account**, `kind: "checking"`. It is the
other side of every card payment and the only place income appears.

## Open questions — ask, do not assume

- **The checking account export.** Still needed: it is the other side of every
  card payment, and the only place income appears. Chase checking CSV has a
  different header from the card (`Details, Posting Date, Description, Amount,
  Type, Balance, Check or Slip #`), so it needs its own declaration.
- **Whether a recurring store-card format deserves promoting** from a saved
  mapping to a built-in parser. A mapping works fine; a built-in is only worth
  it when the format needs handling a declaration cannot express.
- **Jen's cards are still to come.** Held up on access, not on anything here.
  They are separate accounts; nothing in the categorization layer needs changing
  for them, and rules apply across every account automatically.
- **Whether a given pattern is a transfer.** Always confirm before classifying.
- **Anything that would send data off the machine.** Ask first, every time.
