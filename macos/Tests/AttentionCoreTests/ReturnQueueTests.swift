import Foundation
import Testing

@testable import AttentionCore

private let returnPolicy = CapturePolicy(enabled: true)
private let savedTime = Date(timeIntervalSince1970: 1_000_000)
private let returnMaterial = ReturnMaterial(
  title: "A useful article", rawURL: "https://example.com/article", archiveID: "note-1")

@MainActor
@Test func returnAliasesAreIdempotentAcrossSourcesAndLifecycle() throws {
  let queue = ReturnQueue(url: nil)
  let first = try queue.save(
    ReturnMaterial(
      title: "Imported article", rawURL: "https://EXAMPLE.com/article?utm_source=bookmarks#part",
      archiveID: "bookmark"),
    reason: "Use this for my parser", goal: "Build a small language", policy: returnPolicy,
    now: savedTime)
  let id = try #require(queue.entries.first?.id)
  #expect(first == .saved(id))
  let later = savedTime.addingTimeInterval(86_400)
  try queue.apply(.later(later), to: id, policy: returnPolicy, now: savedTime)
  let deferred = queue.entries
  let repeated = try queue.save(
    returnMaterial, reason: "Do not overwrite", goal: "Another goal", policy: returnPolicy)
  #expect(repeated == .existing(id))
  #expect(queue.entries == deferred)
  try queue.apply(.done, to: id, policy: returnPolicy)
  let completed = queue.entries
  try queue.save(returnMaterial, policy: returnPolicy)
  #expect(queue.entries == completed)
  try queue.apply(.returnAgain, to: id, policy: returnPolicy)
  #expect(queue.entries.first?.state == .active)
  #expect(queue.entries.first?.reason == "Use this for my parser")
  #expect(queue.entries.first?.savedAt == savedTime)
}

@MainActor
@Test func linklessReturnsUseArchiveIdentityWithoutTitleGuessing() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(ReturnMaterial(title: "Same title", archiveID: "a"), policy: returnPolicy)
  try queue.save(ReturnMaterial(title: "Same title", archiveID: "b"), policy: returnPolicy)
  try queue.save(ReturnMaterial(title: "Renamed", archiveID: "a"), policy: returnPolicy)
  #expect(queue.entries.count == 2)
  #expect(Set(queue.entries.map(\.id)) == ["archive:a", "archive:b"])
  #expect(queue.entries.allSatisfy { $0.url == nil && $0.title == "Same title" })
}

@MainActor
@Test(arguments: [
  "https://example.com/article?utm_source=account", "https://example.com/article#login",
  "https://example.com/article?token=private", "file:///tmp/note", "",
])
func rejectedSuppliedURLNeverBecomesALinklessReturn(rawURL: String) throws {
  let queue = ReturnQueue(url: nil)
  #expect(throws: ReturnQueueError.excludedURL) {
    try queue.save(
      ReturnMaterial(title: "Private", rawURL: rawURL, archiveID: "archive"), policy: returnPolicy)
  }
  #expect(queue.entries.isEmpty)
}

@MainActor
@Test func oneLevelUndoRejectsStaleTokensAndHasNoRedo() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(returnMaterial, policy: returnPolicy)
  let id = try #require(queue.entries.first?.id)
  try queue.apply(
    .later(savedTime.addingTimeInterval(500)), to: id, policy: returnPolicy, now: savedTime)
  let oldUndo = try #require(queue.undoID)
  let deferred = queue.entries
  try queue.apply(.done, to: id, policy: returnPolicy)
  #expect(try queue.undo(oldUndo, policy: returnPolicy) == false)
  let undo = try #require(queue.undoID)
  #expect(try queue.undo(undo, policy: returnPolicy))
  #expect(queue.entries == deferred)
  #expect(queue.undoID == nil)
  #expect(try queue.undo(undo, policy: returnPolicy) == false)
  try queue.apply(.letGo, to: id, policy: returnPolicy)
  #expect(queue.entries.first?.state == .letGo)
  try queue.apply(.returnAgain, to: id, policy: returnPolicy)
  #expect(queue.entries.first?.state == .active)
}

@MainActor
@Test func policyChangesBlockRestorationButAllowLettingGoAndRemoval() throws {
  let queue = ReturnQueue(url: nil)
  try queue.save(returnMaterial, policy: returnPolicy)
  let id = try #require(queue.entries.first?.id)
  let denied = CapturePolicy(enabled: true, excludedDomains: ["example.com"])
  #expect(throws: ReturnQueueError.excludedURL) {
    try queue.apply(.done, to: id, policy: denied)
  }
  try queue.apply(.letGo, to: id, policy: denied)
  let undo = try #require(queue.undoID)
  #expect(!queue.canUndo(policy: denied))
  #expect(try queue.undo(undo, policy: denied) == false)
  #expect(try queue.undo(undo, policy: returnPolicy))
  try queue.apply(.remove, to: id, policy: denied)
  let removalUndo = try #require(queue.undoID)
  #expect(queue.entries.isEmpty)
  #expect(try queue.undo(removalUndo, policy: denied) == false)
  #expect(try queue.undo(removalUndo, policy: returnPolicy))
}

@MainActor
@Test func returnQueuePersistsLifecyclePrivatelyWithoutTouchingTheProfile() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("return-queue.json")
  let queue = ReturnQueue(url: url)
  #expect(queue.availability == .available)
  #expect(queue.entries.isEmpty)
  try queue.save(returnMaterial, reason: "For my project", policy: returnPolicy, now: savedTime)
  let profileURL = directory.appendingPathComponent("personal-profile.json")
  let profileBytes = Data("profile stays separate".utf8)
  try profileBytes.write(to: profileURL)
  let id = try #require(queue.entries.first?.id)
  try queue.apply(
    .later(savedTime.addingTimeInterval(500)), to: id, policy: returnPolicy, now: savedTime)
  let reopened = ReturnQueue(url: url)
  #expect(reopened.availability == .available)
  #expect(reopened.entries == queue.entries)
  #expect(reopened.undoID == nil)
  #expect(try Data(contentsOf: profileURL) == profileBytes)
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
      == ["personal-profile.json", "return-queue.json"])
}

@MainActor
@Test(arguments: ["not json", "{\"version\":2,\"entries\":[]}", "{\"version\":1,\"entries\":[{}]}"])
func unreadableReturnQueueFailsClosedAndPreservesOriginalBytes(contents: String) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("return-queue.json")
  let original = Data(contents.utf8)
  try original.write(to: url)
  let queue = ReturnQueue(url: url)
  #expect(queue.availability == .unavailable)
  #expect(throws: ReturnQueueError.unavailable) {
    try queue.save(returnMaterial, policy: returnPolicy)
  }
  #expect(try Data(contentsOf: url) == original)
  try Data("{\"version\":1,\"entries\":[]}".utf8).write(to: url)
  queue.reload()
  #expect(queue.availability == .available)
  try queue.save(returnMaterial, policy: returnPolicy)
  #expect(queue.entries.count == 1)
}

@MainActor
@Test func readErrorsAreUnavailableAndFailedWritesKeepPublishedStateAndUndo() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  #expect(ReturnQueue(url: directory).availability == .unavailable)
  let url = directory.appendingPathComponent("return-queue.json")
  let queue = ReturnQueue(url: url)
  try queue.save(returnMaterial, policy: returnPolicy)
  let original = queue.entries
  let undo = queue.undoID
  let bytes = try Data(contentsOf: url)
  try FileManager.default.removeItem(at: url)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  let sentinel = url.appendingPathComponent("original")
  try bytes.write(to: sentinel)
  #expect(throws: ReturnQueueError.writeFailed) {
    try queue.apply(.done, to: original[0].id, policy: returnPolicy)
  }
  #expect(queue.entries == original)
  #expect(queue.undoID == undo)
  #expect(try Data(contentsOf: sentinel) == bytes)
  #expect(throws: ReturnQueueError.writeFailed) {
    try queue.save(ReturnMaterial(title: "Draft", archiveID: "draft"), policy: returnPolicy)
  }
  #expect(queue.entries == original)
}

@MainActor
@Test(arguments: [ReturnAction.done, ReturnAction.letGo])
func finishedReturnsSurviveReopeningAndRequireExplicitReactivation(action: ReturnAction) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("return-queue.json")
  let queue = ReturnQueue(url: url)
  try queue.save(returnMaterial, policy: returnPolicy)
  let id = try #require(queue.entries.first?.id)
  try queue.apply(action, to: id, policy: returnPolicy)
  let finished = queue.entries
  let bytes = try Data(contentsOf: url)
  try queue.save(returnMaterial, reason: "Duplicate", policy: returnPolicy)
  #expect(try Data(contentsOf: url) == bytes)
  #expect(throws: ReturnQueueError.finishedEntry) {
    try queue.apply(
      .later(savedTime.addingTimeInterval(100)), to: id, policy: returnPolicy,
      now: savedTime)
  }
  let reopened = ReturnQueue(url: url)
  #expect(reopened.entries == finished)
  #expect(reopened.entries[0].state.group(at: Date()) == .finished)
  try reopened.apply(.returnAgain, to: id, policy: returnPolicy)
  #expect(reopened.entries[0].state == .active)
}

@MainActor
@Test func duplicateOrInvalidStoredIdentityFailsClosedWithoutSalvagingPromises() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("return-queue.json")
  let queue = ReturnQueue(url: url)
  try queue.save(returnMaterial, policy: returnPolicy)
  let bytes = try Data(contentsOf: url)
  var document = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  let entries = try #require(document["entries"] as? [[String: Any]])
  document["entries"] = entries + entries
  let duplicated = try JSONSerialization.data(withJSONObject: document)
  try duplicated.write(to: url)
  #expect(ReturnQueue(url: url).availability == .unavailable)
  #expect(try Data(contentsOf: url) == duplicated)
  var invalidEntry = entries[0]
  invalidEntry["id"] = "archive:wrong-identity"
  document["entries"] = [invalidEntry]
  let invalid = try JSONSerialization.data(withJSONObject: document)
  try invalid.write(to: url)
  #expect(ReturnQueue(url: url).availability == .unavailable)
  #expect(try Data(contentsOf: url) == invalid)
}
