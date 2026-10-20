import Foundation

public enum ReturnState: Codable, Equatable, Sendable {
  case active
  case deferred(until: Date)
  case completed
  case letGo

  public func group(at now: Date) -> ReturnGroup {
    switch self {
    case .active: .ready
    case .deferred(let until): until <= now ? .ready : .later
    case .completed, .letGo: .finished
    }
  }
}

public enum ReturnGroup: String, CaseIterable, Sendable {
  case ready = "Ready"
  case later = "Later"
  case finished = "Finished"
}

public struct ReturnMaterial: Identifiable, Sendable {
  public let id = UUID()
  public var title: String
  public var rawURL: String?
  public var archiveID: String?

  public init(title: String, rawURL: String? = nil, archiveID: String? = nil) {
    self.title = title
    self.rawURL = rawURL
    self.archiveID = archiveID
  }
}

public struct ReturnEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let url: String?
  public let archiveID: String?
  public let reason: String?
  public let goal: String?
  public let savedAt: Date
  public private(set) var state: ReturnState
  private var revision: UUID

  init(material: ReturnMaterial, reason: String?, goal: String?, policy: CapturePolicy, now: Date)
    throws
  {
    // Check the supplied URL before removing tracking fields or fragments.
    if let raw = material.rawURL {
      guard let accepted = policy.acceptedURL(raw) else { throw ReturnQueueError.excludedURL }
      url = accepted
      id = "url:" + accepted
    } else if let archiveID = material.archiveID, !archiveID.isEmpty {
      url = nil
      id = "archive:" + archiveID
    } else {
      throw ReturnQueueError.invalidMaterial
    }
    let title = material.title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.title = title.isEmpty ? "Untitled material" : String(title.prefix(240))
    archiveID = material.archiveID
    self.reason = Self.optionalText(reason)
    self.goal = Self.optionalText(goal, preserveWhitespace: true)
    savedAt = now
    state = .active
    revision = UUID()
  }

  public func isPermitted(by policy: CapturePolicy) -> Bool {
    url.map { policy.acceptedURL($0) != nil } ?? true
  }

  func changing(to state: ReturnState) -> ReturnEntry {
    var next = self
    next.state = state
    next.revision = UUID()
    return next
  }

  var validStoredValue: Bool {
    let identityIsValid =
      if let url { !url.isEmpty && id == "url:" + url } else if let archiveID {
        !archiveID.isEmpty && id == "archive:" + archiveID
      } else { false }
    let dateIsValid =
      if case .deferred(let until) = state { until.timeIntervalSinceReferenceDate.isFinite } else {
        true
      }
    return identityIsValid && !title.isEmpty && savedAt.timeIntervalSinceReferenceDate.isFinite
      && dateIsValid
  }

  private static func optionalText(_ value: String?, preserveWhitespace: Bool = false) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return preserveWhitespace ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum ReturnAction: Sendable {
  case later(Date)
  case done
  case letGo
  case returnAgain
  case remove
}

public enum ReturnQueueError: Error, Equatable, LocalizedError {
  case unavailable
  case excludedURL
  case invalidMaterial
  case invalidDate
  case unsupportedData
  case writeFailed

  public var errorDescription: String? {
    switch self {
    case .unavailable: "Returns are unavailable. Retry reading the queue before saving."
    case .excludedURL: "This material is unavailable under your current site rules."
    case .invalidMaterial: "This material has no stable identity. Nothing was saved."
    case .invalidDate: "Choose a date in the future."
    case .unsupportedData:
      "The saved return queue could not be read. Its original data is retained."
    case .writeFailed: "Could not save returns. Previous data is unchanged. Try again."
    }
  }
}
