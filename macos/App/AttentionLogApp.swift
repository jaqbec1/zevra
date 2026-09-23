import AppKit
import AttentionCore
import SwiftUI

@main
struct AttentionLogApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    Window("Zevra", id: "observations") {
      ObservationsView(model: model)
    }
    .defaultSize(width: 960, height: 720)
    MenuBarExtra(
      "Zevra", systemImage: model.capturing ? "circle.inset.filled" : "circle.dotted"
    ) {
      MenuContent(model: model)
    }
  }
}

private struct MenuContent: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(model.status)
    Button("Open Zevra") {
      openWindow(id: "observations")
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    Button(model.capturing ? "Pause capture" : "Resume capture") {
      model.setCapture(!model.capturing)
    }
    .disabled(model.demo || model.storageFailed)
    Divider()
    Button("Quit Zevra") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }
}

private struct ObservationsView: View {
  private enum Panel: String, CaseIterable {
    case library = "Library"
    case settings = "Settings"

    var symbol: String { self == .library ? "square.stack" : "slider.horizontal.3" }
  }

  @ObservedObject var model: AppModel
  @State private var panel: Panel = .library
  @State private var pendingKey = ""

  private var isSearching: Bool {
    !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: "square.stack.3d.up.fill")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
          .background(.green.gradient, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Zevra").font(.system(size: 21, weight: .semibold, design: .rounded))
          Text("A quiet record of what held your attention")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if model.demo {
          Label("Preview", systemImage: "sparkles")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        } else {
          HStack(spacing: 7) {
            Circle().fill(model.capturing ? Color.green : Color.secondary)
              .frame(width: 7, height: 7)
            Text(model.status).lineLimit(1)
          }
          .font(.caption).foregroundStyle(.secondary)
          .help(model.status)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 16)

      HStack(spacing: 8) {
        ForEach(Panel.allCases, id: \.self) { item in
          Button {
            panel = item
          } label: {
            Label(item.rawValue, systemImage: item.symbol)
              .font(.subheadline.weight(panel == item ? .semibold : .medium))
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .foregroundStyle(panel == item ? .primary : .secondary)
              .background(
                panel == item ? Color(nsColor: .controlBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(panel == item ? .isSelected : [])
        }
        Spacer()
        if !model.demo {
          Button(model.capturing ? "Pause capture" : "Resume capture") {
            model.setCapture(!model.capturing)
          }
          .buttonStyle(.bordered)
          .disabled(model.storageFailed)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
      Divider()

      if panel == .library {
        library
      } else {
        settings
      }
    }
    .frame(minWidth: 740, minHeight: 600)
    .background(Color(nsColor: .windowBackgroundColor))
    .tint(.green)
    .alert(
      "Zevra",
      isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    ) {
      Button("OK") { model.notice = nil }
    } message: {
      Text(model.notice ?? "")
    }
  }

  private var library: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Saved materials").font(.system(size: 24, weight: .semibold, design: .rounded))
          Text(
            "\(model.observations.count) \(model.observations.count == 1 ? "visit" : "visits") shown"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
      }
      .padding(.horizontal, 24)
      .padding(.top, 22)
      .padding(.bottom, 16)

      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search titles or URLs", text: $model.searchText)
          .textFieldStyle(.plain)
          .accessibilityLabel("Search saved materials")
        if !model.searchText.isEmpty {
          Button {
            model.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear search")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
      .padding(.horizontal, 24)
      .padding(.bottom, 16)

      if model.observations.isEmpty {
        ContentUnavailableView(
          isSearching ? "No matching materials" : "No saved materials yet",
          systemImage: isSearching ? "magnifyingglass" : "square.stack",
          description: Text(
            isSearching
              ? "Try a different title or URL."
              : "Spend a few seconds on an eligible page in Arc. Saved pages appear here."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(model.observations) { observation in
            materialRow(observation)
              .listRowSeparator(.visible)
              .listRowInsets(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24))
          }
          if model.hasMoreObservations {
            Button("Load more visits") { model.loadMore() }
              .frame(maxWidth: .infinity)
              .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }

      Divider()
      HStack {
        Text(model.demo ? "Sample pages from two fictional Macs" : model.syncStatus)
        Spacer()
        Text("Active time is estimated from consecutive samples")
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .padding(.horizontal, 24)
      .padding(.vertical, 11)
    }
  }

  private func materialRow(_ observation: Observation) -> some View {
    let classification = model.classifications[observation.url]
    return HStack(alignment: .top, spacing: 14) {
      Image(systemName: "doc.text")
        .font(.system(size: 17))
        .foregroundStyle(.secondary)
        .frame(width: 36, height: 36)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(observation.title.isEmpty ? "Untitled page" : observation.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
        Text(observation.url)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(observation.url)
        HStack(spacing: 10) {
          Text(observation.deviceID == model.deviceID ? "This Mac" : "Another Mac")
          Text("·")
          Text(observation.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
          if let choice = classification?.displayedChoice {
            Text("·")
            Label(
              "\(classification?.correction == nil ? "Jev" : "You") · \(choice.rawValue)",
              systemImage: classification?.correction == nil ? "sparkle" : "checkmark.circle"
            )
            .foregroundStyle(classification?.correction == nil ? .secondary : .primary)
            if classification?.correction == nil {
              if classification?.status == "Needs review" {
                Text("Needs review").foregroundStyle(.orange)
              } else if classification?.status != "Jev suggestion",
                let status = classification?.status
              {
                Text(status)
              }
            }
          } else if let classification {
            Text("·")
            Text(classification.status)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      VStack(alignment: .trailing, spacing: 10) {
        Text(
          Duration.seconds(observation.activeSeconds).formatted(
            .units(allowed: [.minutes, .seconds], width: .abbreviated))
        )
        .monospacedDigit()
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        HStack(spacing: 7) {
          Button {
            model.openMaterial(observation)
          } label: {
            Image(systemName: "arrow.up.right")
          }
          .help("Open in browser")
          .accessibilityLabel("Open \(observation.title) in browser")
          Button {
            model.copyLink(observation)
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .help("Copy link")
          .accessibilityLabel("Copy link to \(observation.title)")
          if !model.demo {
            Menu {
              if let classification, classification.correction == nil,
                let confidence = classification.confidence
              {
                Text("Jev · \(Int(confidence * 100))% confidence")
                if confidence < 0.6 { Text("Needs review") }
                Divider()
              }
              ForEach(FollowUp.allCases) { choice in
                Button(choice.rawValue) { model.correct(choice, for: observation) }
              }
            } label: {
              Image(systemName: "ellipsis")
            }
            .help("Set a follow-up")
            .accessibilityLabel("Set a follow-up for \(observation.title)")
          }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
      }
    }
    .accessibilityElement(children: .contain)
    .contextMenu {
      Button("Open in browser") { model.openMaterial(observation) }
      Button("Copy link") { model.copyLink(observation) }
      if !model.demo {
        Divider()
        ForEach(FollowUp.allCases) { choice in
          Button(choice.rawValue) { model.correct(choice, for: observation) }
        }
      }
    }
  }

  private var settings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Settings").font(.system(size: 24, weight: .semibold, design: .rounded))
          Text("Capture and classification are separate choices on this Mac.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)

        settingsCard(
          title: "Jev suggestions",
          symbol: "sparkle",
          subtitle: "A provisional follow-up after 10 seconds of active attention."
        ) {
          Toggle(
            "Classify eligible pages with Jev",
            isOn: Binding(get: { model.jevEnabled }, set: { model.setJevEnabled($0) })
          )
          .disabled(!model.hasJevKey)
          Text(
            "When enabled, Zevra fetches a public page excerpt and sends its title, domain and excerpt to TypeSafe. Private or excluded pages stay out. No old visits are sent when you turn it on."
          )
          .font(.caption).foregroundStyle(.secondary)
          Divider()
          HStack {
            Label(
              model.hasJevKey ? "TypeSafe key saved in Keychain" : "No TypeSafe key saved",
              systemImage: model.hasJevKey ? "key.fill" : "key"
            )
            .font(.subheadline)
            Spacer()
            if model.hasJevKey {
              Button("Remove key") { model.removeJevKey() }
            }
          }
          HStack {
            SecureField("Paste TypeSafe API key", text: $pendingKey)
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("TypeSafe API key")
            Button(model.hasJevKey ? "Replace key" : "Save key") {
              model.saveJevKey(pendingKey)
              pendingKey = ""
            }
            .disabled(pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          Text("Suggestions may be uncertain. Your correction always takes precedence.")
            .font(.caption).foregroundStyle(.secondary)
        }

        settingsCard(
          title: "Capture",
          symbol: "record.circle",
          subtitle: "Save eligible Arc page URLs, titles and estimated active time."
        ) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text(model.accessibilityGranted ? "Accessibility enabled" : "Accessibility needed")
                .font(.subheadline.weight(.medium))
              Text("Used to identify the active Arc document.")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant access…") { model.requestAccessibility() }
              .disabled(model.accessibilityGranted)
          }
          Divider()
          Toggle(
            "Launch at login",
            isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
          Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
          Divider()
          Text("Site rules").font(.subheadline.weight(.medium))
          TextField("Allowed domains (optional)", text: $model.allowedDomains)
          TextField("Excluded domains", text: $model.excludedDomains)
          Text("Separate domains with commas. Built-in sensitive-site exclusions always apply.")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Spacer()
            Button("Save site rules") { model.applyRules() }
          }
        }

      }
      .frame(maxWidth: 700)
      .frame(maxWidth: .infinity)
      .padding(24)
    }
  }

  private func settingsCard<Content: View>(
    title: String, symbol: String, subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 17))
          .foregroundStyle(.secondary)
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      Divider()
      content()
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
  }
}
