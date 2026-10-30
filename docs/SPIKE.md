# The number-reading spike

How well do Apple's Vision text recognition and the number rules read the
numbers a player used on a sign? The answer sets how much the camera screen
promises. It is not a go or no-go for the app: whatever is read, "Check the
numbers" and "+ Add a number we missed" let the player fix it.

The bar from the plan: every number read on at least 12 of the 16 new-era
photos means live boxes in the camera are realistic.

## Result

**Every number was read on 14 of the 16 new-era signs** (97% of the numbers
players used), reading each photo in six passes. Two passes (the whole photo,
then the part with the text) read every number on 12, just at the bar; one
pass alone, on 9.

`SignReader.photo`, the app's configuration, is the six passes with the sign
rules: accurate recognition, language correction off, photos under 1000 px
wide scaled up 2x first.

| Configuration | New-era full hits | New-era recall | Archive full hits | Archive recall | Mac s / photo |
| --- | ---: | ---: | ---: | ---: | ---: |
| Six passes (whole, text region, four quarters) | 14 of 16 | 97% | 89 of 157 | 77% | 0.68 |
| Two passes (whole, text region) | 12 of 16 | 92% | 84 of 157 | 74% | 0.25 |
| One pass | 9 of 16 | 81% | 71 of 157 | 69% | 0.13 |

Each pass after the first adds only numbers in places no earlier pass read
one, so a number two passes read counts once. Mac timings are a proxy; phone
timings come with the app.

## What the variants showed

- **Vision skips digits that stand alone.** This is the main failure. A
  distance at the end of a row ("Bolivar 4", "Airport 3"), a route number in a
  shield (US 9) or a column of exit distances is often not read at all on the
  whole photo, while the words beside it are. On the archive, 30% of the
  single-digit numbers players used were missed, against 17% of two-digit
  ones. Reading again a crop around the text, and then each quarter of the
  photo, finds most of them: that is where the gain from 9 to 14 comes from.
- **Fast recognition is not usable for this.** It read every number on 1 of
  the 16 new-era photos (16% recall), and nothing at all on most of them.
- **Language correction** made no difference to full hits and cost a little
  recall (it turns some digits into letters). It stays off.
- **Upscaling small photos 2x** helps the archive's small photos (48% to 54%
  full hits with two passes) and does nothing to full-size phone photos.
- **The sign rules read the same values as a plain digits-only baseline**:
  their job is to say why ("Letters dropped", "Read as 7", "Times split in
  two"), and to join `12,000` and `1/2` into one number. Scored on values they
  tie on the new-era signs. On the archive, digits-only got one more sign: a
  parking sign listing lots "1,3,5 / 27,28" that Vision read as "1,3.5" and
  "27.28". The rules now split a list like "1,3.5", but "27.28" stays a
  decimal; "Check the numbers" is the place to split it.

### The new-era signs one by one (six passes)

| Sign | Used | Read | Missed |
| --- | --- | --- | --- |
| I-35W at 82nd Street | 90, 82, 8, 1, 2, 6, 10, 7 | 1, 1, 2, 2, 6, 7, 7, 8, 10, 82, 90, 902 | - |
| On the way to the airport | 25, 1, 8, 4, 3, 3 | 1, 3, 4, 8, 25 | 3 |
| Cancel it all out | 35, 7, 10, 12, 62, 6, 3, 2, 11 | 2, 2, 2, 3, 6, 7, 10, 11, 12, 12, 35, 62 | - |
| Twin Lakes | 5, 1, 2 | 1, 2, 5 | - |
| Mason Math | 105, 5, 136, 36 | 5, 36, 105, 136 | - |
| Iconium | 7, 12, 19 | 1, 1, 7, 12 | 19 |
| Osceola | 5, 1, 6 | 1, 1, 5, 6 | - |
| Bolivar | 10, 4, 12 | 1, 4, 10, 12 | - |
| Genesis (2023), two photos | 3, 33, 99 | 3, 33, 99 | - |
| Fair Play | 83, 4, 6, 3 | 1, 3, 4, 6, 83 | - |
| Fair Grove | 11, 4, 13 | 1, 4, 11, 13 | - |
| Saratoga | 14, 10, 24 | 1, 1, 2, 10, 14, 24, 40 | - |
| Greenbush | 9, 11, 20 | 9, 11, 20 | - |
| Wurtsboro | 12, 1, 13 | 1, 12, 13 | - |
| Gross Vehicle Weight | 70, 90, 80, 13, 65, 45 | 7, 13, 45, 65, 70, 80, 90 | - |
| Phoenix Math | 7, 7, 3, 2, 19, 1 | 1, 2, 3, 7, 7, 19 | - |

The two misses, from looking at the photos:

- **Iconium**: the sign is photographed at a steep angle and "19" is jammed
  against "Appleton City" at the sign's edge. Vision reads it as part of the
  word ("CityLeil", "City B", "City (9" on different passes).
- **On the way to the airport**: the second "3" (Williston) sits against a bolt on the sign and
  is read as part of it.

The extras are mostly real: arrows read as "1" (up arrows beside place names),
other numbers on the sign that the equation didn't use, and once a licence
plate on a car in the photo ("902"). On "Check the numbers" the player removes
those.

## Method

### Test sets

- **New-era signs**: the 16 posts in the micro.blog export's `feed.json`
  (2021-2025). The expected numbers are the number literals in each post's
  `$$...$$` equation, as a multiset, with LaTeX commands dropped
  (`\frac{a}{b}` keeps a and b) and subscripts dropped (the `_0` under an
  `\underbrace` labels a part as zero; it isn't on the sign). Photos are the
  full-size uploads, 1800 px wide. The Genesis post has two photos and is
  scored on the union of what both read. The tool prints the expected
  multisets so they can be checked by eye.
- **Archive signs**: the 157 of the archive's 251 signs (2005-2014) that have
  both a `numbers:` list and a photo file. Their photos are small (about
  350-580 px wide, many cropped from a printed poster). The archive lists only
  the numbers the old rules allowed players to use (distances, not road
  numbers), so extras there are often real numbers on the sign, and precision
  can't be scored.

### Scoring

For each sign, with E the expected multiset and R the multiset of numbers read
(compared by value; a sign's photos united, each value as often as the most
any one photo read it):

- hits = the size of the multiset intersection of E and R;
- recall = hits / |E|, and a **full hit** when every expected number is read;
- extras = |R| - hits.

Each variant reports, per set: signs, full hits (count and share), mean recall,
total extras, and mean seconds per photo (recognition only, on a Mac, after a
warm-up request).

### Variants

Recognition was run four ways (accurate; accurate with language correction;
accurate without upscaling; fast), each keeping every pass's lines and time,
so the one-, two- and six-pass variants come from the same reads. Every
variant is scored with the sign rules and with a digits-only baseline.

## Full tables

### New-era signs (16)

| Variant | Full hits | Full hits % | Mean recall | Extras | s / photo |
| --- | ---: | ---: | ---: | ---: | ---: |
| Accurate, six passes, sign rules (the app's) | 14 | 88% | 97% | 18 | 0.68 |
| Accurate, six passes, digits only | 14 | 88% | 97% | 18 | 0.68 |
| Accurate, text region, sign rules | 12 | 75% | 92% | 14 | 0.25 |
| Accurate, text region, digits only | 12 | 75% | 92% | 14 | 0.25 |
| Accurate, one pass, sign rules | 9 | 56% | 81% | 9 | 0.13 |
| Accurate, one pass, digits only | 9 | 56% | 81% | 9 | 0.13 |
| Accurate, text region, language correction on, sign rules | 12 | 75% | 90% | 14 | 0.30 |
| Accurate, one pass, language correction on, sign rules | 9 | 56% | 79% | 11 | 0.16 |
| Accurate, text region, no upscaling, sign rules | 11 | 69% | 90% | 13 | 0.27 |
| Accurate, one pass, no upscaling, sign rules | 9 | 56% | 81% | 9 | 0.16 |
| Fast, one pass, sign rules | 1 | 6% | 16% | 0 | 0.02 |
| Fast, text region, sign rules | 1 | 6% | 21% | 0 | 0.03 |

The digits-only rows not shown match their sign-rules rows on this set.

### Archive signs (157)

| Variant | Full hits | Full hits % | Mean recall | Extras | s / photo |
| --- | ---: | ---: | ---: | ---: | ---: |
| Accurate, six passes, sign rules (the app's) | 89 | 57% | 77% | 119 | 0.43 |
| Accurate, six passes, digits only | 90 | 57% | 77% | 125 | 0.43 |
| Accurate, text region, sign rules | 84 | 54% | 74% | 92 | 0.19 |
| Accurate, text region, digits only | 84 | 54% | 75% | 98 | 0.19 |
| Accurate, one pass, sign rules | 71 | 45% | 69% | 72 | 0.11 |
| Accurate, one pass, digits only | 71 | 45% | 69% | 78 | 0.11 |
| Accurate, text region, language correction on, sign rules | 83 | 53% | 75% | 79 | 0.18 |
| Accurate, one pass, language correction on, sign rules | 71 | 45% | 69% | 71 | 0.10 |
| Accurate, text region, no upscaling, sign rules | 75 | 48% | 68% | 94 | 0.14 |
| Accurate, one pass, no upscaling, sign rules | 60 | 38% | 62% | 74 | 0.08 |
| Fast, one pass, sign rules | 11 | 7% | 33% | 66 | 0.01 |
| Fast, text region, sign rules | 17 | 11% | 38% | 91 | 0.02 |

On the archive, the signs with nothing read are small, blurred photos where the
sign's text is a few pixels tall.

## Running it

It runs on a Mac (macOS 15 or later) against the archive and the micro.blog
export, which are not in this repo. Every path is an argument:

```sh
swift run -c release --package-path RoadSignMathKit sign-reading-eval \
  --archive <the archive folder: signs/*.md and images/> \
  --microblog <the micro.blog export: feed.json and uploads/> \
  --out <a folder outside the repo>
```

Either set can be left out. `--limit <n>` reads only the first n archive signs.
It takes about four minutes for both sets and writes three files to `--out`:

- `results.json`: every pass's lines for every photo, and every sign's numbers
  and score for every variant;
- `report.md`: the tables;
- `gallery.html`: one page with every photo (at most 800 px wide, inline) and a
  box on each number read for the best variant, green where the player used
  it and yellow where they didn't, new-era signs first, then the archive worst
  first. It shows the photos, so it stays private.
