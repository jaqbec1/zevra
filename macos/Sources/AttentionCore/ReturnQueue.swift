import Darwin
import Foundation

@MainActor
public final class ReturnQueue {
  public enum Availability: Equatable, Sendable {
    case available
    case unavailable
  }

  public enum SaveResult: Equatable, Sendable {
    case saved(String)
    case existing(String)
  }

  private struct Document: Codable {
    let version: Int
    let entries: [ReturnEntry]
  }

  private struct Undo {
    let id: UUID
    let entryID: String
    let previous: ReturnEntry?
    let expected: ReturnEntry?
  }

  private let url: URL?
  private var values: [String: ReturnEntry] = [:]
  private var undo: Undo?
  public private(set) var availability: Availability = .unavailable
  public var undoID: UUID? { undo?.id }
  public var entries: [ReturnEntry] {
    values.values.sorted {
      $0.savedAt == $1.savedAt ? $0.id < $1.id : $0.savedAt < $1.savedAt
    }
  }

  public init(url: URL?) {
    self.url = url
    reload()
  }

  public func reload() {
    do {
      let loaded = try read()
      values = loaded
      availability = .available
      undo = nil
    } catch {
      values = [:]
      availability = .unavailable
      undo = nil
    }
  }

  @discardableResult
  public func save(
    _ material: ReturnMaterial, reason: String? = nil, goal: String? = nil,
    policy: CapturePolicy, now: Date = Date()
  ) throws -> SaveResult {
    guard availability == .available else { throw ReturnQueueError.unavailable }
    let entry = try ReturnEntry(
      material: material, reason: reason, goal: goal, policy: policy, now: now)
    if values[entry.id] != nil { return .existing(entry.id) }
    try commit(id: entry.id, next: entry)
    return .saved(entry.id)
  }

  public func apply(
    _ action: ReturnAction, to id: String, policy: CapturePolicy, now: Date = Date()
  ) throws {
    guard availability == .available else { throw ReturnQueueError.unavailable }
    guard let entry = values[id] else { return }
    let next: ReturnEntry?
    switch action {
    case .letGo:
      guard entry.state != .letGo else { return }
      next = entry.changing(to: .letGo)
    case .remove:
      next = nil
    case .done, .later, .returnAgain:
      guard entry.isPermitted(by: policy) else { throw ReturnQueueError.excludedURL }
      let state: ReturnState
      switch action {
      case .done: state = .completed
      case .returnAgain: state = .active
      case .later(let until):
        guard until.timeIntervalSinceReferenceDate.isFinite, until > now else {
          throw ReturnQueueError.invalidDate
        }
        state = .deferred(until: until)
      case .letGo, .remove: return
      }
      guard state != entry.state else { return }
      next = entry.changing(to: state)
    }
    try commit(id: id, next: next)
  }

  public func canUndo(policy: CapturePolicy) -> Bool {
    guard availability == .available, let undo, values[undo.entryID] == undo.expected else {
      return false
    }
    return undo.previous?.isPermitted(by: policy) ?? true
  }

  @discardableResult
  public func undo(_ id: UUID, policy: CapturePolicy) throws -> Bool {
    guard let undo, undo.id == id, canUndo(policy: policy) else { return false }
    var next = values
    next[undo.entryID] = undo.previous
    try persist(next)
    values = next
    self.undo = nil
    return true
  }

  private func commit(id: String, next entry: ReturnEntry?) throws {
    var next = values
    next[id] = entry
    try persist(next)
    undo = Undo(id: UUID(), entryID: id, previous: values[id], expected: entry)
    values = next
  }

  private func read() throws -> [String: ReturnEntry] {
    guard let url else { return values }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      return [:]
    }
    let document = try JSONDecoder().decode(Document.self, from: data)
    guard document.version == 1 else { throw ReturnQueueError.unsupportedData }
    var result: [String: ReturnEntry] = [:]
    for entry in document.entries {
      guard entry.validStoredValue, result[entry.id] == nil else {
        throw ReturnQueueError.unsupportedData
      }
      result[entry.id] = entry
    }
    return result
  }

  private func persist(_ values: [String: ReturnEntry]) throws {
    guard let url else { return }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(
        Document(version: 1, entries: values.values.sorted { $0.id < $1.id }))
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let temporary = directory.appendingPathComponent(".return-queue-\(UUID().uuidString).tmp")
      let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
      guard descriptor >= 0 else { throw ReturnQueueError.writeFailed }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? FileManager.default.removeItem(at: temporary) }
      do {
        try handle.write(contentsOf: data)
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
      // Nothing fallible follows the atomic replacement before publishing the new value.
      guard Darwin.rename(temporary.path, url.path) == 0 else {
        throw ReturnQueueError.writeFailed
      }
    } catch {
      throw ReturnQueueError.writeFailed
    }
  }
}
