import Foundation

public enum FollowUp: String, CaseIterable, Codable, Identifiable {
  case read = "Read deeper"
  case keep = "Keep as reference"
  case none = "No obvious follow-up"

  public var id: String { rawValue }
}

public struct ClassificationRecord: Codable, Equatable {
  public var title: String
  public var fingerprint: String?
  public var suggestion: FollowUp?
  public var confidence: Double?
  public var correction: FollowUp?
  public var status: String
  public var checkedAt: Date
  public var attemptCount: Int
  public var suggestedAt: Date?
  public var correctedAt: Date?

  public init(
    title: String, fingerprint: String?, suggestion: FollowUp?, confidence: Double?,
    correction: FollowUp?, status: String, checkedAt: Date, attemptCount: Int,
    suggestedAt: Date? = nil, correctedAt: Date? = nil
  ) {
    self.title = title
    self.fingerprint = fingerprint
    self.suggestion = suggestion
    self.confidence = confidence
    self.correction = correction
    self.status = status
    self.checkedAt = checkedAt
    self.attemptCount = attemptCount
    self.suggestedAt = suggestedAt
    self.correctedAt = correctedAt
  }

  public var displayedChoice: FollowUp? { correction ?? suggestion }
}

@MainActor
public final class ClassificationStore {
  private let url: URL?
  private let observations: ObservationStore
  private var policy: CapturePolicy
  public private(set) var records: [String: ClassificationRecord]
  public private(set) var syncPending = false

  public init(url: URL?, observations: ObservationStore, policy: CapturePolicy) throws {
    self.url = url
    self.observations = observations
    self.policy = policy
    if let url, FileManager.default.fileExists(atPath: url.path) {
      records = try JSONDecoder().decode(
        [String: ClassificationRecord].self, from: Data(contentsOf: url))
    } else {
      records = [:]
    }
    try refreshFromCloud()
  }

  public func record(for url: String) -> ClassificationRecord? { records[url] }

  public func setPolicy(_ policy: CapturePolicy) throws {
    self.policy = policy
    try seedLegacyRecords()
    syncPending = false
  }

  public func update(_ record: ClassificationRecord, for pageURL: String) throws {
    let previous = records[pageURL]
    let suggestionChanged =
      previous?.title != record.title
      || previous?.fingerprint != record.fingerprint
      || previous?.suggestion != record.suggestion
      || previous?.confidence != record.confidence
    let correctionChanged = previous?.correction != record.correction
    var record = record
    record.suggestedAt = suggestionChanged ? Date() : previous?.suggestedAt
    record.correctedAt = correctionChanged ? Date() : previous?.correctedAt
    var updated = records
    updated[pageURL] = record
    try persist(updated)
    records = updated
    do {
      if suggestionChanged, record.suggestion != nil, policy.acceptedURL(pageURL) == pageURL {
        try upload(record, for: pageURL, kind: .suggestion, at: record.suggestedAt!)
      }
      if correctionChanged, record.correction != nil, policy.acceptedURL(pageURL) == pageURL {
        try upload(record, for: pageURL, kind: .correction, at: record.correctedAt!)
      }
      if syncPending { try seedLegacyRecords() }
      syncPending = false
    } catch {
      // The local choice is durable; a later refresh or launch retries the missing snapshot.
      syncPending = true
    }
  }

  public func refreshFromCloud() throws {
    let snapshots = try observations.classificationSnapshots()
    var merged = records
    for snapshot in snapshots {
      guard
        let incoming = try? JSONDecoder().decode(ClassificationRecord.self, from: snapshot.payload)
      else { continue }
      var current = merged[snapshot.pageURL] ?? incoming
      switch snapshot.kind {
      case .suggestion:
        if snapshot.recordedAt >= (current.suggestedAt ?? current.checkedAt) {
          current.title = incoming.title
          current.fingerprint = incoming.fingerprint
          current.suggestion = incoming.suggestion
          current.confidence = incoming.confidence
          current.status = incoming.status
          current.suggestedAt = snapshot.recordedAt
        }
      case .correction:
        let previousCorrection =
          current.correction == nil ? Date.distantPast : current.correctedAt ?? current.checkedAt
        if snapshot.recordedAt >= previousCorrection {
          current.correction = incoming.correction
          current.correctedAt = snapshot.recordedAt
        }
      }
      merged[snapshot.pageURL] = current
    }
    if merged != records {
      try persist(merged)
      records = merged
    }
    try seedLegacyRecords(snapshots: snapshots)
    syncPending = false
  }

  private func seedLegacyRecords(
    snapshots provided: [ObservationStore.ClassificationSnapshot]? = nil
  )
    throws
  {
    let snapshots = try provided ?? observations.classificationSnapshots()
    var latestSuggestion: [String: Date] = [:]
    var latestCorrection: [String: Date] = [:]
    for snapshot in snapshots {
      switch snapshot.kind {
      case .suggestion:
        latestSuggestion[snapshot.pageURL] = max(
          latestSuggestion[snapshot.pageURL] ?? .distantPast, snapshot.recordedAt)
      case .correction:
        latestCorrection[snapshot.pageURL] = max(
          latestCorrection[snapshot.pageURL] ?? .distantPast, snapshot.recordedAt)
      }
    }
    for (pageURL, record) in records {
      guard policy.acceptedURL(pageURL) == pageURL else { continue }
      let suggestionDate = record.suggestedAt ?? record.checkedAt
      let correctionDate = record.correctedAt ?? record.checkedAt
      if record.suggestion != nil,
        (latestSuggestion[pageURL] ?? .distantPast) < suggestionDate
      {
        try upload(record, for: pageURL, kind: .suggestion, at: suggestionDate)
      }
      if record.correction != nil,
        (latestCorrection[pageURL] ?? .distantPast) < correctionDate
      {
        try upload(record, for: pageURL, kind: .correction, at: correctionDate)
      }
    }
  }

  private func upload(
    _ record: ClassificationRecord, for pageURL: String,
    kind: ObservationStore.ClassificationSnapshotKind, at date: Date
  )
    throws
  {
    try observations.saveClassificationSnapshot(
      pageURL: pageURL, kind: kind, payload: JSONEncoder().encode(record), recordedAt: date)
  }

  private func persist(_ updated: [String: ClassificationRecord]) throws {
    guard let url else { return }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(updated).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

}
