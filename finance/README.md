# Household Finance Tracker

A local-only view of where our money goes. Reads bank and credit card CSV
exports, keeps everything in one JSON file in this folder, and never touches the
internet.

## Setting it up on the Mac (once)

1. Copy this `finance` folder wherever you want it to live — `~/Documents/finance`
   is fine.
2. Open Terminal once and make the launcher executable:

   ```
   chmod +x ~/Documents/finance/start.command
   ```

   (Only needed if macOS complains that it can't run the file.)
3. Right-click `start.command` → **Make Alias**, and drag the alias to your
   desktop. That's your shortcut.

The first time you double-click it, macOS may say the file is from an
unidentified developer. Right-click → **Open** → **Open** clears that for good.

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

## Where things are

- `finances-data.json` — everything: transactions, rules, notes. **Back this up.**
- `finances-data.backup.json` — the previous version, rewritten on every save.
  If a save ever goes wrong, delete the bad file and rename this one.
- `finances.html` — the whole app, one readable file.
- `start.command` — the launcher.

Neither data file is ever committed to git. Neither are statements.

## If something breaks

**"python3 was not found"** — run `xcode-select --install` in Terminal.

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
