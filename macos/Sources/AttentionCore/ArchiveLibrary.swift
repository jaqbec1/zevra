import Foundation

public enum ArchiveLibraryError: Error, LocalizedError {
  case missingMaterial, invalidTitle

  public var errorDescription: String? {
    switch self {
    case .missingMaterial:
      "This material is no longer in your library. Close the editor and try again."
    case .invalidTitle:
      "Enter a title between 1 and 240 characters."
    }
  }
}

extension PersonalProfile {
  public func libraryItems(search: String = "", source: ArchiveSource? = nil) -> [ArchiveItem] {
    func normalized(_ value: String) -> String {
      value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(of: "ł", with: "l")
    }
    let query = normalized(search.trimmingCharacters(in: .whitespacesAndNewlines))
    return items.filter { item in
      guard source == nil || item.source == source else { return false }
      return query.isEmpty
        || [item.title, item.url ?? "", item.topic ?? ""].contains {
          normalized($0).contains(query)
        }
    }
  }

  public func editingMaterial(id: String, title: String, link: String, policy: CapturePolicy) throws
    -> PersonalProfile
  {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw ArchiveLibraryError.missingMaterial
    }
    let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTitle.isEmpty, cleanedTitle.count <= 240 else {
      throw ArchiveLibraryError.invalidTitle
    }
    // Reuse import validation, but replace only the existing item. Its identity,
    // source, topic and ratings do not depend on the edited display title or URL.
    var draft = ImportDraft(candidates: [items[index]])
    draft.materials[0].title = title
    draft.materials[0].link = link
    draft.materials[0].topic = ""
    var updated = self
    updated.items[index] = try draft.selectedMaterials(policy: policy)[0]
    updated.items[index].topic = items[index].topic
    return updated
  }
}
