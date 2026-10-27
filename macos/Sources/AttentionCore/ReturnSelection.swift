import Foundation

public struct ReturnContext: Sendable {
  public var goalLines: [String]
  public var archiveIDs: Set<String>
  public var negativeArchiveIDs: Set<String>
  public var negativeURLs: Set<String>

  public init(
    goalLines: [String] = [], archiveIDs: Set<String> = [],
    negativeArchiveIDs: Set<String> = [], negativeURLs: Set<String> = []
  ) {
    self.goalLines = goalLines
    self.archiveIDs = archiveIDs
    self.negativeArchiveIDs = negativeArchiveIDs
    self.negativeURLs = negativeURLs
  }

  public static func lines(in goals: String) -> [String] {
    goals.components(separatedBy: .newlines).filter {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}

public struct ReturnFacts: Equatable, Sendable {
  public let earlierGoal: Bool
  public let sourceRemoved: Bool
  public let negativeFeedback: Bool
}

public struct ReturnCard: Identifiable, Sendable {
  public let entry: ReturnEntry
  /// nil while the personal profile cannot be read, so the card makes no goal, source, or feedback claim.
  public let facts: ReturnFacts?
  public var id: String { entry.id }
}

public enum ReturnPresentation: Identifiable, Sendable {
  case available(ReturnCard)
  case restricted(id: String, state: ReturnState)

  public var id: String {
    switch self {
    case .available(let card): card.id
    case .restricted(let id, _): id
    }
  }

  public var state: ReturnState {
    switch self {
    case .available(let card): card.entry.state
    case .restricted(_, let state): state
    }
  }
}

public struct JevEstimateSnapshot: Identifiable, Sendable {
  public enum Status: Sendable {
    case personalEvaluation
    case unavailable
  }

  public var url: String
  public var title: String
  public var profileRevision: String
  public var status: Status
  public var worth: Double?
  public var interestFit: Double?
  public var goalFit: Double?
  public var confidence: Double?
  public var basis: String?
  public var id: String { url }

  public init(
    url: String, title: String, profileRevision: String, status: Status,
    worth: Double?, interestFit: Double?, goalFit: Double?, confidence: Double?, basis: String?
  ) {
    self.url = url
    self.title = title
    self.profileRevision = profileRevision
    self.status = status
    self.worth = worth
    self.interestFit = interestFit
    self.goalFit = goalFit
    self.confidence = confidence
    self.basis = basis
  }
}

public enum ReturnSelection {
  public static func all(
    _ entries: [ReturnEntry], context: ReturnContext?, policy: CapturePolicy
  ) -> [ReturnPresentation] {
    entries.map { entry in
      guard entry.isPermitted(by: policy) else {
        return .restricted(id: entry.id, state: entry.state)
      }
      let facts = context.map { context in
        ReturnFacts(
          earlierGoal: entry.goal.map { !context.goalLines.contains($0) } ?? false,
          sourceRemoved: entry.archiveID.map { !context.archiveIDs.contains($0) } ?? false,
          negativeFeedback: entry.archiveID.map { context.negativeArchiveIDs.contains($0) } == true
            || entry.url.map { context.negativeURLs.contains($0) } == true)
      }
      return .available(ReturnCard(entry: entry, facts: facts))
    }
  }

  public static func ready(
    _ entries: [ReturnEntry], context: ReturnContext?, policy: CapturePolicy, now: Date
  ) -> [ReturnCard] {
    all(entries, context: context, policy: policy).compactMap { presentation in
      guard case .available(let card) = presentation,
        card.entry.state.group(at: now) == .ready, card.facts?.negativeFeedback == false
      else { return nil }
      return card
    }
  }

  public static func estimates(
    _ candidates: [JevEstimateSnapshot], enabled: Bool, profileRevision: String,
    ratedURLs: Set<String>, entries: [ReturnEntry], policy: CapturePolicy
  ) -> [JevEstimateSnapshot] {
    guard enabled else { return [] }
    let rated = Set(ratedURLs.compactMap { policy.acceptedURL($0) })
    let queued = Set(entries.compactMap(\.url))
    let eligible = candidates.compactMap { candidate -> JevEstimateSnapshot? in
      guard candidate.status == .personalEvaluation,
        candidate.profileRevision == profileRevision,
        let url = policy.acceptedURL(candidate.url),
        !rated.contains(url), !queued.contains(url),
        let worth = candidate.worth, worth.isFinite, (3...4).contains(worth),
        let interest = candidate.interestFit, interest.isFinite, (0...4).contains(interest),
        let goal = candidate.goalFit, goal.isFinite, (0...4).contains(goal),
        let confidence = candidate.confidence, confidence.isFinite, (0.6...1).contains(confidence),
        let basis = candidate.basis, !basis.isEmpty
      else { return nil }
      var result = candidate
      result.url = url
      return result
    }.sorted {
      if $0.worth != $1.worth { return ($0.worth ?? 0) > ($1.worth ?? 0) }
      if $0.confidence != $1.confidence { return ($0.confidence ?? 0) > ($1.confidence ?? 0) }
      return $0.url < $1.url
    }
    var seen: Set<String> = []
    return Array(eligible.filter { seen.insert($0.url).inserted }.prefix(3))
  }
}

extension PersonalProfile {
  public func ratedPageURLs(
    among candidates: Set<String> = [], ratedAs rating: MaterialRating? = nil, policy: CapturePolicy
  ) -> Set<String> {
    func matches(_ value: MaterialRating?) -> Bool {
      guard let value else { return false }
      return rating == nil || value == rating
    }
    var result = Set(
      pageRatings.compactMap { url, value in
        matches(value) ? policy.acceptedURL(url) : nil
      })
    for item in items where matches(ratings[item.id]) {
      if let raw = item.url, let url = policy.acceptedURL(raw) { result.insert(url) }
    }
    for raw in candidates {
      guard let url = policy.acceptedURL(raw) else { continue }
      let aliases = [raw, url].map { ArchiveItem(title: "", source: .other, identity: $0).id }
      if aliases.contains(where: { matches(ratings[$0]) }) { result.insert(url) }
    }
    return result
  }
}
