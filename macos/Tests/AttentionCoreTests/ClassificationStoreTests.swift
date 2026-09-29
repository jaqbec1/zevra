import CoreData
import Foundation
import Testing

@testable import AttentionCore

private func fixture(
  suggestion: FollowUp? = .read, correction: FollowUp? = nil, checkedAt: Date = Date()
) -> ClassificationRecord {
  ClassificationRecord(
    title: "Synthetic article", fingerprint: "fixture", suggestion: suggestion,
    confidence: suggestion == nil ? nil : 0.8, correction: correction,
    status: "Jev suggestion", checkedAt: checkedAt, attemptCount: 0)
}

@Test @MainActor func classificationChangesMergeAcrossLocalStoresAndKeepHumanChoice() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let observations = try ObservationStore(url: directory.appendingPathComponent("visits.sqlite"))
  defer { try? observations.close() }
  let policy = CapturePolicy(enabled: true, allowedDomains: ["example.com"])
  let pageURL = "https://example.com/article"
  let first = try ClassificationStore(
    url: directory.appendingPathComponent("first.json"), observations: observations, policy: policy)
  let second = try ClassificationStore(
    url: directory.appendingPathComponent("second.json"), observations: observations, policy: policy
  )

  try first.update(fixture(), for: pageURL)
  try second.refreshFromCloud()
  #expect(second.record(for: pageURL)?.suggestion == .read)
  #expect(second.record(for: pageURL)?.correction == nil)

  var humanChoice = second.record(for: pageURL)!
  humanChoice.correction = .keep
  try second.update(humanChoice, for: pageURL)
  try first.refreshFromCloud()
  #expect(first.record(for: pageURL)?.displayedChoice == .keep)

  var newerSuggestion = first.record(for: pageURL)!
  newerSuggestion.suggestion = FollowUp.none
  try first.update(newerSuggestion, for: pageURL)
  try second.refreshFromCloud()
  #expect(second.record(for: pageURL)?.suggestion == FollowUp.none)
  #expect(second.record(for: pageURL)?.displayedChoice == .keep)
  #expect(try observations.classificationSnapshots().count == 3)
}

@Test @MainActor func legacyClassificationsMigrateOnceAndRespectCurrentRules() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let observations = try ObservationStore(url: directory.appendingPathComponent("visits.sqlite"))
  defer { try? observations.close() }
  let pageURL = "https://example.com/article"
  let legacyURL = directory.appendingPathComponent("classifications.json")
  try JSONEncoder().encode([pageURL: fixture(correction: .keep)]).write(to: legacyURL)
  let excluded = CapturePolicy(enabled: true, excludedDomains: ["example.com"])
  let classifications = try ClassificationStore(
    url: legacyURL, observations: observations, policy: excluded)
  #expect(try observations.classificationSnapshots().isEmpty)
  #expect(classifications.record(for: pageURL)?.correction == .keep)

  try classifications.setPolicy(CapturePolicy(enabled: true, allowedDomains: ["example.com"]))
  #expect(try observations.classificationSnapshots().count == 2)
  _ = try ClassificationStore(
    url: legacyURL, observations: observations,
    policy: CapturePolicy(enabled: true, allowedDomains: ["example.com"]))
  #expect(try observations.classificationSnapshots().count == 2)
}

@Test @MainActor func existingObservationStoreMigratesWithoutLosingVisits() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appendingPathComponent("existing.sqlite")
  let model = NSManagedObjectModel()
  let observation = NSEntityDescription()
  observation.name = "Observation"
  observation.managedObjectClassName = "NSManagedObject"
  observation.properties = [
    ("id", NSAttributeType.UUIDAttributeType), ("deviceID", .stringAttributeType),
    ("url", .stringAttributeType), ("title", .stringAttributeType),
    ("startedAt", .dateAttributeType), ("lastSeenAt", .dateAttributeType),
    ("activeSeconds", .doubleAttributeType),
  ].map { name, type in
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.attributeType = type
    attribute.isOptional = true
    return attribute
  }
  model.entities = [observation]
  let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
  let oldStore = try coordinator.addPersistentStore(type: .sqlite, at: url)
  let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
  context.persistentStoreCoordinator = coordinator
  let object = NSEntityDescription.insertNewObject(forEntityName: "Observation", into: context)
  let visitID = UUID()
  object.setValue(visitID, forKey: "id")
  object.setValue("old-mac", forKey: "deviceID")
  object.setValue("https://example.com/old", forKey: "url")
  object.setValue("Existing visit", forKey: "title")
  object.setValue(Date(), forKey: "startedAt")
  object.setValue(Date(), forKey: "lastSeenAt")
  object.setValue(5.0, forKey: "activeSeconds")
  try context.save()
  context.reset()
  try coordinator.remove(oldStore)

  let upgraded = try ObservationStore(url: url)
  defer { try? upgraded.close() }
  #expect(try upgraded.recent().first?.id == visitID)
  try upgraded.saveClassificationSnapshot(
    pageURL: "https://example.com/old", kind: .correction, payload: Data("test".utf8),
    recordedAt: Date())
  #expect(try upgraded.classificationSnapshots().count == 1)
}
