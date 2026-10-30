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
- The app's Xcode project comes in a later PR.

## Rules

- This repo is public. Never commit secrets, tokens, signing files, team ids,
  Apple account details, email addresses, local paths, or photos with plates
  or faces that aren't blurred. Signing lives in an ignored local file when the
  app arrives. Tools take every path as an argument.
- No third-party packages. Apple's frameworks only.
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
- Every TestFlight upload, internal ones included, is Jamie's call each time.
  Merge as usual, then ask before uploading.
- Codex reviews every PR (`chatgpt-codex-connector[bot]`). Read its findings
  and fix or answer each one before calling the work done.
- What counts as a sign, what players are promised, and who sees what are
  product calls for Jamie. There are no points and no scoreboard.
