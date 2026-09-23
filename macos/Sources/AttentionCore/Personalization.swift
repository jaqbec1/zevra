import CryptoKit
import Foundation

public enum ArchiveSource: String, Codable, Sendable, CaseIterable {
  case obsidian = "Obsidian"
  case x = "X"
  case youtube = "YouTube"
  case other = "Other"
}

public struct ArchiveItem: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let source: ArchiveSource

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
  public enum ImportError: Error { case unsupportedSelection, tooManyFiles }

  public static func read(selection: URL, limit: Int = 2_000) throws -> [ArchiveItem] {
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: selection.path, isDirectory: &isDirectory) else {
      throw ImportError.unsupportedSelection
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
      for title in titles(
        in: content, extension: file.pathExtension.lowercased(),
        fallback: file.deletingPathExtension().lastPathComponent)
      {
        let item = ArchiveItem(title: title, source: source)
        guard item.title.count >= 5, seen.insert(item.id).inserted else { continue }
        items.append(item)
        if items.count >= limit { break }
      }
    }
    return items
  }

  private static func supported(_ url: URL) -> Bool {
    ["md", "markdown", "json", "js", "html", "htm", "csv"].contains(url.pathExtension.lowercased())
  }

  private static func supportedInFolder(_ url: URL) -> Bool {
    guard supported(url) else { return false }
    if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return true }
    let name = url.lastPathComponent.lowercased()
    return ["bookmark", "youtube", "watch-history"].contains { name.contains($0) }
  }

  private static func sourceFor(_ url: URL) -> ArchiveSource {
    let path = url.path.lowercased()
    if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return .obsidian }
    if path.contains("youtube") || path.contains("watch-history") { return .youtube }
    if path.contains("twitter") || path.contains("tweet") || path.contains("bookmarks")
      || path.contains("/x/")
    {
      return .x
    }
    return .other
  }

  private static func titles(in content: String, extension kind: String, fallback: String)
    -> [String]
  {
    switch kind {
    case "md", "markdown":
      if let heading = content.split(separator: "\n", omittingEmptySubsequences: false)
        .first(where: { $0.hasPrefix("# ") })
      {
        return [String(heading.dropFirst(2))]
      }
      return [fallback]
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
      var found: [String] = []
      collectTitles(object, into: &found, depth: 0)
      return found
    case "html", "htm":
      let pattern = #"(?is)<a\b[^>]*>(.*?)</a>"#
      let regex = try? NSRegularExpression(pattern: pattern)
      let range = NSRange(content.startIndex..<content.endIndex, in: content)
      return (regex?.matches(in: content, range: range) ?? []).compactMap { match in
        guard let valueRange = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[valueRange]).replacingOccurrences(
          of: #"<[^>]+>"#, with: " ", options: .regularExpression
        )
        .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(
          in: .whitespacesAndNewlines)
      }
    case "csv":
      return content.split(separator: "\n").dropFirst().prefix(2_000).compactMap { line in
        let first = line.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: CharacterSet(charactersIn: "\" \r"))
      }
    default: return []
    }
  }

  private static func collectTitles(_ value: Any, into found: inout [String], depth: Int) {
    guard depth < 8, found.count < 2_000 else { return }
    if let object = value as? [String: Any] {
      for key in ["full_text", "title"] {
        if let title = object[key] as? String, !title.hasPrefix("http") {
          found.append(title)
          break
        }
      }
      for child in object.values { collectTitles(child, into: &found, depth: depth + 1) }
    } else if let array = value as? [Any] {
      for child in array { collectTitles(child, into: &found, depth: depth + 1) }
    }
  }
}
