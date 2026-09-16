# Household Finance Tracker

A local-only view of where our money goes. Reads bank and credit card CSV
exports, keeps everything in one JSON file in this folder, and never touches the
internet.

## Setting it up on the Mac (once)

1. Copy this `finance` folder wherever you want it to live — `~/Documents/finance`
   is fine.
2. The first time only, macOS will refuse to run it. Double-click
   `start.command`, click **Done** on the warning, then open
   **System Settings → Privacy & Security**, scroll to **Security**, and click
   **Open Anyway** next to the message about `start.command`.

   On older macOS a right-click → **Open** → **Open** does the same thing.
   Either way it is once, not every time.

   The blunt alternative, which also works everywhere: open Terminal, type
   `xattr -cr ` (with the trailing space), drag the folder in, press return.
3. Right-click `start.command` → **Make Alias**, and drag the alias to your
   desktop. That's your shortcut.

## Using it

Double-click the shortcut. A Terminal window opens and the app appears in your
browser at `http://localhost:8777/finances.html`.

Leave the Terminal window open while you work — it's the little server that lets
the page save files. Closing it stops the app.

**First run:** click **Connect project folder** and pick this folder. The app
creates `finances-data.json` and from then on reads and writes it directly.

After a browser restart you'll see a **Reconnect** banner. That's normal — the
browser forgets folder permission between sessions. Your data is safe in the
browser's cache until you click it.

`⌘S` saves at any time.

## Adding a statement

Drag a CSV onto the page, or use **Import statement…** on the Data file tab.

You get a review screen before anything is saved: how many rows were read, how
many are new, how many are duplicates you already have, and what will be treated
as a card payment, a refund, or interest. Nothing is written until you click
Import.

**A card the app hasn't seen before** opens a mapping screen instead. It shows
every column in your file with an example value and its best guess at what each
one is. Check it, fix anything wrong, name the account, and save. That format is
remembered from then on — the next file from that card imports straight away.

Re-importing the same file is safe. Overlapping months are safe. Duplicates are
detected and skipped, and the review screen tells you how many.

## Sorting out categories

The **Categorize** tab lists the merchants you haven't categorized yet, biggest
spend first. Type a category next to one and it becomes a rule — applied to
every matching transaction on every card, past and future. Work down from the
top and the biggest numbers get answered first.

The **rule text** next to each merchant is editable. Shorten it when a shop
bills under more than one spelling, and one rule catches them all.

Rules are checked in order and the first match wins, so you can put a specific
rule above a general one. The Rows column shows how many transactions each rule
actually claims — a rule showing 0 is being shadowed by one above it.

In the transactions table you can also type straight into the Category column to
pin a single transaction, and it'll offer to turn that into a rule. Tick several
rows to set them all at once. Notes are editable the same way.

Nothing is ever baked in. Change a rule and the whole history re-derives.

## The overview

The **Overview** tab is the landing page: spending this month against last month
and against the same month a year ago, a column per month going back as far as
your data, and the categories for the month you're looking at, biggest first.

**Every number opens the transactions behind it.** Click a tile, a column, or a
category row and the table opens filtered to exactly those rows. If a figure
ever looks wrong, click it and count.

When the newest month is only part-way through, the tile says "so far" and
compares against the *same days* of the previous month rather than the whole of
it — otherwise a half-finished month always looks like a spending collapse.

Transfers between your own accounts are excluded from every total on this page,
and called out separately so you can see they were counted and set aside.

## Where things are

- `finances-data.json` — everything: transactions, rules, notes. **Back this up.**
- `finances-data.backup.json` — the previous version, rewritten on every save.
  If a save ever goes wrong, delete the bad file and rename this one.
- `finances.html` — the whole app, one readable file.
- `start.command` — the launcher.

Neither data file is ever committed to git. Neither are statements.

## If something breaks

**"This Mac has no working web server built in yet"** — run
`xcode-select --install` in Terminal, click Install, wait, then try again.
macOS ships `/usr/bin/python3` as a stub that does nothing until those tools
are installed, which is why the launcher tests that it actually runs rather
than just that it exists.

**The page loads but nothing saves** — check the top-right pill. If it says
"Cached in browser", click Reconnect on the Data file tab. If it says "Loaded by
hand", the browser doesn't support folder access; use **Export data file** and
replace `finances-data.json` yourself.

**You opened `finances.html` directly instead of using the shortcut** — the app
will tell you. Saving doesn't work that way; use `start.command`.

**Everything looks wrong** — swap `finances-data.backup.json` in for
`finances-data.json` and reload.

## Tests

With the app running, open `http://localhost:8777/tests/tests.html`. Running
tests can't touch your real data.

## Working on the code

See `CLAUDE.md` for the data model, parser conventions, and the decisions behind
how this is built.
