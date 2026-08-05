---
name: lbi-listing-post
description: >
  Fully automated LBI rental listing pipeline for Brian Martin at RE/MAX Barnegat Bay –
  The Seegers Group. Use this skill whenever Brian wants to post a rental property to social
  media — even if phrased casually like "post a listing today," "feature a property,"
  "schedule something for Instagram," "which property should we highlight," or "run the
  listing pipeline." The skill picks the two best properties automatically (most open summer
  weeks, no repeats within 10 days) and schedules two posts per day to Instagram and Facebook
  via Blotato: a single cover-photo post at 9 AM ET and a five-photo gallery post at 3 PM ET,
  each featuring a different property. No browser login required — data is pulled directly
  from the live brianonlbi.com API. Always invoke this skill for any social media post about
  LBI rental properties — do not attempt the pipeline manually without it.
---

# LBI Listing Post Pipeline

Full pipeline: brianonlbi.com API → property selection → Blotato scheduling.

**Two posts per day, two different properties:**

| Slot | Time (ET) | Property | Media |
|---|---|---|---|
| Morning | 9:00 AM | Pick **A** (best available) | 1 image — the cover photo |
| Afternoon | 3:00 PM | Pick **B** (next best) | 5 images — gallery |

Both slots go to **Instagram and Facebook** — four Blotato posts total per run.

**IMPORTANT: Never fabricate property data.** All property details, addresses, and availability
must come from the live API (Step 1). If the API is unreachable, stop and tell Brian rather
than inventing anything.

**Prerequisites:**
- Blotato MCP connected (load via ToolSearch: `blotato_create_post`, `blotato_list_accounts`)
- Adobe CC only if Brian explicitly asks for a branded flyer (see the Optional Flyer appendix)

---

## Step 1: Fetch Live Rental Data

Pull all properties and their availability from the live API:

```bash
curl -s "https://brianonlbi.com/api/rentals"
```

The response shape:

```json
{
  "lastUpdated": "2026-06-12T00:00:23Z",
  "source": "kv",
  "rentals": [
    {
      "id": 1190708,
      "propertyId": 42302,
      "title": "5BR · Ocean Side",
      "address": "217 Sixth Street",
      "town": "Beach Haven",
      "displayTown": "Beach Haven",
      "beds": 5,
      "baths": 3,
      "sleeps": 10,
      "weekly": 5900,
      "weeklyMax": 7500,
      "badges": ["Ocean Side", "Rooftop Deck"],
      "amenityList": ["Dishwasher", "Pool", "Dock", "..."],
      "photos": ["https://realtimerental.com/rrv10/RentalPhotos/1190/1190708.0.jpg", "..."],
      "blurb": "Welcome to your dream...",
      "schedule": [
        {"start": "2026-06-27", "end": "2026-07-04", "rate": 7500, "status": "Available"},
        {"start": "2026-07-04", "end": "2026-07-11", "rate": 7500, "status": "Booked"}
      ]
    }
  ]
}
```

The data refreshes daily at midnight. If the API returns an error or empty `rentals`, stop and inform Brian.

---

## Step 2: Check the Post Log

The post log prevents re-featuring the same property within 10 days.

**Log location (in the Open-House-App repo, so it survives container rebuilds):**
```
<repo>/.claude/skills/lbi-listing-post/post_log.json
```

The repo is normally checked out at `/home/user/Open-House-App`. Resolve the path with:

```bash
REPO="$(git -C /home/user/Open-House-App rev-parse --show-toplevel 2>/dev/null || echo /home/user/Open-House-App)"
LOG="$REPO/.claude/skills/lbi-listing-post/post_log.json"
```

Pull the latest first so a run in a fresh container sees yesterday's entries:

```bash
git -C "$REPO" fetch origin && git -C "$REPO" pull --ff-only origin "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" || true
```

Read the log with the Read tool. If the file doesn't exist, treat as `[]` (empty — no blocked properties).

Format:
```json
[
  {"property_id": "42302", "address": "217 Sixth Street, Beach Haven", "slot": "morning", "posted_at": "2026-06-01T13:00:00Z"}
]
```

Build the **blocked set** from every entry whose `posted_at` is within the last 10 days. Match a
rental against it on **either** key:

- `property_id` equals the rental's `propertyId`, **or**
- `address` matches `address + ", " + town` after normalizing — lowercase, collapse whitespace,
  strip punctuation, and fold the common abbreviations (`ave`/`avenue`, `blvd`/`boulevard`,
  `st`/`street`, `dr`/`drive`, `n`/`north`, `s`/`south`, `w`/`west`, `e`/`east`)

Some historical entries have `property_id: null` because the ID wasn't recoverable when the log
was seeded — the address match is what covers those. Always write **both** keys on new entries.

> If the repo is unreachable or the log can't be read, do **not** silently continue with an
> empty blocked set — say so in the Step 8 report so Brian knows the no-repeat guard was off
> for that run.

---

## Step 3: Select Two Properties

Using the API data from Step 1:

1. For each rental, count `schedule` entries where `status == "Available"` and `start >= today`
   and `start <= "2026-09-05"` — this is its **available week count**
2. Drop any rental with an available week count of 0
3. Exclude any rental whose `propertyId` is in the blocked set
4. Sort by available week count descending; break ties by `weekly` rate descending
5. **Pick A** = the top candidate → the 9 AM cover-photo post
6. **Pick B** = the next candidate, and it must have a *different* `propertyId` than A
   → the 3 PM gallery post

**If only one property survives filtering:** post it in the 9 AM slot only, skip the 3 PM slot,
and say so in the report. Do not post the same property twice in one day.

**If none survive:** the blocked set has eaten the whole portfolio. Relax the window to 5 days,
retry once, and flag it in the report.

---

## Step 4: Gather Property Details

For **each** of A and B, extract from the rental object:

- **Full address**: `address + ", " + town`
- **Beds / baths / sleeps**: `beds`, `baths`, `sleeps`
- **Weekly rate**: `weekly` (the "starting at" price)
- **Location badge**: first entry of `badges` (Ocean Side, Bayfront, Bayside, etc.)
- **Top amenities**: key items from `badges` + `amenityList` (Pool, Hot Tub, Dock, Boat Slip,
  Elevator, Oceanfront, Bayfront, Rooftop Deck)
- **Open weeks**: every remaining `Available` entry with its `rate`, formatted
  `• Aug 8–Aug 15 — $10,000/wk`
- **Listing URL**: `https://brianonlbi.com/rentals/<propertyId>/<slugified address + town>`
- **Blurb**: `blurb` field, for the 3 PM gallery caption

### Media

- **Pick A (9 AM):** `photos[0]` only — the cover photo. One image, nothing else.
- **Pick B (3 PM):** `photos[0]` through `photos[4]` — five images in order.
  If the property has fewer than 5 photos, use every photo it has and note the count in the report.

Photo URLs from the API are publicly accessible and can be handed to Blotato directly as
`mediaUrls` — no upload/presign step is needed.

---

## Step 5: Write the Captions

Keep captions factual — only mention amenities that appear in `badges` or `amenityList`.

### 9 AM — Pick A (cover photo, single image)

**Facebook:**
```
🏠 LBI Rental Available — [Address], [Town]

[X] bed · [X] bath · sleeps [X]
[Location badge]
Starting at $[weekly]/week

Open weeks:
• [Aug 8–Aug 15] — $[rate]/wk
• ...

View the full listing, photos, and calendar:
[listing URL]

📞 Brian Martin · 609-713-5063
📧 brianonlbi@gmail.com

Interested? Message me and I'll help you lock in your week before it's gone.

#LBI #LBIRentals #LongBeachIsland #SummerRental #NJShore #BeachHouseRental #VacationRental #NJBeach #LBISummer #JerseyShore
```

**Instagram:** same body, but **hard limit 5 hashtags** — Blotato rejects Instagram posts with
more than 5. Use `#[Town] #LBI #LongBeachIsland #LBIRentals #NJShore`.

### 3 PM — Pick B (5-photo gallery)

Lead with the property's character rather than repeating the spec sheet — this is the
"take a closer look" post.

**Facebook:**
```
🏡 Get a closer look at [Address] in [Town]! This [X] BR / [X] BA property still has
[N] weeks available through September.

[2–3 sentences drawn from the blurb: standout amenities, who it sleeps, location.]

Weekly rentals from $[weekly]/wk through September. See full details and availability at
brianonlbi.com, or contact Brian Martin at RE/MAX Barnegat Bay – The Seegers Group.

#LBI #LBIRentals #LongBeachIsland #SummerRental
```

**Instagram:** same body, max 5 hashtags. Instagram renders 5 images as a carousel — lead with
the strongest exterior shot.

---

## Step 6: Schedule via Blotato

Load Blotato tools via ToolSearch: `blotato_list_accounts`, `blotato_create_post`.

**Accounts:**
- Instagram: `52078`
- Facebook: `35988` (page ID: `1121854594352155`)

Call `blotato_list_accounts` first to confirm these IDs and the required per-platform fields
before creating posts — do not assume the IDs above are still current.

**Schedule times — next calendar day:**

| Slot | ET | EDT (summer, UTC−4) | EST (winter, UTC−5) |
|---|---|---|---|
| Morning | 9:00 AM | **13:00 UTC** | **14:00 UTC** |
| Afternoon | 3:00 PM | **19:00 UTC** | **20:00 UTC** |

Derive the offset rather than guessing — `TZ=America/New_York date` tells you whether EDT or
EST is in effect.

**Create four posts:**

1. Instagram — Pick A, `mediaUrls: [photos[0]]`, morning time
2. Facebook — Pick A, `mediaUrls: [photos[0]]`, morning time
3. Instagram — Pick B, `mediaUrls: photos[0..4]`, afternoon time
4. Facebook — Pick B, `mediaUrls: photos[0..4]`, afternoon time

After creating them, call `blotato_list_posts` filtered to the target day and confirm all four
came back `scheduled`. If any is missing or `failed`, report it — do not silently retry more
than once.

---

## Step 7: Update the Post Log

Append one entry per property actually scheduled, trim entries older than 30 days, and commit:

```bash
REPO="$(git -C /home/user/Open-House-App rev-parse --show-toplevel)"
LOG="$REPO/.claude/skills/lbi-listing-post/post_log.json"
mkdir -p "$(dirname "$LOG")"
# write the updated JSON to "$LOG" with the Write tool, then:
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
git -C "$REPO" add "$LOG"
git -C "$REPO" commit -m "Log LBI listing posts for <date>"
git -C "$REPO" push -u origin "$BRANCH"
```

Entry format:
```json
{"property_id": "<propertyId>", "address": "<address, town>", "slot": "morning|afternoon", "posted_at": "<ISO timestamp UTC>"}
```

If the push fails (network), retry up to 4 times with backoff (2s, 4s, 8s, 16s). If it still
fails, the posts are already scheduled and that is fine — just flag in the report that the log
did not persist, so the next run may repeat a property.

---

## Step 8: Report to Brian

Summarize in 8 lines or fewer:
- **9 AM — [address, town]**: X BR / X BA, N open weeks, why it won
- **3 PM — [address, town]**: X BR / X BA, N open weeks, why it won
- Confirmation that all 4 posts (IG + FB × 2 slots) came back `scheduled`, with the target date
- Anything degraded: post log unreadable/unpushed, fewer than 5 photos available, a slot skipped

---

## Appendix: Optional Adobe Express Flyer

Brian's default is the plain cover photo for the 9 AM slot. Only build a branded flyer when he
explicitly asks for one.

1. Call `adobe_mandatory_init` before any Adobe tool
2. **Template asset ID:** `urn:aaid:sc:US:4df7774e-c475-58f7-b59a-7031843d1f98`
3. Call `fill_text` with `templateURN` set to that ID and a `description` naming every text
   field to replace (address line, town, bed/bath/sleeps badge, available weeks, weekly rate),
   plus a `generalQuery` describing the replacements without specific addresses or values
4. Call `asset_get_presigned_urls`, download the render, and upload it to Blotato via
   `blotato_create_presigned_upload_url` → `curl -X PUT -T <file>` → `blotato_create_visual` →
   poll `blotato_get_visual_status`

> **Known limitation:** the template's 3 circular photo insets cannot be replaced via
> `fill_text`, so the flyer publishes with placeholder photos unless they're swapped manually at
> https://new.express.adobe.com first. Always flag this if a flyer is used.
