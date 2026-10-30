# Road Sign Math for iPhone

Road Sign Math is a road trip game. Find a road sign whose numbers make a true
equation, photograph it, write the math, and post it. Driving + Math = Fun.

This app is the whole game: capture a sign, check the numbers it read, solve
it, post it, and see everyone's signs on a feed and a map. Sign in with an
email link. There are no points and no scoreboard.

The website and the server behind it are in
[roadsignmath.xyz](https://github.com/jthingelstad/roadsignmath.xyz).

## What's here

The app isn't built yet. So far there is `RoadSignMathKit`, a Swift package
for the app's code that isn't a screen. Its first module, `SignReading`, reads
the numbers on a photo of a sign with Apple's Vision and turns what it reads
into numbers a player can use (`82nd St` is 82, `EXIT 7B` reads as 7,
`6AM-10AM` is 6 and 10). [`docs/SPIKE.md`](docs/SPIKE.md) is how well it does
on real signs, and how to run that test again.

```sh
swift test --package-path RoadSignMathKit
```

## License

MIT. See [`LICENSE`](LICENSE).
