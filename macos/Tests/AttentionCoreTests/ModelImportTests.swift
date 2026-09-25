import Foundation
import Testing

@testable import AttentionCore

@Test func modelImportRequiresReviewAndPreservesExistingRatings() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  var profile = PersonalProfile(
    goals: "Finish my project", items: [item], ratings: [item.id: .worthwhile])
  let revision = profile.revision
  var draft = try ModelImport.decode(response: response(for: item), candidates: [item])
  #expect(profile.revision == revision)
  #expect(draft.interests.allSatisfy { !$0.selected })
  #expect(draft.intentions.allSatisfy { !$0.selected })
  draft.interests[0].selected = true
  draft.intentions[0].selected = true
  profile = try draft.applying(to: profile)
  #expect(profile.ratings[item.id] == .worthwhile)
  #expect(profile.items.count == 1)
  #expect(profile.items.first?.topic == "Compilers")
  #expect(profile.interests == ["Compilers"])
  #expect(profile.goals == "Finish my project\nLearn compiler design")
  #expect(!profile.evaluationEnabled)
}

@Test func modelRequestContainsOnlyChosenCandidatesAndNoTools() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  let omitted = ArchiveItem(title: "Do not send this title", source: .books)
  var draft = ImportDraft(candidates: [item, omitted])
  draft.materials[0].link = "https://example.com/compilers"
  draft.materials[0].topic = "Local draft topic"
  draft.materials[1].selected = false
  let request = try ModelImport.request(
    candidates: draft.selectedMaterials(), apiKey: "synthetic-key")
  let bodyData = try #require(request.httpBody)
  let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
  #expect(body["store"] as? Bool == false)
  #expect(body["tools"] == nil)
  #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
  let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
  #expect(format["strict"] as? Bool == true)
  #expect(format["type"] as? String == "json_schema")
  let messages = try #require(body["input"] as? [[String: String]])
  let content = try #require(messages.first?["content"])
  let sources = try #require(
    JSONSerialization.jsonObject(with: Data(content.utf8)) as? [[String: String]])
  #expect(
    sources == [
      [
        "source_id": item.id, "title": item.title, "source": "Obsidian",
        "link": "https://example.com/compilers",
      ]
    ])
}

@Test(arguments: ["incomplete", "failed", "cancelled"])
func incompleteModelResponseNeverBecomesAnImport(status: String) throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  #expect(throws: ModelImport.Failure.self) {
    try ModelImport.decode(response: response(for: item, status: status), candidates: [item])
  }
}

@Test func modelCannotInventSourceIdentityOrDropMaterials() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  let other = ArchiveItem(title: "A different source", source: .books)
  #expect(throws: ModelImport.Failure.self) {
    try ModelImport.decode(response: response(for: other), candidates: [item])
  }
  #expect(throws: ModelImport.Failure.self) {
    try ModelImport.decode(response: response(for: item), candidates: [item, other])
  }
}

@Test func importDraftHonorsEditsAndDeselection() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  var draft = ImportDraft(candidates: [item])
  draft.materials[0].title = "Edited title"
  draft.materials[0].topic = "Parsing"
  draft.materials[0].link = "https://example.com/compilers"
  let profile = try draft.applying(to: PersonalProfile())
  #expect(profile.items.first?.title == "Edited title")
  #expect(profile.items.first?.url == "https://example.com/compilers")
  #expect(profile.items.first?.topic == "Parsing")
  #expect(profile.ratings.isEmpty)
  draft.materials[0].selected = false
  #expect(try draft.applying(to: PersonalProfile()).items.isEmpty)
}

@Test func legacyArchiveItemsRemainReadable() throws {
  let item = try JSONDecoder().decode(
    ArchiveItem.self,
    from: Data(#"{"id":"old-id","title":"Old material","source":"Obsidian"}"#.utf8))
  #expect(item.id == "old-id")
  #expect(item.url == nil)
  #expect(item.topic == nil)
}

@Test(arguments: ["", "   "])
func modelMayLeaveAnUncertainTopicEmpty(topic: String) throws {
  let item = ArchiveItem(title: "Untitled material", source: .obsidian)
  let draft = try ModelImport.decode(
    response: response(for: item, topic: topic), candidates: [item])
  #expect(draft.materials.first?.topic == "")
  #expect(try draft.applying(to: PersonalProfile()).items.first?.topic == nil)
}

private func response(
  for item: ArchiveItem, status: String = "completed", topic: String = "Compilers"
)
  throws -> Data
{
  let payload: [String: Any] = [
    "materials": [["source_id": item.id, "title": item.title, "topic": topic]],
    "interests": [["text": "Compilers", "source_ids": [item.id]]],
    "intentions": [["text": "Learn compiler design", "source_ids": [item.id]]],
  ]
  let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
  return try JSONSerialization.data(withJSONObject: [
    "status": status,
    "output": [
      ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]
    ],
  ])
}

@Test func modelTransportRunsThroughURLSessionWithoutNetwork() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [ImportResponseStub.self]
  let session = URLSession(configuration: config)
  defer { session.invalidateAndCancel() }
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  let draft = try await ModelImport.analyze(
    candidates: [item], apiKey: "synthetic-key", session: session)
  #expect(draft.modelGenerated)
  #expect(draft.materials.first?.topic == "Compilers")
  #expect(draft.intentions.first?.text == "Learn compiler design")
}

@Test(arguments: [401, 429, 500])
func modelHTTPFailuresDoNotReturnDraft(status: Int) async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [ImportResponseStub.self]
  config.httpAdditionalHeaders = ["X-Test-Status": String(status)]
  let session = URLSession(configuration: config)
  defer { session.invalidateAndCancel() }
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  await #expect(throws: ModelImport.Failure.self) {
    try await ModelImport.analyze(candidates: [item], apiKey: "synthetic-key", session: session)
  }
}

@Test func rejectedOrInvalidResultsCannotChangeProfile() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  let refusal = Data(
    #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
  #expect(throws: ModelImport.Failure.self) {
    try ModelImport.decode(response: refusal, candidates: [item])
  }
  var draft = ImportDraft(candidates: [item])
  draft.materials[0].link = "javascript:alert(1)"
  let profile = PersonalProfile(goals: "Existing goal")
  #expect(throws: ModelImport.Failure.self) { try draft.applying(to: profile) }
  #expect(profile.goals == "Existing goal")
  #expect(profile.items.isEmpty)
}

@Test func importRulesApplyBeforeSendingAndSaving() throws {
  let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
  var draft = ImportDraft(candidates: [item])
  draft.materials[0].link = "https://example.com/compilers"
  var policy = CapturePolicy(excludedDomains: ["example.com"])
  policy.enabled = true
  #expect(throws: ModelImport.Failure.self) { try draft.selectedMaterials(policy: policy) }
  #expect(throws: ModelImport.Failure.self) {
    try draft.applying(to: PersonalProfile(), policy: policy)
  }
  policy.excludedDomains = []
  draft.materials[0].link =
    "https://example.com/compilers?utm_source=private&chapter=2#personal-note"
  let selected = try draft.selectedMaterials(policy: policy)
  let saved = try draft.applying(to: PersonalProfile(), policy: policy)
  #expect(selected.first?.url == "https://example.com/compilers?chapter=2")
  #expect(saved.items.first?.url == selected.first?.url)
}

@Test func archiveImportRetainsSuppliedLinks() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try #"[{"title":"A compiler talk","titleUrl":"https://example.com/talk"}]"#.write(
    to: root.appendingPathComponent("youtube-watch-history.json"), atomically: true, encoding: .utf8
  )
  try #"<a href="https://example.com/article?a=1&amp;b=2">An interesting article</a>"#.write(
    to: root.appendingPathComponent("bookmarks.html"), atomically: true, encoding: .utf8)
  try "---\nurl: https://example.com/notes\n---\n# Notes on compilers".write(
    to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
  try "title,url\n\"Compilers, explained\",https://example.com/book\n".write(
    to: root.appendingPathComponent("books-reading-list.csv"), atomically: true, encoding: .utf8)
  let items = try ArchiveImporter.read(selection: root)
  #expect(
    Set(items.compactMap(\.url)) == [
      "https://example.com/talk", "https://example.com/article?a=1&b=2",
      "https://example.com/notes", "https://example.com/book",
    ])
}

private final class ImportResponseStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let item = ArchiveItem(title: "Compiler internals", source: .obsidian)
      let body = try response(for: item)
      let status = Int(request.value(forHTTPHeaderField: "X-Test-Status") ?? "200") ?? 200
      let http = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
