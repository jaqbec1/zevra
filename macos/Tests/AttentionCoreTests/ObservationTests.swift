import Foundation
import Testing

@testable import AttentionCore

@Test @MainActor func browsingSearchesOlderMaterialsAndFiltersBeforeLimiting() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ObservationStore(url: directory.appendingPathComponent("browse.sqlite"))
  defer { try? store.close() }
  let now = Date()
  for index in 0..<310 {
    let blocked = index < 205
    try store.save(
      Observation(
        id: UUID(), deviceID: "synthetic-mac",
        url: "https://\(blocked ? "excluded.example.com" : "example.org")/material/\(index)",
        title: index == 309 ? "Café: a video worth revisiting" : "Material \(index)",
        startedAt: now.addingTimeInterval(-Double(index + 1)),
        lastSeenAt: now.addingTimeInterval(-Double(index)), activeSeconds: 10))
  }
  let policy = CapturePolicy(enabled: true, excludedDomains: ["excluded.example.com"])
  let first = try store.recent(limit: 101, policy: policy)
  #expect(first.count == 101)
  #expect(first.first?.url == "https://example.org/material/205")
  #expect(first.last?.url == "https://example.org/material/305")
  #expect(try store.recent(limit: 201, policy: policy).count == 105)
  #expect(
    try store.recent(limit: 100, search: "  CAFE  ", policy: policy).first?.title
      == "Café: a video worth revisiting")
  #expect(try store.recent(search: "/material/309", policy: policy).count == 1)
  #expect(try store.recent(search: "excluded.example.com", policy: policy).isEmpty)
  #expect(try store.recent(search: "no such material", policy: policy).isEmpty)
  #expect(try store.recent(limit: 0, policy: policy).isEmpty)
}

@Test @MainActor func unavailableStorageFailsWithoutReplacingExistingData() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let blocker = directory.appendingPathComponent("existing-file")
  let original = Data("synthetic data that must survive".utf8)
  try original.write(to: blocker)
  #expect(throws: CocoaError.self) {
    _ = try ObservationStore(url: blocker.appendingPathComponent("store.sqlite"))
  }
  #expect(try Data(contentsOf: blocker) == original)
}

@Test func policyDefaultsToNoCollection() {
  #expect(CapturePolicy().acceptedURL("https://example.com/article") == nil)
  #expect(
    CapturePolicy(allowedDomains: ["example.com"]).acceptedURL("https://example.com/article") == nil
  )
}

@Test func exclusionsRunBeforeNormalization() {
  let policy = CapturePolicy(
    enabled: true, allowedDomains: ["example.com", "gmail.com", "127.0.0.1"])
  #expect(
    policy.acceptedURL("https://EXAMPLE.com/a?utm_source=x&b=2&a=1#section")
      == "https://example.com/a?a=1&b=2")
  for url in [
    "https://elsewhere.com", "https://notexample.com", "https://gmail.com/",
    "http://127.0.0.1/", "https://user:pass@example.com", "file:///tmp/a",
    "https://example.com:8443/", "https://example.com?access_token=x",
    "https://example.com#token=x", "https://example.com/%2561ccount",
    "https://example.com/%6cogin", "https://example.com/settings",
    "https://example.com/?%74oken=x", "https://example.com/%ZZ",
  ] {
    #expect(policy.acceptedURL(url) == nil, "Rejected synthetic URL: \(url)")
  }
}

@Test func emptyAllowedListUsesExclusionsWhileExplicitListsRestrictCapture() {
  let policy = CapturePolicy(enabled: true, excludedDomains: ["private.example.com"])
  #expect(policy.acceptedURL("https://example.com/article") != nil)
  #expect(policy.acceptedURL("https://another.org/article") != nil)
  for url in [
    "https://private.example.com/a", "https://nested.private.example.com/a",
    "https://gmail.com/", "http://127.0.0.1/", "https://example.com/account",
    "https://example.com/?token=secret",
  ] {
    #expect(policy.acceptedURL(url) == nil)
  }
  let restricted = CapturePolicy(
    enabled: true, allowedDomains: ["example.com"], excludedDomains: ["private.example.com"])
  #expect(restricted.acceptedURL("https://blog.example.com/a") != nil)
  #expect(restricted.acceptedURL("https://another.org/a") == nil)
  #expect(restricted.acceptedURL("https://private.example.com/a") == nil)
}

@Test func domainListsAcceptCommasWhitespaceAndReportInvalidEntries() {
  #expect(
    CapturePolicy.domains(from: "EXAMPLE.com, wikipedia.org,\n blog.example.net") == [
      "example.com", "wikipedia.org", "blog.example.net",
    ])
  #expect(
    CapturePolicy.invalidDomains(from: "example.com, https://example.org, *.example.net") == [
      "https://example.org", "*.example.net",
    ])
  #expect(CapturePolicy.invalidDomains(from: " , \n").isEmpty)
}

@Test func trackerExcludesSwitchesIdleAndSleep() {
  var tracker = AttentionTracker(deviceID: "test-device")
  let page = PageIdentity(url: "https://example.com/a", title: "Synthetic article")
  #expect(tracker.sample(page, uptime: 10, date: .distantPast) == nil)
  let checkpoint = tracker.sample(page, uptime: 12, date: .distantPast)
  #expect(checkpoint?.activeSeconds == 2)
  #expect(tracker.sample(nil, uptime: 14, date: .distantPast) == nil)
  #expect(tracker.sample(page, uptime: 16, date: .distantPast) == nil)
  let resumed = tracker.sample(page, uptime: 18, date: .distantPast)
  #expect(resumed?.activeSeconds == 2)
  #expect(resumed?.id != checkpoint?.id)
  #expect(tracker.sample(page, uptime: 100, date: .distantPast) == nil)
  #expect(tracker.sample(page, uptime: 102, date: .distantPast)?.activeSeconds == 2)
  tracker.reset()
  #expect(tracker.sample(page, uptime: 104, date: .distantPast) == nil)
}

@Test @MainActor func persistenceIsIdempotentAndSurvivesReopening() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("test.sqlite")
  let original = Observation(
    id: UUID(), deviceID: "synthetic-mac", url: "https://example.com/a", title: "Fixture",
    startedAt: .distantPast, lastSeenAt: Date(), activeSeconds: 4)
  do {
    let store = try ObservationStore(url: url)
    try store.save(original)
    try store.save(original)
    var newer = original
    newer.activeSeconds = 8
    try store.save(newer)
    try store.save(original)
    #expect(try store.recent().count == 1)
    #expect(try store.recent().first?.activeSeconds == 8)
    try store.close()
  }
  let reopened = try ObservationStore(url: url)
  #expect(try reopened.recent().first?.id == original.id)
  #expect(try reopened.recent().first?.activeSeconds == 8)
  try reopened.close()
}

@Test func wakingDisplayDoesNotReactivateAnotherUsersSession() {
  var activity = ActivityGate()
  #expect(activity.permitsCapture(idleSeconds: 0))
  #expect(!activity.permitsCapture(idleSeconds: 60))
  #expect(!activity.permitsCapture(idleSeconds: .infinity))
  activity.sessionActive = false
  activity.screenAwake = false
  activity.screenAwake = true
  #expect(!activity.permitsCapture(idleSeconds: 0))
  activity.sessionActive = true
  activity.awake = false
  #expect(!activity.permitsCapture(idleSeconds: 0))
}

@Test @MainActor func policyTrackerAndStorePreserveIndependentDeviceVisits() throws {
  let store = try ObservationStore(url: nil)
  let policy = CapturePolicy(enabled: true, allowedDomains: ["example.com"])
  for device in ["mac-one", "mac-two"] {
    var tracker = AttentionTracker(deviceID: device)
    for (time, raw) in [
      (0.0, "https://example.com/article"), (2.0, "https://example.com/article"),
      (4.0, "https://example.com/account"), (6.0, "https://example.com/article"),
    ] {
      let page = policy.acceptedURL(raw).map { PageIdentity(url: $0, title: "Synthetic page") }
      if let observation = tracker.sample(page, uptime: time, date: Date()) {
        try store.save(observation)
        try store.save(observation)
      }
    }
  }
  let records = try store.recent()
  #expect(records.count == 2)
  #expect(Set(records.map(\.deviceID)) == ["mac-one", "mac-two"])
  #expect(records.reduce(0) { $0 + $1.activeSeconds } == 4)
  #expect(records.allSatisfy { $0.url == "https://example.com/article" })
  try store.close()
}
