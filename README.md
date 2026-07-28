# Open House Sign In — RE/MAX at Barnegat Bay / The Seegers Group

A full-screen iPad sign-in sheet for open houses. Everything is stored on the iPad
itself; when the open house is over you export a CSV and AirDrop or email it to
your work computer. No accounts, no server, no internet required at the property.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole app — screens, styling, storage, CSV export |
| `sw.js` | Service worker, caches the app so it opens with no signal |
| `manifest.webmanifest` | Makes it launch full-screen from the Home Screen |
| `icon.png` | Home Screen icon |

## Putting it on the iPad

The app is served by GitHub Pages from this repo's default branch, at:

**https://brianonlbi.github.io/Open-House-App/**

1. If Pages is ever turned off: **Settings → Pages → Source: Deploy from a branch**,
   pick the default branch and the `/ (root)` folder, and save. The repo must be
   public for this to work on a free GitHub plan.
2. On the iPad, open the URL above in **Safari**.
3. Tap the **Share** button → **Add to Home Screen** → Add.
4. Launch it from the Home Screen icon. It opens full-screen with no address bar.

Open it once with a connection so it caches itself. After that it works offline.

## Running an open house

1. Open the app. Enter the **property address**, **date**, **start/end time**, and
   the **agent hosting**. Optionally set a 4-digit **admin PIN**.
2. Tap **Start open house**. The visitor form comes up.
3. Visitors fill in whatever they want — nothing is required — and tap **Sign In**.
   A thank-you flashes for two seconds and a blank form is ready for the next person.
4. When you're done, **tap the logo 5 times** to open the admin panel.
5. Tap **Export this open house**. iOS opens the Share sheet — choose AirDrop, or
   Mail to send the CSV to yourself as an attachment.

The app remembers everything, so if the iPad sleeps or Safari closes, reopening it
drops you right back on the sign-in form with the same property.

### Lock the iPad to this app (recommended)

Guided Access stops guests from swiping out of the app or into your email:

**Settings → Accessibility → Guided Access → On**, set a passcode. Then at the open
house, with the app open, **triple-click the top/side button → Start**. Triple-click
and enter your passcode to end it.

## The CSV

One row per visitor, with the property details repeated on each row so multiple
open houses merge cleanly into one spreadsheet:

```
Property Address, Open House Date, Start Time, End Time, Hosting Agent,
Visitor Name, Phone, Email, Working With An Agent, Signed In At
```

`Export all` gives you every open house ever recorded on the iPad. Nothing is
deleted on export — data stays on the iPad until you tap **Erase all stored
sign-ins**, so export before you erase.

## Notes

- A sign-in with all four fields blank is discarded silently, so someone tapping
  the button out of curiosity doesn't leave a junk row.
- Storage is Safari's local storage for this site. Do not use Private Browsing,
  and don't clear website data for the site before exporting.
- Phone numbers are auto-formatted as `(609) 555-1234` while typing.
- Answering the agent question is optional; tapping the selected answer again
  clears it.
