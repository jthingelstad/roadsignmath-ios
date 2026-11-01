# Road Sign Math for iPhone

Road Sign Math is a road trip game. Find a road sign whose numbers make a true
equation, photograph it, write the math, and post it. Driving + Math = Fun.

This app is the whole game: capture a sign, check the numbers it read, solve
it, post it, and see everyone's signs on a feed and a map. There's no password:
sign in with a 6-digit code we email you, or tap the link in that email on
your iPhone. There are no points and no scoreboard.

The website and the server behind it are in
[roadsignmath.xyz](https://github.com/jthingelstad/roadsignmath.xyz).

## What's here

The app so far is the reading half of the game: a Home feed of everyone's
signs, newest first, each with its photo and its math drawn the way a math
book would; a sign's own page with every way it has been solved; and a Map
of where the signs were found. You can sign in (email, then the code or the
link), pick the name that goes on your signs, and see yourself under You,
where you can sign out or delete your account. A sign's ⋯ menu shares it,
reports someone else's sign as inappropriate (the moderator looks again and
takes it down if it agrees) or blocks whoever posted it, and deletes a sign
of your own. Settings lists the players you blocked.

Capture is here too: the green camera button opens the camera, sideways or
upright, marked "Passenger mode" as a reminder that the shot is the
passenger's job. Take a photo, or pick one you took earlier, and every number
it reads gets a yellow box. Check the numbers next: untick the ones you don't
want, fix a misread one, and add one it missed by tapping the photo where it
is or typing it. Then write the math and post it.

`RoadSignMathKit` is a Swift package for the code that isn't a screen.
`SignReading` reads the numbers on a photo of a sign with Apple's Vision and
turns what it reads into numbers a player can use (`82nd St` is 82,
`EXIT 7B` reads as 7, `6AM-10AM` is 6 and 10). [`docs/SPIKE.md`](docs/SPIKE.md)
is how well it does on real signs, and how to run that test again.
`Equation` is the equation checker, the same rules as the server's: it says
whether the math is true, what each side equals, which numbers it used, and
writes the LaTeX the math is drawn from. It passes the server's own test
vectors. `SignCapture` is what Capture needs around the reading: the checked number
list (in reading order, with fixes, removals and additions), the typed number's
rules, a photo's own day and place from its metadata, re-reading the spot a
player taps, and a made-up sample sign for the simulator, which has no camera.
`MathArt` draws that LaTeX with
[SwiftMath](https://github.com/mgriebling/SwiftMath), and
`RoadSignMathAPI` talks to the server: the signs and the map, and signing
in, with the token kept in the Keychain.

```sh
swift test --package-path RoadSignMathKit
xcodebuild -project RoadSignMath.xcodeproj -scheme RoadSignMath \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

To run it on a phone, put your team in an ignored
`Config/Signing.local.xcconfig` (`DEVELOPMENT_TEAM = <your team>`).

The words are set in [Overpass](https://overpassfont.org), under the SIL
Open Font License (its license is in `RoadSignMath/Fonts/`).

## License

MIT. See [`LICENSE`](LICENSE).
