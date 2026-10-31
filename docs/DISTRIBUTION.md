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
from Apple. The version is the day's (`scripts/version.sh`); the build
number is the commit count, so a commit uploads once. Each build gets
[a pass on a real phone](PHONE-TEST.md).

## 2. The public beta

The website will link a public TestFlight invite with the app's story
(Jamie, 30 October 2026). Apple calls these external testers. It takes:

- **A build that isn't internal only.** `scripts/testflight.sh --external`
  leaves `testFlightInternalTestingOnly` out. The commit needs its own
  upload: one already uploaded internal only has used its build number.
- **Test information** under TestFlight in App Store Connect: a Beta App
  Description, a feedback email, a contact and a privacy policy URL.
- **A sign-in for Apple's reviewers.** Sign-in sends a code by email,
  which a reviewer can't receive, so review needs a way in that doesn't:
  a demo account Apple can use that never expires. How is Jamie's call
  before the first review.
- **Review.** The first external build gets a full Beta App Review, about
  a day. A build stays installable for 90 days.
- **A public group** with its link, and how many testers it takes.

## 3. The App Store

Later, on Jamie's go: the listing, screenshots, the privacy details
(email for sign-in; photos, places and names posted publicly), age
rating, and App Review. Delete my account is already in the app, as
Apple requires.
