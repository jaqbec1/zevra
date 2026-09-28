import Foundation
import Testing

@testable import AttentionCore

@Test func archiveLibrarySearchesTheWholeProfileAndCombinesSourceFilter() {
  var linked = ArchiveItem(title: "Żółć and compilers", source: .x, identity: "tweet-1")
  linked.url = "https://example.com/parser"
  linked.topic = "Languages"
  let notes = (0..<350).map { ArchiveItem(title: "Note \($0)", source: .obsidian) }
  let profile = PersonalProfile(items: notes + [linked])
  #expect(profile.libraryItems().count == 351)
  #expect(profile.libraryItems(search: "  ZOLC  ") == [linked])
  #expect(profile.libraryItems(search: "PARSER", source: .x) == [linked])
  #expect(profile.libraryItems(search: "languages") == [linked])
  #expect(profile.libraryItems(search: "parser", source: .obsidian).isEmpty)
  #expect(profile.libraryItems(source: .obsidian) == notes)
  #expect(profile.libraryItems(search: "absent").isEmpty)
}

@Test(arguments: ["Compilers", "  Compilers  ", String(repeating: "x", count: 121)])
func archiveEditingPreservesIdentityRatingsAndUnrelatedProfileData(topic: String) throws {
  var item = ArchiveItem(title: "Original", source: .x, identity: "tweet-1")
  item.topic = topic
  let other = ArchiveItem(title: "Another material", source: .books)
  let profile = PersonalProfile(
    goals: "Learn parsing", interests: ["Languages"], items: [item, other],
    ratings: [item.id: .worthwhile], pageRatings: ["https://example.org/": .notWorthwhile],
    evaluationEnabled: true)
  let updated = try profile.editingMaterial(
    id: item.id, title: "  Revised title  ", link: "https://example.com/parser?utm_source=x",
    policy: CapturePolicy(enabled: true))
  #expect(updated.items.count == 2)
  #expect(updated.items[0].id == item.id)
  #expect(updated.items[0].source == .x)
  #expect(updated.items[0].topic == topic)
  #expect(updated.items[0].title == "Revised title")
  #expect(updated.items[0].url == "https://example.com/parser")
  #expect(updated.items[1] == other)
  #expect(updated.ratings == profile.ratings)
  #expect(updated.pageRatings == profile.pageRatings)
  #expect(updated.goals == profile.goals)
  #expect(updated.interests == profile.interests)
  #expect(updated.evaluationEnabled == profile.evaluationEnabled)
  let decoded = try JSONDecoder().decode(PersonalProfile.self, from: JSONEncoder().encode(updated))
  #expect(decoded.revision == updated.revision)
  #expect(profile.items[0] == item)
  let withoutLink = try updated.editingMaterial(
    id: item.id, title: "Revised title", link: "  ", policy: CapturePolicy(enabled: true))
  #expect(withoutLink.items[0].url == nil)
}

@Test func invalidArchiveEditCannotAppendOrPartiallyChangeTheProfile() throws {
  let item = ArchiveItem(title: "Original", source: .obsidian)
  let profile = PersonalProfile(items: [item])
  let originalRevision = profile.revision
  let policy = CapturePolicy(enabled: true, excludedDomains: ["blocked.example.com"])
  for (title, link) in [
    ("", ""), (String(repeating: "x", count: 241), ""),
    ("Changed", "file:///tmp/private"), ("Changed", "https://blocked.example.com/post"),
    ("Changed", "https://example.com/login"),
  ] {
    #expect(throws: (any Error).self) {
      try profile.editingMaterial(id: item.id, title: title, link: link, policy: policy)
    }
  }
  #expect(throws: ArchiveLibraryError.self) {
    try profile.editingMaterial(id: "missing", title: "New", link: "", policy: policy)
  }
  #expect(profile.revision == originalRevision)
}
