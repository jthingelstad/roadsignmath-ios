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
  - `MathArt`: draws a way's LaTeX (the `tex` the server and `Equation`
    write) as an image with SwiftMath in Latin Modern, the look of a math
    book, and caches each picture by text, size and color so feeds scroll
    smoothly. `fittingSize` shrinks a long equation to its width instead of
    clipping it.
  - `RoadSignMathAPI`: the client for the server's `/api/v1` and its
    models: the reads (latest, sign, map pins) and the account
    (`auth/start`, `auth/verify` with a code or the email's link,
    `auth/signout`, `GET`/`PATCH`/`DELETE /me`, the token as a Bearer
    header). `SignInLink` reads the email's link, `Handle.preview` ports
    the server's handle slug so the name step can show the address a name
    makes, and `TokenStore` keeps the token: `KeychainTokenStore` (this
    device only, after first unlock, one item per server address) and
    `MemoryTokenStore` for tests. Its tests decode fixtures shaped like
    the server's contract and check each request against a stub
    `URLProtocol`, never a server. The Keychain test needs an app's
    entitlements, so a plain `swift test` on a Mac skips it.
- `RoadSignMath.xcodeproj` and `RoadSignMath/`: the app. SwiftUI, one
  target, the project's folders synchronized, so a new Swift file needs no
  project edit. `Store.swift` holds what the screens share; `Views/` holds
  Home (the feed), the sign page, the Map (MapKit through
  `UIViewRepresentable`, since SwiftUI's `Map` can't cluster pins), and the
  tab bar with the raised Capture button. `Account.swift` is who's signed
  in and the sign-in in progress (an email waiting for its code survives a
  relaunch; after "Send the email again" a code from any of them works; a
  401 on any signed-in call signs out with a word why; deleting and
  reinstalling the app signs out, since the Keychain outlives the app).
  `Views/SignInView.swift` is the sign-in screen (email, code, name,
  welcome), shown on first launch with "Look around first", and
  `Views/MeView.swift` is You: name, email, sign out, delete my account.
  `Theme.swift` is the boards' colors and type: Overpass (bundled, SIL
  OFL, its license beside it in `Fonts/`) for words, Latin Modern for
  math.
- `Config/`: `Info.plist` (it also claims the `roadsignmath://` scheme,
  so `roadsignmath://signin?l=<login>&t=<token>` finishes a sign-in where
  a universal link can't), the entitlements (Associated Domains for
  `roadsignmath.xyz`: the server's AASA covers `/signin` and `/signs/*`),
  and `Signing.xcconfig`, which includes the ignored
  `Signing.local.xcconfig` holding the team (`DEVELOPMENT_TEAM = ...`).
  Signing is Automatic. Never commit the local file or a team id.
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
  `-RSMOpen /signs/<slug>`, `-RSMFocus <sign id>`, `-RSMSearch <words>`,
  and for sign-in `-RSMSignIn <email>` (opens sign-in and sends the
  email), `-RSMCode <digits>`, `-RSMName <name>` (`-RSMNameSave YES`
  saves it) and `-RSMMe YES` (opens You). `RSM_API` also works as a
  default (`xcrun simctl spawn <sim> defaults write xyz.roadsignmath.app
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
- Every TestFlight upload, internal ones included, is Jamie's call each time.
  Merge as usual, then ask before uploading.
- Codex reviews every PR (`chatgpt-codex-connector[bot]`). Read its findings
  and fix or answer each one before calling the work done.
- What counts as a sign, what players are promised, and who sees what are
  product calls for Jamie. There are no points and no scoreboard.
