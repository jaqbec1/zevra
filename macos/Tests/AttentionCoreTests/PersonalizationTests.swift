import Foundation
import Testing

@testable import AttentionCore

@Test func archiveImportTreatsHistoryAsUnratedCandidates() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try "# A useful note about compilers\nPersonal notes".write(
    to: directory.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
  try #"[{"title":"Compiler architecture talk"},{"title":"Another video"}]"#.write(
    to: directory.appendingPathComponent("youtube-watch-history.json"), atomically: true,
    encoding: .utf8)
  let imported = try ArchiveImporter.read(selection: directory)
  #expect(imported.count == 3)
  #expect(
    imported.contains { $0.source == .obsidian && $0.title == "A useful note about compilers" })
  #expect(imported.contains { $0.source == .youtube && $0.title == "Compiler architecture talk" })
  let profile = PersonalProfile(items: imported)
  #expect(profile.ratings.isEmpty)
  #expect(!profile.readyForWorthJudgment)
}

@Test func worthJudgmentRequiresGoalsAndBothKindsOfExamples() {
  let items = (0..<4).map { ArchiveItem(title: "Distinct article \($0)", source: .obsidian) }
  var profile = PersonalProfile(items: items)
  for item in items.prefix(2) { profile.ratings[item.id] = .worthwhile }
  for item in items.suffix(2) { profile.ratings[item.id] = .notWorthwhile }
  #expect(!profile.readyForWorthJudgment)
  profile.goals = "Learn compiler design"
  #expect(profile.readyForWorthJudgment)
  #expect(profile.calibrationCandidates.isEmpty)
}

@Test func exportsImportTitlesWithoutTreatingThemAsRatings() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let xFile = directory.appendingPathComponent("twitter-bookmarks.js")
  try
    #"window.YTD.bookmark.part0 = [{"tweet":{"full_text":"A detailed note on local-first software"}}];"#
    .write(to: xFile, atomically: true, encoding: .utf8)
  try #"window.YTD.dm.part0 = [{"message":{"full_text":"Private direct message"}}];"#
    .write(to: directory.appendingPathComponent("dm.js"), atomically: true, encoding: .utf8)
  let youtubeFile = directory.appendingPathComponent("youtube-watch-history.html")
  try #"<a href="https://youtube.com/watch?v=synthetic">How compilers parse code</a>"#
    .write(to: youtubeFile, atomically: true, encoding: .utf8)
  let imported = try ArchiveImporter.read(selection: directory)
  #expect(imported.count == 2)
  #expect(!imported.contains { $0.title == "Private direct message" })
  #expect(
    imported.contains { $0.source == .x && $0.title == "A detailed note on local-first software" })
  #expect(imported.contains { $0.source == .youtube && $0.title == "How compilers parse code" })
  #expect(PersonalProfile(items: imported).ratings.isEmpty)
}

@Test func notesStoreHeadingsRatherThanBodies() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("article.md")
  try "# Good article\nPrivate diary content must not become a title".write(
    to: file, atomically: true, encoding: .utf8)
  let imported = try ArchiveImporter.read(selection: file)
  #expect(imported.map(\.title) == ["Good article"])
}

@Test func obsidianBaseImportsOnlyMatchingFrontmatter() throws {
  let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let bases = vault.appendingPathComponent("Bases")
  try FileManager.default.createDirectory(at: bases, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: vault) }
  let base = bases.appendingPathComponent("Consumables.base")
  try "views:\n  - name: All\n    filters:\n      - categories.contains(link(\"Clippings\"))"
    .write(to: base, atomically: true, encoding: .utf8)
  try
    "---\ntitle: Useful compiler guide\ncategories: [\"[[Clippings]]\"]\nstatus: Consumed\n---\nBody"
    .write(to: vault.appendingPathComponent("included.md"), atomically: true, encoding: .utf8)
  try "---\ncategories:\n  - \"[[Other]]\"\n---\n[[Clippings]] in body"
    .write(to: vault.appendingPathComponent("excluded.md"), atomically: true, encoding: .utf8)
  let imported = try ArchiveImporter.read(selection: base)
  #expect(imported.map(\.title) == ["Useful compiler guide"])
  #expect(PersonalProfile(items: imported).ratings.isEmpty)
}

@Test func selectedBooksListRemainsUnrated() throws {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(
    "books-reading-list-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: file) }
  try #"[{"title":"A thoughtful engineering book"}]"#.write(
    to: file, atomically: true, encoding: .utf8)
  let imported = try ArchiveImporter.read(selection: file)
  #expect(imported.count == 1)
  #expect(imported[0].source == .books)
  #expect(PersonalProfile(items: imported).ratings.isEmpty)
}

@Test func pageRelatedExamplesAreChosenAcrossWholeArchive() {
  let unrelated = (0..<40).map {
    ArchiveItem(title: "Cooking technique number \($0)", source: .youtube)
  }
  let relevant = ArchiveItem(title: "Compiler parsing techniques", source: .obsidian)
  var profile = PersonalProfile(items: unrelated + [relevant])
  profile.ratings[relevant.id] = .worthwhile
  #expect(
    profile.relevantItems(for: "A guide to compiler parsing", ratedAs: .worthwhile, limit: 1).first
      == relevant)
  #expect(profile.relevantItems(for: "Cooking technique", limit: 2).count == 2)
}
