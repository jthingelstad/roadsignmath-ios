# Road Sign Math for iPhone: agent guide

Road Sign Math is a road trip game: find a road sign whose numbers make a true
equation, photograph it, write the math, post it. This repo is the iPhone app.
The website and the server behind it are in
[roadsignmath.xyz](https://github.com/jthingelstad/roadsignmath.xyz).
`README.md` is the overview for people; this file is the working rules.

`CLAUDE.md` is a symlink to this file. Do not fork them.

## Layout

- `RoadSignMathKit/` is a Swift package for everything that isn't a screen.
  - `SignReading`: Vision text recognition (`TextRecognizer`), the number rules
    (`NumberExtractor`: letters dropped, `7B` read as 7, times split in two,
    fractions) and `SignReader`, which reads a photo in passes and merges them.
    It builds for macOS too, so it runs headless on a Mac.
  - `Equation`: the equation checker, a port of the server's
    `src/domain/equation.ts` (tokenizer, parser, checker, `numbersNotOnSign`
    and `tex`). It must agree with the server exactly: the same canonical
    text, the same value text (JavaScript's number printing, ported in
    `JSNumber`), the same error codes and the same LaTeX, byte for byte.
    Exact arithmetic uses a small `BigInt` of its own, since the server's
    uses JavaScript's. Its tests run every case in
    `Tests/EquationTests/Resources/equation-vectors.json`, a byte-for-byte
    copy of the server's `contracts/equation-vectors.json`;
    `scripts/check-vectors.sh` (in CI) fails when they differ. Change the
    server first, copy the file, then make the port pass. A case it can't
    pass is a bug to fix, never one to skip. Text longer than 64
    characters is checked on a thread with a 16 MB stack, since a Debug
    build's recursion overflows 512 KB about 100 brackets deep.
  - `SignReadingEval` and `sign-reading-eval`: the number-reading spike, which
    scores `SignReading` against signs with known numbers. See `docs/SPIKE.md`.
  - `SignCapture`: Capture's logic around `SignReading`. `NumberList`
    is the numbers a player checks (read in reading order: rows top to
    bottom, then left to right; every one ticked to start; fixed, unticked,
    removed or added, up to 30 kept); `values` is what Solve may use.
    `NumberEntry` parses a typed number with the same rules as reading.
    `PhotoFacts` reads a photo's own day, time and place (EXIF and GPS)
    for posting's "place from the photo". `SpotReading` reads the part of
    a photo around a tap again, close up. `SampleSign` draws a made-up
    gantry (EXIT 8, 82nd St, EXIT 7B, 90th St, 1 MILE) with a made-up date
    and place, so the simulator, which has no camera, can run Capture and
    the tests can read a sign without a real photo. Never add real photos
    as fixtures. `WayDraft` is the math written on Solve: tiles (each kept
    number goes in once, so a number shown twice goes in twice) and keys,
    the text the checker reads, the LaTeX to draw with a box where the next
    piece goes, and a status from the checker's own answer.
    `WayDraft.tiles(onSign:)` makes the tiles from a posted sign's numbers,
    for "Find another way". `Draft` and `DraftFolder` (`Drafts.swift`)
    are Drafts: a sign saved for later, its photo as taken, its numbers
    as checked (nil when saved before they were read, so opening it
    reads again) and the math so far (`WayDraft` is `Codable`), a folder
    each in Application Support (`Drafts/`, which the phone's backup
    keeps, unlike the outbox) with a small `thumb.jpg` for the list.
  - `MathArt`: draws a way's LaTeX (the `tex` the server and `Equation`
    write) as an image with SwiftMath in Latin Modern, the look of a math
    book, and caches each picture by text, size and color so feeds scroll
    smoothly. `fittingSize` shrinks a long equation to its width instead of
    clipping it.
  - `RoadSignMathAPI`: the client for the server's `/api/v1` and its
    models: the reads (latest, sign, map pins) and the account
    (`auth/start`, `auth/verify` with a code or the email's link,
    `auth/signout`, `GET`/`PATCH`/`DELETE /me`, `PUT`/`DELETE /me/avatar`
    (API 1.7.0: `setAvatar` sends the photo's bytes and answers with `Me`;
    a 422 `refused` carries the moderator's reason, for the player;
    `avatarUrl` and `avatarThumbUrl` on `Player` and `Me`), the token as a Bearer
    header, which `player(_:token:)` also sends so your own page carries
    your held and hidden signs), and posting (`Posting.swift`:
    `uploadPhoto` sends `POST /photos` the photo's bytes, `postSign` sends
    `POST /signs` a `SignPost` with its `Idempotency-Key`, `addWay` sends
    `POST /signs/{id}/ways` a way's text (201 is the sign with its ways and
    `unlocked`; 409 `conflict` is a way someone already found), and
    `similarSigns` reads `GET /signs/similar`), `popularSigns` reads
    `GET /signs/popular` (API 1.8.0) for Home's Popular tab, `complexSigns`
    reads `GET /signs/complex` (API 1.9.0) for Complexity, hearts (`heart(_:_:token:)`
    sends `PUT` or `DELETE /signs/{id}/heart` and answers with `HeartState`;
    `hearts` and `hearted` on `Sign`; the sign reads take an optional
    token, so a signed-in read says which signs you hearted and is never
    cached for anyone else), keeping it pleasant (`Safety.swift`: `report`
    sends `POST /signs/{id}/report` a reason of at most 300 characters and
    answers with `ReportOutcome`, hidden or kept with the moderator's note;
    `block` and `unblock` send `POST` and `DELETE /players/{handle}/block`;
    `blocks` reads `GET /me/blocks`; `deleteSign` sends `DELETE
    /signs/{id}`, a 503 meaning the sign is still there), feedback and
    the bio (`Feedback.swift`, API 1.10.0: `sendFeedback` sends `POST
    /feedback` a message of at most 2000 characters, `reply_ok` and an
    app line of at most 120, answered 202, ten a day; `updateMe(token:bio:)`
    sends `PATCH /me` a bio of at most 160, empty taking it away), screen views (`ScreenViews.swift`: `ViewPath`
    makes and checks a screen's path as the server's `VIEW_PATH` does,
    `countViews` sends `POST /app/views` with no token, and `ViewCounter`
    batches them, the first a few seconds after a view and then at most
    one batch of 20 every 30 seconds, keeping them while offline, dropping
    a refused batch and resting an hour after a 429), and badges (API 1.6.0,
    `Badges.swift`: `badges()` reads the `GET /badges` catalog, secret
    ones only an id and shelf; `badges` on `Player` and `Me`; `unlocked`
    on a post's answer; `Badges.shelves` puts the catalog and the earned
    ones on the five shelves, `Badges.newest` orders the few on You, and
    `SeenBadges` is which ones this phone has shown, per step).
    `SignInLink` reads the email's link, `Handle.preview` ports
    the server's handle slug so the name step can show the address a name
    makes, and `TokenStore` keeps the token: `KeychainTokenStore` (this
    device only, after first unlock, one item per server address) and
    `MemoryTokenStore` for tests. Its tests decode fixtures shaped like
    the server's contract and check each request against a stub
    `URLProtocol`, never a server. The Keychain test needs an app's
    entitlements, so a plain `swift test` on a Mac skips it.
  - `Posting`: what posting needs off the screen. `OutboxItem` is one
    post on its way (its own `Idempotency-Key`, its upload, its state:
    waiting with a reason, needs sign-in, posted, held with the
    moderator's note, or refused in the server's words), and
    `Delivery.attempt` takes it one step: upload the photo (again if the
    upload is 20 hours old or the server lost it), then post with the
    same key, so a retry is one sign. No connection waits ("Waiting for a
    connection. It'll post on its own."), a busy server backs off (5 s to
    30 min), a rate limit waits an hour, a 401 waits for sign-in, any
    other 4xx is a refusal. A post that left the phone with no answer back
    (a timeout, a dropped connection, a gateway error) may have made the
    sign, so the next try first looks on the poster's own page for a sign
    whose photo is its upload (a sign keeps its upload's id): found, the
    post is done; not there, it goes again with the same key. However long
    the phone waited, a post is never made twice and the player never has
    to look. `OutboxFolder` keeps the queue and its photos
    in Application Support (`Outbox/`, not backed up), so a post survives
    a relaunch. `PostParts` makes the upload (JPEG, upright, no metadata,
    under 4 MB), the numbers (with their text, why and box), the finders
    (none when you found it alone, so the server names you; with others,
    you took the photo and they spotted it, an `@handle` that matches a
    player linking to them), the state from a place, and the title
    suggestion ("Ames Math"). A posted item keeps the badges its post
    unlocked (`PostedSign.unlocked`), so Posted! or Home's note can show
    them later; one found on the poster's page after a lost answer has
    none. Its tests drive the outbox with a fake sender, never a server.
- `RoadSignMath.xcodeproj` and `RoadSignMath/`: the app. SwiftUI, one
  target, the project's folders synchronized, so a new Swift file needs no
  project edit. `Store.swift` holds what the screens share (signed in, its
  reads and a player's page carry your token so they say which signs you
  hearted; Home's four tabs are Latest, Near you, Popular (the most
  hearted first as the server orders them; Jamie, 2026-10-31: "all-time
  hearts, newest breaks ties, unhearted signs last, app first") and
  Complexity (the most complex math first, scored by the server's
  `src/domain/complexity.ts`; the score orders the list and is never
  shown), in a row that slides sideways on a narrow phone, each read
  when first chosen; a 401 there reads again without it and lets `Account` check,
  and an answer read as someone since signed out is read again;
  `Store.heart` shows a heart at once and puts it back if the server
  says no; `heartsGiven` keeps the newest word on each sign hearted on
  this phone (a read begun after the heart's answer updates it) and
  `current(_:)` lays it, and ways added, over every copy of the sign, so
  Home, a kept sign page and a player's timeline agree); `Views/` holds
  Home (the feed), the sign page, the Map (MapKit through
  `UIViewRepresentable`, since SwiftUI's `Map` can't cluster pins; its
  search reads the pins' own place, finders and numbers, from API 1.4.0,
  and its Mine chip, shown once you're signed in with a sign, keeps the
  pins whose finders carry your handle), and the tab bar with the raised
  Capture button. `Account.swift` is who's signed
  in and the sign-in in progress (an email waiting for its code survives a
  relaunch; after "Send the email again" a code from any of them works; a
  401 on any signed-in call signs out with a word why; deleting and
  reinstalling the app signs out, since the Keychain outlives the app).
  `Views/SignInView.swift` is the sign-in screen (email, code, name,
  welcome), shown on first launch with "Look around first", with Privacy
  and About links to the website under the email step, and
  `Views/MeView.swift` is You: your profile (signs, states, the year of
  your first sign), your signs as Home's timeline (the same cards, newest
  posted first) or a grid of photos (a tap opens the sign; held or hidden
  ones only you see say why instead), a warm empty state that opens Capture, and the settings
  sheet (profile photo, name, bio, email, Blocked players with a count,
  Help, About, sign out, delete my account, and the build at the bottom).
  The bio (`BioView`) is one line of at most 160 characters, Return
  being Done. `Views/Help.swift` holds the rest: `HowToPlaySteps` (Spot
  it, Snap it, Solve it and the EXIT 2, COUNTY 5, 1 MILE example, √(5 − 1)
  = 2, the copy from the 1.0 canvas, shared with the first-run card),
  `FeedbackView` (Send feedback: emailed to Jamie, the address being the
  server's `FEEDBACK_TO`, with the player's name and page and
  `Account.feedbackApp`, the build line, the iOS version and the phone's
  model; "Jamie can write back to <email>" is on to start and sends
  `reply_ok`, the only way the email goes along, as the Reply-To),
  `LicensesView` (Overpass, Latin Modern Math, SwiftMath with iosMath,
  and CC BY 4.0 for what players post, each license's whole text read
  from the bundle) and `SitePage`, the website pages the app links to,
  always the live site. `RoadSignMath/Licenses/` holds the license texts
  copied from SwiftMath's checkout (its MIT, iosMath's MIT and the GUST
  Font License); a new dependency's license goes there and on
  `LicensesView`. The profile photo (`Views/ProfilePhoto.swift`): "Choose a
  photo" (PhotosPicker), "Take a photo" (UIKit's camera picker, front
  first; hidden where there's no camera) and "Remove photo", from
  settings or a tap on your own avatar on You (the camera badge), then
  `PhotoCropView`, a square you drag and pinch seen through the circle
  it shows in, sent as a 1024-pixel JPEG by `Account.setPhoto` with a
  plain call ("Try again" on a failure, the server's words when the
  moderator refuses). `Store.showPhoto(of:)` puts it on your cards at
  once, since `/players` may be cached. `Avatar` (`Views/Bits.swift`)
  draws a player's photo over their letter once it's read (through
  `Photos.shared`, at the size shown), wherever the app draws one: the
  Home header, cards, the sign page, Post it's finders, You and player
  pages; `Store.photo(for:)` finds a finder's by handle in `/players`.
  Under the profile is the Badges row (shown with none earned too, so "See all" says how to earn the first): the newest six earned,
  a red dot on any not seen on this phone, and "See all", the shelves
  (`Views/BadgesView.swift`: five shelves, earned in color with the step,
  the day and the sign, a tap opens that sign; not earned faded with how,
  a stepped one showing its first step; secret ones a blank plate
  until earned; each badge's own `BadgeSheet`). `Views/BadgeArt.swift`
  draws every badge natively as the website's `src/web/badges.tsx` does
  (same 64-point grid and colors), and `BadgeRow` is the earned-only row.
  Seen badges live on the phone (UserDefaults, per server and handle):
  the first time a player's badges are read, the ones already earned
  arrive seen, so there's no fanfare on day one; the You avatar on Home
  carries the dot too. Opening the shelves or a Posted! card sees them,
  and so does opening You: any badges not seen on this phone (earned
  on the website, or while the app was away) flip in on a
  `NewBadgesCard` under the profile with a heavy tap, then count as seen.
  Other players: tap a sign's finder for their page
  (`Views/PlayerView.swift`), pushed in whichever tab you're in: You's
  shape (`Views/Profile.swift` holds the header and the Signs or Photos
  view both share), their bio, earned badges only (never a count or the
  ones not earned), and their page on the website. Each tab's stack hands
  its screens an `Opener` (environment) that pushes a sign or a player;
  Home and the Map put a player on their stack of sign ids as `@handle`,
  and a `roadsignmath.xyz/players/<handle>` link (`-RSMOpen
  /players/jamie`) opens one. You reads `GET /me` and your own
  `GET /players/{handle}` with your token, which carries your held and
  hidden signs. `Preferences.swift` holds `BuildInfo`, the stamped
  version, build and commit. Capture always shows "Passenger mode": a
  reminder, never a lock, with no setting to hide it (Jamie, 2026-10-30:
  "passenger mode leave on").
  Capture is `CaptureFlow.swift` (the shot, its reading and the checked
  list, shared by the screens after the camera), `Camera.swift`
  (AVFoundation on its own queue; the preview turns with the phone through
  the rotation coordinator) and `Views/CaptureView.swift` (camera and the
  shot with its numbers boxed), `CheckView.swift` (Check the numbers),
  `NumberSheet.swift` (fix or add a number), `SolveView.swift` (Solve: the
  math on a sign of its own, the numbers as tiles that check off, an
  operator keypad with no digits, and a live "It works"; the board,
  reading, tiles and keypad are `WayEditor.swift`, which "Find another
  way" shares; `WayDraft` in `SignCapture` is the math being written and
  asks `Equation` whether it's true), then posting: `PostView.swift` (Post it: name it; "Say something", an optional
  caption of up to 500 characters in one paragraph (`APIClient.captionMax`,
  the server's cap; Return ends typing) that shows under the title for
  everyone; the place from
  the photo's own GPS reverse-geocoded to a town, or, when the photo has
  none, "Where was it?", a town search; the day found; who found it and
  who spotted it; your name if you've none yet; and "Posted already?",
  the signs nearby with the same numbers, each with "Find another way",
  which starts from the player's own math when its numbers are all on
  that sign), `PostedView.swift` (the post
  on its way, then "Posted!" with its numbers bursting out and any new
  badge flipping in with a heavy tap, "New badge: Square Root", and three
  buttons, "See your sign", "Share it" (its link) and "Snap another sign";
  or why it waits, is held or was refused; `NewBadgesCard` is that card, which
  "Find another way" shares), `Places.swift` (MapKit's reverse
  geocode and town search; never the phone's own location),
  `Outbox.swift` (the queue on the phone: it sends one post at a time,
  sleeps until the next is due, tries again at once when the network
  comes back or the app opens, and bumps `postedCount` so Home and the
  Map read again) and `Views/OutboxNotes.swift` (Home's word about a post
  waiting, posted while you were away, held or refused).
  Drafts, for playing later (Jamie, 2026-10-31: "I take photos of any
  sign that looks hopeful and then I try to solve it later"): "Save for
  later" on the camera's review (the right-hand slot) and in Check's and
  Solve's toolbars (`.savesForLater()`) keeps the shot, its numbers and
  the math so far, and the camera is ready for the next sign. The
  camera's top right shows the Drafts button with a count while any are
  kept; `Views/DraftsView.swift` lists them newest first, a tap picks one
  up on the screen it reached (`CaptureFlow.resume`: Check, or Solve once
  math is begun) and a swipe deletes it. `RoadSignMath/DraftShelf.swift`
  is the list the screens watch; saving again updates the same draft, and
  posting it (into the outbox) removes it. They never leave the phone.
  `Views/AnotherWayView.swift` is "Find another way": from a Home card or
  the sign page (the `findWay` environment, set by `.findsAnotherWay()` on
  each tab's stack), a sheet with the sign, its ways so far and Solve's
  editor on the sign's numbers; a way someone found already reads as
  taken, and a new one goes on through `Account.addWay`, updates the sign
  everywhere (`Store.wayAdded`) and shows "Another way!" with any badge
  it earned. `Views/HeartButton.swift` is a sign's heart and count, on
  Home's cards and beside the finder on the sign page: a tap gives your
  heart with a burst of little hearts (`HeartBurst`, skipped with Reduce
  Motion) and a firm haptic, as the website's kudos button does; another
  takes it back with a light one; signed out it asks "Sign in to heart
  it"; a failure says so in the notice toast. The count is the website's
  and the app's hearts together, hidden when there are none.
  The sign page's ⋯ menu (`SignView.menu`) has Share, then for someone
  else's shown sign Report this sign and Block <poster>, and for your own
  (`posted_by` is your handle) Delete this sign. Reporting has one reason,
  inappropriate (Jamie, 2026-10-31: "we don't need that much yuck… just
  report it as inappropriate"): `Views/Safety.swift`'s `ReportSheet`
  takes an optional note, sends "Inappropriate" or "Inappropriate: <note>",
  and shows the moderator's answer and note, with "Block <poster> too".
  Blocking confirms first and says they aren't told; a blocked player's
  signs leave Home and the map at once (`Store.blocked`), and every list and
  the map read again. The map reads with your token when signed in (API
  `GET /map` leaves out blocked players' signs for that reader and is
  never cached for anyone else). A player's page kept from before leaves
  out signs posted by a player blocked since (`Store.blockedHandles`) and
  reads again on any block or unblock (`Store.blockChanges`).
  Deleting confirms with what goes, counting the ways other players found
  (Jamie, 2026-10-31: yes, deleting takes them too, and the confirm says
  so). A deleted sign, or one a report took down, leaves every list, the
  map and the timelines at once (`Store.signGone`, `Store.gone`), and the
  page closes. A held or hidden sign has no page, so You's "Only you can
  see this one" alert has Delete this sign. Signed out, Report and Block
  ask you to sign in first. Settings has Blocked players
  (`BlockedPlayersView`), each with Unblock.
  Screen views: `countsView(_:)` (`Views/ScreenViews.swift`) counts a
  screen in the site's analytics each time it comes into view, as a page
  load would: a sign page (`/signs/<slug>`), a player's (`/players/<handle>`),
  You (`/you`) and Capture (`/capture`); `RootView` counts Home (`/`) and
  the Map (`/map`) when chosen or come back to. Home and the Map stay
  mounted side by side, so `tabShown` (environment) tells a page kept on
  a hidden tab when its tab is back, and it counts again. `Store.views`
  sends them, with nothing about who looked, and the app sends any
  waiting as it goes to the background (`BackgroundSend`: if the
  system's few seconds run out first, the send is cancelled and they
  wait for the next batch). Counts are never per person.
  `Views/SignInToPost.swift` is the "Sign in to post" alert
  and sign-in sheet that Check, Solve and "Find another way" share
  (`signInFirst` asks the same in its own words, for hearts). The app stands upright except Capture, which
  turns: Info.plist allows both landscapes and `Orientation.swift` narrows
  the rest of the app to portrait. Capture never asks for the phone's
  location; a library photo brings its own day and place.
  `Theme.swift` is the boards' colors and type: Overpass (bundled, SIL
  OFL, its license beside it in `Fonts/`) for words, Latin Modern for
  math.
- `Config/`: `Info.plist` (it also claims the `roadsignmath://` scheme,
  so `roadsignmath://signin?l=<login>&t=<token>` finishes a sign-in where
  a universal link can't), the entitlements (Associated Domains for
  `roadsignmath.xyz`: the server's AASA covers `/signin`, `/signs/*` and `/players/*`),
  and `Signing.xcconfig`, which includes the ignored
  `Signing.local.xcconfig` holding the team (`DEVELOPMENT_TEAM = ...`).
  Signing is Automatic. Never commit the local file or a team id.
- `scripts/testflight.sh` archives main and uploads it to TestFlight
  (`Config/ExportOptions-TestFlight.plist`, internal only unless
  `--external`); `docs/DISTRIBUTION.md` is the road from there to the App
  Store and `docs/PHONE-TEST.md` the pass each build gets on a phone.
- `scripts/version.sh`: the version a build carries, by Your Version
  Number's arithmetic from 30 October 2026 (`scripts/version.sh test`
  checks it). A build phase stamps it, the commit count and the commit into
  the built Info.plist.

## Rules

- This repo is public. Never commit secrets, tokens, signing files, team ids,
  Apple account details, email addresses, local paths, or photos with plates
  or faces that aren't blurred. Signing lives in an ignored local file when the
  app arrives. Tools take every path as an argument.
- Apple's frameworks plus SwiftMath (mgriebling/SwiftMath, pinned to an
  exact version), which draws the math. Any other package is Jamie's call.
- iOS 26 and later, iPhone only, Swift 6 strict concurrency.
- No task groups (`withTaskGroup` and its kin). An optimized build has ended
  one before its children finished and crashed a sibling app on launch, while
  Debug, and every test, ran fine. Run work side by side as one `Task` each,
  awaited in turn.
- Keep the package's tests passing in Debug and optimized:

  ```sh
  swift test --package-path RoadSignMathKit
  swift test -c release -Xswiftc -enable-testing --package-path RoadSignMathKit
  ```

  CI (`.github/workflows/test.yml`) runs both on every PR, after
  `scripts/check-vectors.sh`. Actions are pinned by commit SHA. With the
  server's repo checked out beside this one,
  `ROADSIGNMATH_SERVER=<its folder> swift test --package-path RoadSignMathKit`
  also compares the vectors with that checkout.
- Build the app for the simulator before pushing, as CI does:

  ```sh
  xcodebuild -project RoadSignMath.xcodeproj -scheme RoadSignMath \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
  ```

  A Debug build in the simulator reads the local server (`npm run dev` in
  the server's checkout, after its seed) at `http://localhost:8787/api/v1`,
  and on a phone the live one; set the
  scheme's `RSM_API` environment variable to read another, such as the live
  site (reads only). Release reads `https://roadsignmath.xyz/api/v1`. Debug
  builds also take launch arguments for screenshots: `-RSMTab map`,
  `-RSMFeed popular|complexity` (Home on that tab),
  `-RSMOpen /signs/<slug>`, `-RSMFocus <sign id>`, `-RSMSearch <words>`,
  `-RSMMine YES` (the Map's Mine chip),
  and for sign-in `-RSMSignIn <email>` (opens sign-in and sends the
  email), `-RSMCode <digits>`, `-RSMName <name>` (`-RSMNameSave YES`
  saves it) and `-RSMMe YES` (opens You; `-RSMLook photos` shows the
  grid, `-RSMSettings YES` opens its settings, `-RSMPhoto menu` the
  profile photo's choices, and `-RSMPhoto <file>` squares up a file on
  this Mac as if picked; `-RSMPhotoSave YES` then sends it, so only
  ever against `npm run dev`). Capture's: `-RSMCapture camera`
  opens the camera, `-RSMCapture sample` shoots the sample sign and
  `-RSMCapture <file>` takes a file on this Mac as if picked from the
  library (the simulator reads Mac paths); then `-RSMCheck YES` (Check the
  numbers), `-RSMFix <n>` (the nth number's sheet), `-RSMAdd YES`,
  `-RSMSpot <x>,<y>` (a tap on the photo, 0 to 1 each way), `-RSMSolve YES`
  (with `-RSMWay <math>` to write the math, its numbers taken from the
  tiles) or `-RSMPost YES` (`-RSMWay` there posts the math as solved),
  and `-RSMLandscape YES` to turn sideways. Drafts: `-RSMSaveDraft YES`
  saves the read shot (with `-RSMWay`'s math), `-RSMDrafts YES` opens the
  list on the camera and `-RSMDrafts open` picks up the newest. On Post it: `-RSMTitle
  <name>`, `-RSMCaption <words>`, `-RSMSpotted <a,b>`, `-RSMPostName <name>`, `-RSMSayWhere YES`
  (the town search, `-RSMTown <words>` typed in it, `-RSMTownPick YES`
  picks the first), `-RSMScrollEnd YES` (to the bottom once "Posted
  already?" has its answer), `-RSMPostIt YES` (posts once the form is
  ready) and `-RSMOffline YES` (every send fails as if offline, for the
  waiting screens; a simulator can't drop its network). Badges:
  `-RSMBadges YES` opens You's shelves, `-RSMBadge <id>` opens that
  badge's sheet over them, and `-RSMUnlocked <id,id>` shows Posted! for
  the sample sign as if its post had unlocked those badges (made from the
  catalog, a stepped one at its first step; nothing is sent).
  `-RSMHeart YES` with `-RSMOpen /signs/<slug>` taps the sign page's
  heart two seconds after it opens (`-RSMHeart twice` takes it back after);
  `npm run dev` has hearts off (no counts, and a heart answers 503), so
  seeing one go on needs a dev server given the tests' fake Tinylytics.
  `-RSMFindWay YES` with `-RSMOpen /signs/<slug>` opens "Find another
  way" on that sign (on Post it, on the first sign "Posted already?"
  finds); `-RSMWay <math>` writes the way there too, and
  `-RSMWayAdded <id,id>` shows it gone on with those badges (nothing is
  sent). With `-RSMOpen /signs/<slug>`, `-RSMReport YES` opens the report
  sheet (`-RSMReportNote <words>` writes the note, `-RSMReportSend YES`
  sends it), `-RSMBlock YES` the block confirm (`-RSMBlock send` blocks),
  and `-RSMDelete YES` the delete confirm on your own sign; `-RSMBlocked
  YES` with `-RSMMe YES -RSMSettings YES` opens Blocked players. Sending
  or blocking only ever against `npm run dev`. With `-RSMMe YES
  -RSMSettings YES`: `-RSMBio YES` opens the bio (`-RSMBioText <words>`
  writes it, `-RSMBioSave YES` saves it), and `-RSMHelp
  play|feedback|licenses` opens How to play, Send feedback
  (`-RSMFeedbackText <words>` writes it, `-RSMFeedbackReply NO` turns
  the reply off, `-RSMFeedbackSend YES` sends it; its mail lands in
  the dev server's `.data/mail/`) or Licenses. Saving a bio or sending
  feedback only ever against `npm run dev`. To see the
  You dot or the flip on You, write the seen record with `xcrun simctl
  spawn <sim> defaults write "$(xcrun simctl get_app_container <sim>
  xyz.roadsignmath.app data)/Library/Preferences/xyz.roadsignmath.app"
  'account:<api>:badgesSeen:<handle>' -data <hex of JSON {"keys":[...]}>`
  (the full container path, without `.plist`), with the app quit. Editing
  the plist file directly doesn't stick: cfprefsd writes its own copy back. The token lives
  in the Keychain, which an unsigned simulator build can't write, so for
  anything across relaunches (a post waiting in the outbox) build signed
  for the simulator as for the email's link below. `RSM_API`
  also works as a default (`xcrun simctl spawn <sim> defaults write xyz.roadsignmath.app
  RSM_API <url>`), which a launch from `simctl` without the scheme needs.
- Never sign in, post or report against the live API to test anything:
  `auth/start` emails a real person and `auth/verify` makes a live player.
  Sign in against `npm run dev`, whose emails land in its `.data/mail/`.
  To test the email's link, build signed for the simulator
  (`-allowProvisioningUpdates`, no `CODE_SIGNING_ALLOWED=NO`, so the
  associated domain is there), then take the link from the local mail and
  open it as `https://roadsignmath.xyz/signin?l=<login>&t=<token>` with
  `xcrun simctl openurl`: the app finishes it against the server it
  reads, so the live site is never asked. A `roadsignmath://` link asks
  "Open in?" first, which a headless simulator can't tap.
- TestFlight: `scripts/testflight.sh` uploads main for internal testers
  (`docs/DISTRIBUTION.md`). Jamie, 2026-10-30: "When you have a complete
  build go ahead and send internal build to TestFlight." So the first
  internal upload goes once the core loop works on main (Capture, Check
  the numbers, Solve, Post). After that, upload for a change worth a
  tester's time, not every merge: each upload pings the testers' phones.
  `--external`, the public beta and the App Store are each Jamie's call.
  Each build gets `docs/PHONE-TEST.md` on a real phone.
- Codex reviews every PR (`chatgpt-codex-connector[bot]`). Read its findings
  and fix or answer each one before calling the work done.
- What counts as a sign, what players are promised, and who sees what are
  product calls for Jamie. There are no points and no scoreboard.
