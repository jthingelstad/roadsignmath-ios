import Foundation
import Testing

@testable import RoadSignMathAPI

/// `Store.open(url)`: what a roadsignmath.xyz link opens, and what gets out
/// of its way.
@Suite struct AppLinkTests {
  func link(_ path: String) -> AppLink { AppLink(URL(string: "https://roadsignmath.xyz" + path)!) }

  @Test func aSignsPageOpensTheSign() {
    #expect(link("/signs/twin-lakes-math") == .sign("twin-lakes-math"))
    #expect(link("/signs/twin-lakes-math").homePath == ["twin-lakes-math"])
    // A trailing slash and a query don't matter.
    #expect(link("/signs/twin-lakes-math/?ref=share") == .sign("twin-lakes-math"))
  }

  @Test func aPlayersPageOpensThePlayer() {
    #expect(link("/players/jamie") == .player("jamie"))
    #expect(link("/players/jamie").homePath == ["@jamie"])
    #expect(PlayerPath.handle("@jamie") == "jamie")
    #expect(PlayerPath.handle("twin-lakes-math") == nil)
  }

  @Test func anIdLinkInAnyCaseAsksTheAPIWithTheIdAsStored() {
    let id = "01KA0Z8Q4V3Y6W2N9T5R7P1M3X"
    #expect(link("/signs/" + id.lowercased()) == .sign(id))
    #expect(link("/players/" + id.lowercased()).homePath == ["@" + id])
  }

  @Test func anythingElseOpensHomeAsItIs() {
    for path in ["/", "/map", "/signs", "/signs/", "/signs/a/b", "/players", "/about"] {
      #expect(link(path) == .home, "\(path)")
      #expect(link(path).homePath == nil)
    }
  }

  @Test func whatGetsOutOfTheWay() {
    #expect(AppLink.clearing([]) == [])
    #expect(AppLink.clearing(.sheet) == [.closeSheets])
    #expect(AppLink.clearing(.signIn) == [.closeSignIn])
    // Capture steps aside (keeping its shot), and what it presents goes with it.
    #expect(AppLink.clearing([.capture, .sheet]) == [.captureAside])
    #expect(AppLink.clearing([.capture, .signIn]) == [.captureAside, .closeSignIn])
  }
}
