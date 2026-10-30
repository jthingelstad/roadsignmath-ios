import Foundation
import SignReading
import SignReadingEval

/// report.md: the tables.
enum Report {
  static func markdown(results: [VariantResult], best: VariantResult, signs: [EvalSign]) -> String {
    var out = "# Number-reading spike results\n\n"
    out += "Best variant (most new-era full hits, then recall): **\(best.label)**. "
    if let shipping = results.first(where: \.isShipping) {
      out += "The app's configuration (`SignReader.photo`) is \(shipping.label), marked †.\n\n"
    } else {
      out += "\n\n"
    }
    out += "Recall is the share of the numbers a player used that were read; a full hit reads all of them. "
    out += "Extras are numbers read that the player didn't use. Seconds are per image on a Mac, "
    out += "a proxy for the phone.\n\n"

    out += "## New-era signs (micro.blog, 2021-2025)\n\n"
    out += table(results, best: best) { $0.newEra }
    out += "\n## Archive signs (2005-2014)\n\n"
    out += "The archive lists only the numbers the old rules allowed (distances, not road numbers), "
    out += "so extras here are mostly real numbers on the sign, not misreads.\n\n"
    out += table(results, best: best) { $0.archive }

    let newEra = best.signs.filter { $0.era == .newEra }
    if !newEra.isEmpty {
      out += "\n## New-era signs, one by one (\(best.label))\n\n"
      out += "| Sign | Expected | Read | Missed | Recall |\n| --- | --- | --- | --- | --- |\n"
      for sign in newEra {
        out += "| \(sign.title) | \(list(sign.expected)) | \(list(sign.read)) | \(list(missed(sign))) | "
        out += "\(sign.hits)/\(sign.expected.count) |\n"
      }
    }
    return out
  }

  static func table(_ results: [VariantResult], best: VariantResult, _ pick: (VariantResult) -> ScoreSummary)
    -> String
  {
    var out = "| Variant | Signs | Full hits | Full hits % | Mean recall | Extras | s / image |\n"
    out += "| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n"
    for result in results {
      let summary = pick(result)
      var name = result.key == best.key ? "**\(result.label)**" : result.label
      if result.isShipping { name += " †" }
      out += "| \(name) | \(summary.signs) | \(summary.fullHits) | \(percent(summary.fullHitShare)) | "
      out += "\(percent(summary.meanRecall)) | \(summary.extras) | "
      out += String(format: "%.2f", summary.meanSecondsPerImage) + " |\n"
    }
    return out
  }

  static func missed(_ sign: SignResult) -> [Decimal] {
    var left = Multiset(sign.read)
    return sign.expected.filter { !left.remove($0) }
  }

  static func list(_ values: [Decimal]) -> String {
    values.isEmpty ? "-" : values.map { "\($0)" }.joined(separator: ", ")
  }

  static func percent(_ share: Double) -> String {
    String(format: "%.0f%%", share * 100)
  }
}
