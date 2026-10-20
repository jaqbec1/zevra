import Foundation
import Testing

@testable import AttentionCore

private let selectionPolicy = CapturePolicy(enabled: true)
private let selectionTime = Date(timeIntervalSince1970: 2_000_000)

@MainActor
@Test func allReturnsStayReachableWhileHomeIsBoundedAndDeferralsExpire() throws {
  let queue = ReturnQueue(url: nil)
  for index in 0..<7 {
    try queue.save(
      ReturnMaterial(title: "Material \(index)", archiveID: "\(index)"), policy: selectionPolicy,
      now: selectionTime.addingTimeInterval(Double(index)))
  }
  let id = queue.entries[0].id
  try queue.apply(
    .later(selectionTime.addingTimeInterval(100)), to: id, policy: selectionPolicy,
    now: selectionTime)
  let context = ReturnContext(archiveIDs: Set((0..<7).map(String.init)))
  let all = ReturnSelection.all(queue.entries, context: context, policy: selectionPolicy)
  #expect(all.count == 7)
  #expect(all.filter { $0.state.group(at: selectionTime) == .later }.map(\.id) == [id])
  let ready = ReturnSelection.ready(
    queue.entries, context: context, policy: selectionPolicy,
    now: selectionTime)
  #expect(ready.count == 6)
  #expect(Array(ready.prefix(3)).map(\.id) == Array(queue.entries.dropFirst().prefix(3)).map(\.id))
  #expect(
    ReturnSelection.ready(
      queue.entries, context: context, policy: selectionPolicy,
      now: selectionTime.addingTimeInterval(100)
    ).count == 7)
  #expect(queue.entries[0].state == .deferred(until: selectionTime.addingTimeInterval(100)))
}

@MainActor
@Test func savedContextRetainsEarlierGoalsAndRemovedSourcesWithoutReassignment() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(
    ReturnMaterial(title: "Parser notes", archiveID: "removed-note"), reason: "Implement a parser",
    goal: "  Build a language", policy: selectionPolicy)
  let old = ReturnContext(goalLines: ["  Build a language"], archiveIDs: ["removed-note"])
  let changed = ReturnContext(goalLines: ["Learn to draw"])
  let before = ReturnSelection.all(queue.entries, context: old, policy: selectionPolicy)
  let after = ReturnSelection.all(queue.entries, context: changed, policy: selectionPolicy)
  guard case .available(let original) = before[0], case .available(let current) = after[0] else {
    Issue.record("An allowed linkless return must remain visible")
    return
  }
  #expect(!original.earlierGoal && !original.sourceRemoved)
  #expect(current.earlierGoal && current.sourceRemoved)
  #expect(current.entry.goal == "  Build a language")
  #expect(current.entry.reason == "Implement a parser")
  #expect(ReturnContext.lines(in: "First\n\n  Second\n") == ["First", "  Second"])
}

@MainActor
@Test func exclusionsRedactAndNegativeFeedbackOnlySuppressesHomeFeaturing() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(
    ReturnMaterial(
      title: "Sensitive snapshot", rawURL: "https://example.com/article", archiveID: "a"),
    reason: "Private reason", goal: "Private goal", policy: selectionPolicy)
  try queue.save(
    ReturnMaterial(title: "Linkless account notes", archiveID: "b"),
    policy: selectionPolicy)
  let denied = CapturePolicy(enabled: true, excludedDomains: ["example.com"])
  let context = ReturnContext(negativeArchiveIDs: ["b"])
  let cards = ReturnSelection.all(queue.entries, context: context, policy: denied)
  #expect(cards.count == 2)
  #expect(cards.contains { if case .restricted = $0 { true } else { false } })
  #expect(
    ReturnSelection.ready(
      queue.entries, context: context, policy: denied,
      now: Date()
    ).isEmpty)
  #expect(queue.entries.allSatisfy { $0.state == .active })
  let noFeedback = ReturnSelection.ready(
    queue.entries, context: ReturnContext(), policy: denied,
    now: Date())
  #expect(noFeedback.map(\.entry.title) == ["Linkless account notes"])
  let negativeURL = ReturnContext(negativeURLs: ["https://example.com/article"])
  let home = ReturnSelection.ready(
    queue.entries, context: negativeURL, policy: selectionPolicy,
    now: Date())
  #expect(home.map(\.entry.title) == ["Linkless account notes"])
  #expect(queue.entries.count == 2)
}

private func eligibleEstimate(_ index: Int = 0) -> JevEstimateSnapshot {
  JevEstimateSnapshot(
    url: "https://example.com/article-\(index)", title: "Estimate \(index)",
    profileRevision: "current",
    status: .personalEvaluation, worth: 3.4, interestFit: 3, goalFit: 3, confidence: 0.7,
    basis: "Compared with your goals and rated materials")
}

@Test func estimatesAreOptionalBoundedAndDeduplicatedWithExistingEvidence() {
  let candidates = (0..<6).map(eligibleEstimate)
  let selected = ReturnSelection.estimates(
    candidates + [candidates[0]], enabled: true, profileRevision: "current", ratedURLs: [],
    entries: [], policy: selectionPolicy)
  #expect(selected.map(\.url) == candidates.prefix(3).map(\.url))
  #expect(selected[0].basis == "Compared with your goals and rated materials")
  #expect(
    ReturnSelection.estimates(
      candidates, enabled: false, profileRevision: "current",
      ratedURLs: [], entries: [], policy: selectionPolicy
    ).isEmpty)
}

@Test(arguments: [
  "stale", "uncertain", "failed", "lowConfidence", "nanConfidence", "infiniteConfidence",
  "excessConfidence", "missingConfidence", "lowWorth", "nanWorth", "infiniteWorth",
  "excessWorth", "missingWorth", "nanInterest", "missingInterest", "infiniteGoal",
  "missingGoal", "missingBasis", "excludedRawURL",
])
func ineligibleEstimatesAreFilteredAlongsideAnEligibleControl(failure: String) {
  var candidate = eligibleEstimate(1)
  switch failure {
  case "stale": candidate.profileRevision = "older"
  case "uncertain", "failed": candidate.status = .unavailable
  case "lowConfidence": candidate.confidence = 0.59
  case "nanConfidence": candidate.confidence = .nan
  case "infiniteConfidence": candidate.confidence = .infinity
  case "excessConfidence": candidate.confidence = 1.1
  case "missingConfidence": candidate.confidence = nil
  case "lowWorth": candidate.worth = 2.99
  case "nanWorth": candidate.worth = .nan
  case "infiniteWorth": candidate.worth = .infinity
  case "excessWorth": candidate.worth = 4.1
  case "missingWorth": candidate.worth = nil
  case "nanInterest": candidate.interestFit = .nan
  case "missingInterest": candidate.interestFit = nil
  case "infiniteGoal": candidate.goalFit = .infinity
  case "missingGoal": candidate.goalFit = nil
  case "missingBasis": candidate.basis = nil
  case "excludedRawURL": candidate.url = "https://example.com/article-1?utm_source=login"
  default: Issue.record("Unknown fixture")
  }
  let control = eligibleEstimate()
  let selected = ReturnSelection.estimates(
    [candidate, control], enabled: true, profileRevision: "current", ratedURLs: [], entries: [],
    policy: selectionPolicy)
  #expect(selected.map(\.url) == [control.url])
}

@MainActor
@Test func estimatesRespectHumanRatingAliasesQueuedReturnsAndCurrentRules() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(
    ReturnMaterial(title: "Queued", rawURL: eligibleEstimate(1).url),
    policy: selectionPolicy)
  let selected = ReturnSelection.estimates(
    (0..<5).map(eligibleEstimate), enabled: true, profileRevision: "current",
    ratedURLs: [eligibleEstimate(0).url + "?utm_source=archive", eligibleEstimate(2).url],
    entries: queue.entries, policy: selectionPolicy)
  #expect(selected.map(\.url) == [eligibleEstimate(3).url, eligibleEstimate(4).url])
  let denied = CapturePolicy(enabled: true, excludedDomains: ["example.com"])
  #expect(
    ReturnSelection.estimates(
      [eligibleEstimate()], enabled: true, profileRevision: "current",
      ratedURLs: [], entries: [], policy: denied
    ).isEmpty)
}

@Test func knownArchiveAndRatedVisitAliasesSuppressEstimatesWithEitherHumanRating() {
  var imported = ArchiveItem(title: "An imported alias", source: .obsidian)
  imported.url = eligibleEstimate(0).url + "?utm_source=archive#part"
  let ratedVisit = ArchiveItem(
    title: "A rated visit", source: .other, identity: eligibleEstimate(1).url)
  let profile = PersonalProfile(
    items: [imported, ratedVisit],
    ratings: [imported.id: .worthwhile, ratedVisit.id: .notWorthwhile])
  let candidates = (0..<3).map(eligibleEstimate)
  let rated = profile.ratedPageURLs(among: Set(candidates.map(\.url)), policy: selectionPolicy)
  #expect(rated == [eligibleEstimate(0).url, eligibleEstimate(1).url])
  #expect(
    profile.ratedPageURLs(
      among: Set(candidates.map(\.url)), ratedAs: .notWorthwhile,
      policy: selectionPolicy) == [eligibleEstimate(1).url])
  #expect(
    ReturnSelection.estimates(
      candidates, enabled: true, profileRevision: "current",
      ratedURLs: rated, entries: [], policy: selectionPolicy
    ).map(\.url) == [eligibleEstimate(2).url])
}
