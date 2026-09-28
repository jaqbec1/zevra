import AttentionCore
import SwiftUI

struct ImportedLibraryView: View {
  @ObservedObject var model: AppModel
  var chooseSource: () -> Void
  var chooseBase: () -> Void
  @State private var search = ""
  @State private var source: ArchiveSource?
  @State private var editing: ArchiveItem?

  var body: some View {
    let items = model.personalProfile.libraryItems(search: search, source: source)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Saved materials").font(.title.weight(.semibold))
          Text("Imported notes, bookmarks and pages you have rated.")
            .font(.body).foregroundStyle(ZevraStyle.secondaryText)
          Text("\(items.count) of \(model.personalProfile.items.count) materials")
            .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
        }
        Spacer()
        Menu {
          Button("From folder or export…", action: chooseSource)
          Button("Filter notes with Obsidian Base…", action: chooseBase).disabled(model.demo)
        } label: {
          Label(
            model.importingArchive ? "Importing…" : "Import…", systemImage: "square.and.arrow.down")
        }
        .disabled(model.importingArchive)
        .menuStyle(.borderedButton)
        .fixedSize()
      }
      .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

      HStack(spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").foregroundStyle(ZevraStyle.secondaryText)
          TextField(
            "Search titles, links or topics", text: $search,
            prompt: Text("Search titles, links or topics").foregroundStyle(ZevraStyle.secondaryText)
          )
          .textFieldStyle(.plain).accessibilityLabel("Search saved materials")
          if !search.isEmpty {
            Button {
              search = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain).accessibilityLabel("Clear material search")
          }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        Picker("Source", selection: $source) {
          Text("All sources").tag(ArchiveSource?.none)
          ForEach(ArchiveSource.allCases, id: \.self) { value in
            Text(value.rawValue).tag(Optional(value))
          }
        }
        .frame(width: 180)
      }
      .padding(.horizontal, 24).padding(.bottom, 16)

      if model.personalProfile.items.isEmpty {
        ContentUnavailableView {
          Label("Import your first materials", systemImage: "books.vertical")
        } description: {
          Text("Import notes or bookmarks, then review them before saving.")
        } actions: {
          Button("Choose a source…", action: chooseSource)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if items.isEmpty {
        ContentUnavailableView {
          Label("No matching materials", systemImage: "magnifyingglass")
        } description: {
          Text("Try another title, link or source.")
        } actions: {
          Button("Clear filters") {
            search = ""
            source = nil
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(items) { item in
          row(item)
            .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
      }

      Divider()
      Text(model.demo ? "Demo · edits stay in memory" : "Saved materials · stored on this Mac")
        .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
        .padding(.horizontal, 24).padding(.vertical, 11)
    }
    .sheet(item: $editing) { item in
      ArchiveMaterialEditor(model: model, item: item)
    }
  }

  private func row(_ item: ArchiveItem) -> some View {
    let canOpen = model.archiveURL(for: item) != nil
    return HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text(item.title).font(.body.weight(.medium)).lineLimit(3).help(item.title)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
          Text(item.source.rawValue)
          if let rating = model.personalProfile.ratings[item.id] {
            Text(rating == .worthwhile ? "Worthwhile" : "Not worthwhile")
          } else {
            Text("Unrated")
          }
          if let topic = item.topic { Text(topic).lineLimit(1) }
        }
        .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
        if let link = item.url {
          Text(link).font(.caption).foregroundStyle(ZevraStyle.secondaryText).lineLimit(1).help(
            link)
          if !canOpen {
            Text("Link unavailable under current site rules")
              .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
          }
        } else {
          Text("No link added").font(.caption).foregroundStyle(ZevraStyle.secondaryText)
        }
      }
      HStack(spacing: 8) {
        Button("Open") { model.openArchiveItem(item) }
          .disabled(!canOpen).help(canOpen ? "Open in your browser" : "No available link")
          .accessibilityLabel("Open \(item.title)")
        Button("Edit") { editing = item }
          .accessibilityLabel("Edit \(item.title)")
      }
      .buttonStyle(.bordered).controlSize(.small)
    }
    .padding(.vertical, 2)
  }
}

private struct ArchiveMaterialEditor: View {
  @ObservedObject var model: AppModel
  let item: ArchiveItem
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var link: String
  @State private var error: String?

  init(model: AppModel, item: ArchiveItem) {
    self.model = model
    self.item = item
    _title = State(initialValue: item.title)
    _link = State(initialValue: item.url ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit material").font(.title2.weight(.semibold))
      Text("\(item.source.rawValue) · Your rating stays unchanged.")
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
      VStack(alignment: .leading, spacing: 6) {
        Text("Title").font(.headline)
        TextEditor(text: $title).frame(height: 100)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .accessibilityLabel("Saved material title")
        Text("\(title.trimmingCharacters(in: .whitespacesAndNewlines).count) / 240 characters")
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Link (optional)").font(.headline)
        TextField("https://…", text: $link).accessibilityLabel("Saved material link")
        Text("Use a full HTTP or HTTPS link. Your site rules apply when saving and opening.")
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      }
      if let error {
        Label(error, systemImage: "exclamationmark.circle")
          .foregroundStyle(.primary).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if model.demo {
          Text("Demo · not saved to disk").font(.caption).foregroundStyle(ZevraStyle.secondaryText)
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save changes") {
          error = model.saveArchiveItem(id: item.id, title: title, link: link)
          if error == nil { dismiss() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || title.trimmingCharacters(in: .whitespacesAndNewlines).count > 240)
      }
    }
    .padding(24).frame(width: 540)
  }
}
