import CryptoKit
import Foundation
import Yams

public enum ArchiveSource: String, Codable, Sendable, CaseIterable {
  case obsidian = "Obsidian"
  case x = "X"
  case youtube = "YouTube"
  case books = "Books"
  case other = "Other"
}

public struct ArchiveItem: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var title: String
  public let source: ArchiveSource
  public var url: String?
  public var topic: String?

  public init(title: String, source: ArchiveSource, identity: String? = nil) {
    self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    self.source = source
    let digest = SHA256.hash(
      data: Data("\(source.rawValue)\u{0}\(identity ?? self.title.lowercased())".utf8))
    id = digest.map { String(format: "%02x", $0) }.joined()
  }
}

public enum MaterialRating: String, Codable, Sendable {
  case worthwhile
  case notWorthwhile
}

public struct PersonalProfile: Codable, Sendable {
  public var goals: String
  public var interests: [String]
  public var items: [ArchiveItem]
  public var ratings: [String: MaterialRating]
  public var pageRatings: [String: MaterialRating]
  public var evaluationEnabled: Bool

  public init(
    goals: String = "", interests: [String] = [], items: [ArchiveItem] = [],
    ratings: [String: MaterialRating] = [:],
    pageRatings: [String: MaterialRating] = [:],
    evaluationEnabled: Bool = false
  ) {
    self.goals = goals
    self.interests = interests
    self.items = items
    self.ratings = ratings
    self.pageRatings = pageRatings
    self.evaluationEnabled = evaluationEnabled
  }

  public var worthwhileExamples: [ArchiveItem] {
    items.filter { ratings[$0.id] == .worthwhile }
  }

  public var notWorthwhileExamples: [ArchiveItem] {
    items.filter { ratings[$0.id] == .notWorthwhile }
  }

  public var readyForWorthJudgment: Bool {
    !goals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && worthwhileExamples.count >= 2 && notWorthwhileExamples.count >= 2
  }

  public var calibrationCandidates: [ArchiveItem] {
    let unrated = items.filter { ratings[$0.id] == nil }.sorted { $0.id < $1.id }
    // Spread the first examples across sources rather than taking one large archive first.
    var buckets = Dictionary(grouping: unrated, by: \.source)
    var result: [ArchiveItem] = []
    while result.count < 10 {
      var added = false
      for source in ArchiveSource.allCases {
        if var bucket = buckets[source], !bucket.isEmpty {
          result.append(bucket.removeFirst())
          buckets[source] = bucket
          added = true
          if result.count == 10 { break }
        }
      }
      if !added { break }
    }
    return result
  }

  public var suggestedTopics: [String] {
    var counts: [String: Int] = [:]
    for item in items {
      for word in Self.words(in: item.title) { counts[word, default: 0] += 1 }
    }
    return Array(
      counts.filter { $0.value >= 2 }.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
      }.map(\.key).prefix(12))
  }

  public var revision: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = (try? encoder.encode(self)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public func relevantItems(
    for pageText: String, ratedAs rating: MaterialRating? = nil, limit: Int
  ) -> [ArchiveItem] {
    let pageWords = Self.words(in: String(pageText.prefix(2_400)))
    let candidates = items.filter { ratings[$0.id] == rating }
    return Array(
      candidates.sorted { left, right in
        let leftWords = Self.words(in: left.title)
        let rightWords = Self.words(in: right.title)
        let leftScore =
          Double(pageWords.intersection(leftWords).count)
          / Double(max(leftWords.count, 1))
        let rightScore =
          Double(pageWords.intersection(rightWords).count)
          / Double(max(rightWords.count, 1))
        return leftScore == rightScore ? left.id < right.id : leftScore > rightScore
      }.prefix(max(limit, 0)))
  }

  private static func words(in text: String) -> Set<String> {
    let stopwords: Set<String> = [
      "about", "after", "also", "from", "have", "into", "more", "that", "their", "them",
      "there", "these", "this", "with", "your", "które", "oraz", "przez", "tego", "tych",
      "post", "video", "watch", "article", "guide", "notes", "part", "episode",
    ]
    return Set(
      text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 4 && !stopwords.contains($0) })
  }
}

public enum ArchiveImporter {
  public enum ImportError: Error, LocalizedError {
    case unsupportedSelection, tooManyFiles, notesFolderRequired, unreadableFolder
    case invalidBase(String)
    case unsupportedNoteProperties

    public var errorDescription: String? {
      switch self {
      case .unsupportedSelection:
        "Choose a folder or a Markdown, JSON, JS, HTML or CSV export."
      case .tooManyFiles:
        "The selected collection is too large. Choose a smaller notes folder."
      case .notesFolderRequired:
        "Choose a notes folder first, then optionally a Base filter. The Base does not define where notes are read."
      case .unreadableFolder:
        "Could not read the complete notes folder. Check folder access and try again. Nothing was imported."
      case .invalidBase(let reason):
        "Nothing was imported. \(reason)"
      case .unsupportedNoteProperties:
        "Nothing was imported. A note has invalid or unsupported properties. Base import requires categories to be a list of simple [[Note name]] links, without paths or aliases, and complete YAML properties within the first 16 KiB."
      }
    }
  }

  public static func read(selection: URL, base: URL? = nil, limit: Int = 2_000) throws
    -> [ArchiveItem]
  {
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: selection.path, isDirectory: &isDirectory) else {
      throw ImportError.unsupportedSelection
    }
    if let base {
      guard isDirectory.boolValue else { throw ImportError.notesFolderRequired }
      return try readObsidianBase(base, source: selection, limit: limit)
    }
    if !isDirectory.boolValue && selection.pathExtension.lowercased() == "base" {
      throw ImportError.notesFolderRequired
    }
    let files: [URL]
    if isDirectory.boolValue {
      guard
        let iterator = manager.enumerator(
          at: selection, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { throw ImportError.unsupportedSelection }
      var found: [URL] = []
      for case let url as URL in iterator {
        if found.count >= 5_000 { throw ImportError.tooManyFiles }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        if supportedInFolder(url) { found.append(url) }
      }
      files = found.sorted { $0.path < $1.path }
    } else {
      guard supported(selection) else { throw ImportError.unsupportedSelection }
      files = [selection]
    }
    var items: [ArchiveItem] = []
    var seen = Set<String>()
    var remainingBytes = 50_000_000
    for file in files {
      if items.count >= limit { break }
      let values = try file.resourceValues(forKeys: [.fileSizeKey])
      guard let size = values.fileSize, size <= 20_000_000, size <= remainingBytes else {
        continue
      }
      let data = try Data(contentsOf: file)
      remainingBytes -= data.count
      let content = String(decoding: data, as: UTF8.self)
      let source = sourceFor(file)
      for material in materials(
        in: content, extension: file.pathExtension.lowercased(),
        fallback: file.deletingPathExtension().lastPathComponent)
      {
        var item = ArchiveItem(title: material.title, source: source)
        item.url = material.link
        guard item.title.count >= 4, seen.insert(item.id).inserted else { continue }
        items.append(item)
        if items.count >= limit { break }
      }
    }
    return items
  }

  private static func supported(_ url: URL) -> Bool {
    ["md", "markdown", "json", "js", "html", "htm", "csv"].contains(url.pathExtension.lowercased())
  }

  private static func readObsidianBase(_ base: URL, source: URL, limit: Int) throws -> [ArchiveItem]
  {
    guard base.pathExtension.lowercased() == "base" else { throw ImportError.unsupportedSelection }
    let handle = try FileHandle(forReadingFrom: base)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 262_145) ?? Data()
    guard data.count <= 262_144, let text = String(data: data, encoding: .utf8) else {
      throw ImportError.invalidBase("The Base must be UTF-8 YAML smaller than 256 KiB.")
    }
    let filter = try ObsidianBaseFilter(contents: text)
    let root = source.resolvingSymlinksInPath().standardizedFileURL
    var enumerationFailed = false
    guard
      let iterator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in
          enumerationFailed = true
          return false
        })
    else { throw ImportError.unreadableFolder }
    var files: [URL] = []
    for case let url as URL in iterator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      if values.isSymbolicLink == true {
        iterator.skipDescendants()
        continue
      }
      guard values.isRegularFile == true,
        ["md", "markdown"].contains(url.pathExtension.lowercased())
      else { continue }
      let resolved = url.resolvingSymlinksInPath().standardizedFileURL
      guard resolved.pathComponents.starts(with: root.pathComponents) else {
        throw ImportError.unreadableFolder
      }
      if files.count >= 5_000 { throw ImportError.tooManyFiles }
      files.append(url)
    }
    guard !enumerationFailed else { throw ImportError.unreadableFolder }
    var items: [ArchiveItem] = []
    var seen = Set<String>()
    for file in files.sorted(by: { $0.path < $1.path }) {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      let prefix = try handle.read(upToCount: 16_384) ?? Data()
      let lines = String(decoding: prefix, as: UTF8.self)
        .replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
      guard lines.first == "---" else { continue }
      guard let end = lines.dropFirst().firstIndex(of: "---") else {
        throw ImportError.unsupportedNoteProperties
      }
      guard
        let material = try filter.material(
          in: Array(lines[1..<end]), fallback: file.deletingPathExtension().lastPathComponent)
      else { continue }
      var item = ArchiveItem(title: material.title, source: .obsidian)
      item.url = material.url
      if item.title.count >= 4, seen.insert(item.id).inserted {
        guard items.count < limit else { throw ImportError.tooManyFiles }
        items.append(item)
      }
    }
    return items
  }

  private static func supportedInFolder(_ url: URL) -> Bool {
    guard supported(url) else { return false }
    if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return true }
    let name = url.lastPathComponent.lowercased()
    return ["bookmark", "youtube", "watch-history", "books-reading-list"].contains {
      name.contains($0)
    }
  }

  private static func sourceFor(_ url: URL) -> ArchiveSource {
    let path = url.path.lowercased()
    if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return .obsidian }
    if path.contains("books-reading-list") { return .books }
    if path.contains("youtube") || path.contains("watch-history") { return .youtube }
    if path.contains("twitter") || path.contains("tweet") || path.contains("bookmarks")
      || path.contains("/x/")
    {
      return .x
    }
    return .other
  }

  private struct MaterialText {
    let title: String
    let link: String?
  }

  private static func materials(in content: String, extension kind: String, fallback: String)
    -> [MaterialText]
  {
    switch kind {
    case "md", "markdown":
      let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
      var link: String?
      if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"),
        let node = try? Yams.compose(yaml: lines[1..<end].joined(separator: "\n"))
      {
        link =
          ["url", "source", "link"].compactMap { node[$0]?.string }.compactMap(ModelImport.webLink)
          .first
      }
      if let heading = lines.first(where: { $0.hasPrefix("# ") }) {
        return [MaterialText(title: String(heading.dropFirst(2)), link: link)]
      }
      return [MaterialText(title: fallback, link: link)]
    case "json", "js":
      let json =
        kind == "js"
        ? String(
          content.dropFirst(
            content.firstIndex(of: "=").map {
              content.distance(from: content.startIndex, to: $0) + 1
            } ?? 0)
        ).trimmingCharacters(in: CharacterSet(charactersIn: "; \n\r")) : content
      guard let data = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data)
      else { return [] }
      var found: [MaterialText] = []
      collectTitles(object, into: &found, depth: 0)
      return found
    case "html", "htm":
      let pattern = #"(?is)<a\b([^>]*)>(.*?)</a>"#
      let regex = try? NSRegularExpression(pattern: pattern)
      let range = NSRange(content.startIndex..<content.endIndex, in: content)
      let hrefRegex = try? NSRegularExpression(pattern: #"(?i)\bhref\s*=\s*["']([^"']+)["']"#)
      return (regex?.matches(in: content, range: range) ?? []).compactMap { match in
        guard let valueRange = Range(match.range(at: 2), in: content) else { return nil }
        let attributes = Range(match.range(at: 1), in: content).map { String(content[$0]) } ?? ""
        let href = hrefRegex?.firstMatch(
          in: attributes, range: NSRange(attributes.startIndex..., in: attributes))
        let link = href.flatMap { Range($0.range(at: 1), in: attributes) }
          .map { String(attributes[$0]).replacingOccurrences(of: "&amp;", with: "&") }
          .flatMap(ModelImport.webLink)
        let title = String(content[valueRange]).replacingOccurrences(
          of: #"<[^>]+>"#, with: " ", options: .regularExpression
        )
        .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(
          in: .whitespacesAndNewlines)
        return MaterialText(title: title, link: link)
      }
    case "csv":
      let rows = csvRows(content)
      guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) })
      else { return [] }
      let titleColumn = header.firstIndex(where: { ["title", "name"].contains($0) }) ?? 0
      let linkColumn = header.firstIndex(where: { ["url", "link", "titleurl"].contains($0) })
      return rows.dropFirst().prefix(2_000).compactMap { row in
        guard row.indices.contains(titleColumn) else { return nil }
        let link = linkColumn.flatMap {
          row.indices.contains($0) ? ModelImport.webLink(row[$0]) : nil
        }
        return MaterialText(title: row[titleColumn], link: link)
      }
    default: return []
    }
  }

  private static func csvRows(_ content: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var iterator = content.makeIterator()
    while let character = iterator.next() {
      if character == "\"" {
        quoted.toggle()
        if !quoted {
          // A second quote reopens the quoted field and represents one literal quote.
          var lookahead = iterator
          if lookahead.next() == "\"" {
            field.append("\"")
            _ = iterator.next()
            quoted = true
          }
        }
      } else if character == ",", !quoted {
        row.append(field)
        field = ""
      } else if character.isNewline, !quoted {
        row.append(field)
        rows.append(row)
        row = []
        field = ""
        if rows.count >= 2_001 { break }
      } else {
        field.append(character)
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }

  private static func collectTitles(_ value: Any, into found: inout [MaterialText], depth: Int) {
    guard depth < 8, found.count < 2_000 else { return }
    if let object = value as? [String: Any] {
      for key in ["full_text", "title"] {
        if let title = object[key] as? String, !title.hasPrefix("http") {
          let link = ["titleUrl", "url", "expanded_url", "link"].compactMap {
            object[$0] as? String
          }
          .compactMap(ModelImport.webLink).first
          found.append(MaterialText(title: title, link: link))
          break
        }
      }
      for child in object.values { collectTitles(child, into: &found, depth: depth + 1) }
    } else if let array = value as? [Any] {
      for child in array { collectTitles(child, into: &found, depth: depth + 1) }
    }
  }
}
