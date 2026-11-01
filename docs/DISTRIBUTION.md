# From TestFlight to the App Store

Road Sign Math goes out in three steps: TestFlight for Jamie's developer
team, TestFlight for a public group of players, then the App Store. When
to upload is in `AGENTS.md`; outside testers and the App Store are each
Jamie's call.

## Once, before the first upload

- **The bundle id.** `xyz.roadsignmath.app`, with Associated Domains, is
  registered with Apple: a signed device build from Xcode did it on
  30 October 2026. An App Store Connect API key can't register a new
  bundle id or make its first profile, so any new target (a widget, say)
  needs one archive with Xcode's own sign-in first.
- **The app in App Store Connect.** Made on the web (the API can't make
  one), for `xyz.roadsignmath.app`, with an internal group of testers.
- **Signing.** `Config/Signing.local.xcconfig` holds the team, and
  `Config/AppStoreConnect.local` the API key's ids (both ignored by git;
  see `scripts/testflight.sh`).

## 1. Internal testers

`scripts/testflight.sh` archives a clean commit on main and uploads it,
marked internal only (`testFlightInternalTestingOnly` in
`Config/ExportOptions-TestFlight.plist`). Internal builds need no review
from Apple. The version is the one in `VERSION` (`scripts/version.sh`),
set by hand; the build number is the commit count, so a commit uploads
once. Each build gets
[a pass on a real phone](PHONE-TEST.md).

## 2. The public beta

Jamie made the Beta group and its public invite on 31 October 2026, and
roadsignmath.xyz links it from Home's app section. Apple calls these
external testers. It takes:

- **A build that isn't internal only.** `scripts/testflight.sh --external`
  leaves `testFlightInternalTestingOnly` out. The commit needs its own
  upload: one already uploaded internal only has used its build number, so
  a docs-only commit is enough to make a fresh one.
- **Test information** under TestFlight in App Store Connect: a Beta App
  Description, a feedback email, a contact and a privacy policy URL
  (roadsignmath.xyz/privacy).
- **A sign-in for Apple's reviewers.** Anyone can sign up with an email
  address, so reviewers sign in with their own and get the 6-digit code
  there; no demo account. "Look around first" shows the signs without
  signing in. The review notes say both.
- **Review.** The first external build gets a full Beta App Review, about
  a day. A build stays installable for 90 days. Apple reviews one build
  per version at a time.
- **Each round is Jamie's call** (Jamie's go on 31 October 2026 was for
  the first).

## 3. The App Store

Later, on Jamie's go. What the listing needs, ready to fill in:

- **Privacy** (App Privacy in App Store Connect), the same as
  `RoadSignMath/PrivacyInfo.xcprivacy`. No tracking. Linked to the
  player, for App Functionality: Contact Info (email address, for
  sign-in), Name, Identifiers (user id: the handle), User Content
  (photos; other content: titles, captions, the math, the bio; customer
  support: Send feedback), Location (precise: a photo's own place, posted
  with the sign). Not linked, for Analytics: Usage Data (product
  interaction: screen views, counted with nothing about who looked).
  Near you's location answers one request and is kept nowhere, so it
  isn't collected in Apple's sense.
- **Age rating.** The questionnaire counts player posts: user-generated
  content, with reporting, blocking and moderation (Claude holds or hides
  a post; Report and Block are on every sign). The rating it gives is
  Jamie's to accept.
- **URLs.** Marketing: roadsignmath.xyz. Privacy policy:
  roadsignmath.xyz/privacy. Support needs a page with a way to reach
  Jamie; the site takes no mail in, so which page and which address is
  Jamie's call (the app's Send feedback already reaches Jamie).
- **Screenshots** at 6.9 inches (1320 by 2868), taken from a Debug build
  in a Pro Max simulator (its screenshots are that size) with the launch arguments in
  `AGENTS.md`, against `npm run dev` and its seeded signs.
- **The words**: name, subtitle (30 characters), description and
  keywords. What the listing promises is Jamie's call.
- **App Review**: the same sign-in note as the beta (any email, the code
  arrives there; "Look around first" needs none). Delete my account,
  reporting, blocking and contact are in the app, as Apple asks of an app
  where players post.
