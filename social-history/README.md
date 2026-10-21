# Preschool Social History — iPad interview form

A replacement for the 14-page fillable PDF. The social worker fills it in on an
iPad while interviewing a parent. Answers save automatically, and the form prints
or saves as a clean PDF.

**Answers never leave the device.** The page makes no network requests (a
Content-Security-Policy blocks them). Interviews live in Safari's storage for this
site on that one iPad.

## Files

| File | What it is |
| --- | --- |
| `preschool-social-history.html` | The whole form: questions, styling, autosave, print, export/import |
| `sw.js` | Service worker. Caches the form's own files so it opens with no signal |
| `manifest.webmanifest` | Lets it launch full-screen from the Home Screen |
| `icon.png` | Home Screen icon |
| `index.html` | Redirects the folder URL to the form, for a shorter link |

## Putting it on the iPad

Safari won't run a page opened from the Files app, and saving needs a real web
address. So the form is hosted as a static page by the same GitHub Pages site as
the open house app:

**https://brianonlbi.github.io/Open-House-App/social-history/**

1. On the iPad, open that link in **Safari** (not Private Browsing).
2. Tap **Share → Add to Home Screen → Add**.
3. Open it from the new **Social History** icon. It runs full-screen like an app.
4. Open it once with a connection. After that it works offline.

The pages contain no family data, so it's fine for them to be public. Answers
stay in the iPad's storage.

**Using Vercel instead:** drag the `social-history` folder into a new Vercel
project (no build settings needed) and use that URL in step 1. Interviews saved
under one address can't be seen from another, so export them to JSON before you
switch and import them at the new address.

## Using it

- **Cover sheet:** the app opens here. Type the student's name, check the date
  (today is filled in), and tap **Start questionnaire**. The questionnaire opens
  with the name and date already filled in. Saved interviews are listed below,
  with **Continue**, **Duplicate** (handy for siblings) and **Delete**.
- If the app is closed partway through an interview, it reopens on that interview.
- **Interviews** goes back to the cover sheet. **New** does too, with the cursor
  in the name box.
- **Yes/No:** tap to choose. Tap the chosen answer again to clear it.
- "If yes, explain" boxes are always available. They stay dimmed until the
  answer that needs them is chosen.
- The chips under the header jump to each section and show how many questions
  are answered.
- **Print / PDF:** on the iPad, the form builds a PDF (a cover page, then every
  question) and opens the Share sheet. Choose **Print**, **Save to Files**,
  AirDrop or Mail. iPadOS ignores the normal print command in Home Screen apps,
  so this is how printing works there. On a computer it opens the regular print
  dialog.
- **Export** shares the open interview as `SocialHistory_{Student}_{Date}.json`
  the same way. **Import** (header or cover sheet) loads such a file back, for
  example on another iPad.
- If the Share sheet can't open, a "Your file is ready" box appears instead. Tap
  **Open file** to view and share the file. For exports, **Copy text** is also
  offered.

## Don't lose interviews

- iPadOS can clear website data for sites that aren't used for several weeks.
  Opening the app from the Home Screen icon makes this much less likely. Even so,
  **export each finished interview** (or save its PDF) and keep the file
  somewhere safe.
- Clearing Safari history or website data, or deleting the Home Screen app,
  erases saved interviews.
- If the "Saved ✓" label ever turns red, storage is full or blocked. Export
  right away.

## Changing the questions

Questions are defined in the `SECTIONS` array near the top of the script. Each
answer is stored under its field `id`, so keep existing ids unchanged, or older
saved interviews will lose those answers. If you change any file, bump `CACHE`
in `sw.js` so iPads pick up the new version. The update appears on the second
launch after it's published.
