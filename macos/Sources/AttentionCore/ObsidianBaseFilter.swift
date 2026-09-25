import Foundation
import Yams

/// A deliberately small subset of Bases. Unsupported selection rules fail before any import.
struct ObsidianBaseFilter {
  let categories: Set<String>

  init(contents: String, viewName: String? = nil) throws {
    let root = try Self.document(contents)
    let views = try Self.views(in: root)
    let defaultName =
      views.contains { $0["name"]?.string == "All" }
      ? "All" : (views.count == 1 ? views.first?["name"]?.string : nil)
    guard let selectedName = viewName ?? defaultName,
      let view = views.first(where: { $0["name"]?.string == selectedName })
    else {
      throw ArchiveImporter.ImportError.invalidBase(
        "Choose an existing view from this Base before importing.")
    }
    try Self.allowKeys(
      ["type", "name", "filters", "order", "sort", "columnSize", "summaries"], in: view,
      context: "selected view (row limits and grouping are not supported)")
    var categories = Set<String>()
    for (context, node) in [
      ("global filters", root["filters"]), ("selected view filters", view["filters"]),
    ] {
      if let node {
        categories.formUnion(try Self.readCategories(node, context: context, depth: 0))
      }
    }
    guard !categories.isEmpty else {
      throw ArchiveImporter.ImportError.invalidBase(
        "Add a supported category filter to the selected view or global filters.")
    }
    self.categories = categories
  }

  static func viewNames(contents: String) throws -> [String] {
    try views(in: document(contents)).compactMap { $0["name"]?.string }
  }

  private static func document(_ contents: String) throws -> [String: Node] {
    let root = try mapping(parse(contents), context: "Base document")
    try allowKeys(
      ["filters", "views", "properties", "formulas"], in: root, context: "Base document")
    return root
  }

  private static func views(in root: [String: Node]) throws -> [[String: Node]] {
    guard let nodes = root["views"]?.sequence, !nodes.isEmpty else {
      throw ArchiveImporter.ImportError.invalidBase("Expected a nonempty views list.")
    }
    var names = Set<String>()
    return try nodes.map { node in
      let view = try mapping(node, context: "view")
      guard let name = view["name"]?.string,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        names.insert(name).inserted
      else {
        throw ArchiveImporter.ImportError.invalidBase(
          "Each view must have a unique, nonempty name.")
      }
      return view
    }
  }

  func material(in lines: [String], fallback: String) throws -> (title: String, url: String?)? {
    let metadata: [String: Node]
    do {
      guard let node = try Yams.compose(yaml: lines.joined(separator: "\n")), node.null == nil
      else {
        return nil
      }
      metadata = try Self.mapping(node, context: "note properties")
    } catch {
      throw ArchiveImporter.ImportError.unsupportedNoteProperties
    }
    guard let property = metadata["categories"], property.null == nil else { return nil }
    guard let values = property.sequence else {
      throw ArchiveImporter.ImportError.unsupportedNoteProperties
    }
    var links = Set<String>()
    for value in values {
      guard let text = value.string, text.hasPrefix("[["), text.hasSuffix("]]"),
        Self.simpleLinkName(String(text.dropFirst(2).dropLast(2)))
      else { throw ArchiveImporter.ImportError.unsupportedNoteProperties }
      links.insert(String(text.dropFirst(2).dropLast(2)))
    }
    guard categories.isSubset(of: links) else { return nil }
    let title = metadata["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    let url = ["url", "source", "link"].compactMap { metadata[$0]?.string }.compactMap(
      ModelImport.webLink
    ).first
    return (title, url)
  }

  private static func readCategories(_ node: Node, context: String, depth: Int) throws -> Set<
    String
  > {
    guard depth < 16 else {
      throw ArchiveImporter.ImportError.invalidBase("Filters are nested too deeply.")
    }
    if let expression = node.string {
      let prefix = "categories.contains(link(\""
      let suffix = "\"))"
      let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
      guard expression.hasPrefix(prefix), expression.hasSuffix(suffix) else {
        throw ArchiveImporter.ImportError.invalidBase(
          "Unsupported condition in \(context). Only categories.contains(link(\"Name\")) and AND groups are supported."
        )
      }
      let category = String(expression.dropFirst(prefix.count).dropLast(suffix.count))
      guard simpleLinkName(category) else {
        throw ArchiveImporter.ImportError.invalidBase(
          "Category links must be simple note names without paths, aliases or expressions.")
      }
      return [category]
    }
    let group = try mapping(node, context: context)
    guard group.count == 1, let children = group["and"]?.sequence, !children.isEmpty else {
      throw ArchiveImporter.ImportError.invalidBase(
        "Unsupported condition in \(context). Only nonempty AND groups are supported.")
    }
    return try children.reduce(into: Set<String>()) { result, child in
      result.formUnion(try readCategories(child, context: context, depth: depth + 1))
    }
  }

  private static func simpleLinkName(_ value: String) -> Bool {
    !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\|#[]\"()\n\r")) == nil
      && !value.hasSuffix(".md") && value != "." && value != ".."
  }

  private static func parse(_ text: String) throws -> Node {
    do {
      guard let node = try Yams.compose(yaml: text) else {
        throw ArchiveImporter.ImportError.invalidBase("The YAML document is empty.")
      }
      return node
    } catch {
      // Parser diagnostics can contain private source excerpts; keep them out of UI/logs.
      throw ArchiveImporter.ImportError.invalidBase("Could not read a single valid YAML document.")
    }
  }

  private static func mapping(_ node: Node, context: String) throws -> [String: Node] {
    guard let mapping = node.mapping else {
      throw ArchiveImporter.ImportError.invalidBase("Expected a property mapping in \(context).")
    }
    var result: [String: Node] = [:]
    for (key, value) in mapping {
      guard let key = key.string, result[key] == nil else {
        throw ArchiveImporter.ImportError.invalidBase(
          "Duplicate or invalid property in \(context).")
      }
      result[key] = value
    }
    return result
  }

  private static func allowKeys(_ keys: Set<String>, in mapping: [String: Node], context: String)
    throws
  {
    guard Set(mapping.keys).isSubset(of: keys) else {
      throw ArchiveImporter.ImportError.invalidBase("Unsupported property in \(context).")
    }
  }
}
