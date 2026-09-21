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
    .defaultSize(width: 860, height: 700)
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
  @ObservedObject var model: AppModel
  @State private var showSetup = true

  private var isSearching: Bool {
    !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Zevra").font(.system(size: 28, weight: .semibold, design: .rounded))
          Text("A quiet record of what held your attention.")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if model.demo {
          Label("Demo", systemImage: "sparkle").padding(8).background(.quaternary, in: Capsule())
        } else {
          Button(model.capturing ? "Pause capture" : "Start capture") {
            model.setCapture(!model.capturing)
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.storageFailed)
        }
      }

      HStack(spacing: 24) {
        Label(model.status, systemImage: model.capturing ? "circle.fill" : "pause.circle")
        Spacer()
        Label(model.syncStatus, systemImage: "icloud")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(14)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

      if !model.demo {
        DisclosureGroup("Capture settings", isExpanded: $showSetup) {
          VStack(alignment: .leading, spacing: 12) {
            Text(
              "This prototype records Arc page URLs, titles and estimated active time. It does not read page text, record the screen or call AI services."
            )
            .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 5) {
                Label(
                  model.accessibilityGranted
                    ? "Accessibility enabled" : "Accessibility access needed",
                  systemImage: model.accessibilityGranted ? "checkmark.shield" : "hand.raised")
                Text(
                  "macOS grants broad access to app interfaces. Zevra uses it only to identify the active Arc document."
                )
                .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Grant access…") { model.requestAccessibility() }
                .disabled(model.accessibilityGranted)
            }
            HStack {
              Toggle(
                "Launch at login",
                isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
              Spacer()
              Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
              GridRow {
                Text("Allowed domains (optional)")
                TextField("example.com, wikipedia.org", text: $model.allowedDomains)
              }
              GridRow {
                Text("Excluded domains")
                TextField("private.example.com, another.org", text: $model.excludedDomains)
              }
            }
            .textFieldStyle(.roundedBorder)
            HStack {
              Text(
                "Separate domains with commas or spaces. Leave Allowed domains empty to capture all sites except exclusions; add domains to limit capture. Subdomains are included. Built-in exclusions always apply. Save rules to apply changes on this Mac."
              )
              .font(.caption).foregroundStyle(.secondary)
              Spacer()
              Button("Save rules") { model.applyRules() }
            }
          }.padding(.top, 12)
        }
        .disclosureGroupStyle(CaptureSettingsStyle())
      }

      HStack {
        Text("Saved materials").font(.headline)
        Text(
          "\(model.observations.count) \(model.observations.count == 1 ? "visit" : "visits") shown"
        )
        .foregroundStyle(.secondary)
        Spacer()
        Button {
          model.refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search titles or URLs", text: $model.searchText)
          .textFieldStyle(.plain)
          .accessibilityLabel("Search saved materials")
        if !model.searchText.isEmpty {
          Button {
            model.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear search")
          .help("Clear search")
        }
      }
      .padding(10)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      if model.observations.isEmpty {
        ContentUnavailableView(
          isSearching ? "No matching materials" : "No saved materials yet",
          systemImage: isSearching ? "magnifyingglass" : "text.book.closed",
          description: Text(
            isSearching
              ? "Try a different title or URL, or clear the search."
              : "Enable capture and spend a few seconds on an eligible page in Arc. Materials excluded by your site rules are hidden."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(model.observations) { observation in
          HStack(spacing: 16) {
            Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
              Text(observation.title.isEmpty ? "Untitled page" : observation.title)
                .font(.headline).lineLimit(2)
              Text(observation.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .help(observation.url)
              HStack(spacing: 12) {
                Text(observation.deviceID == model.deviceID ? "This Mac" : "Another Mac")
                Text(
                  "Last seen: \(observation.lastSeenAt.formatted(date: .abbreviated, time: .shortened))"
                )
              }.font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
              Text("Active time").font(.caption)
              Text(
                Duration.seconds(observation.activeSeconds).formatted(
                  .units(allowed: [.minutes, .seconds], width: .abbreviated))
              )
              .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            VStack(spacing: 8) {
              Button {
                model.openMaterial(observation)
              } label: {
                Label("Open", systemImage: "arrow.up.right")
              }
              .help("Open in your default browser")
              Button {
                model.copyLink(observation)
              } label: {
                Label("Copy link", systemImage: "doc.on.doc")
              }
              .help("Copy the full URL")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
          .padding(.vertical, 8)
          .accessibilityElement(children: .contain)
          .contextMenu {
            Button("Open in browser") { model.openMaterial(observation) }
            Button("Copy link") { model.copyLink(observation) }
          }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      if model.hasMoreObservations {
        Button("Load more") { model.loadMore() }
          .frame(maxWidth: .infinity)
      }
      Text(
        model.demo
          ? "Sample observations from two fictional Macs. Capture, iCloud and launch at login are disabled."
          : "Active time is estimated from consecutive samples. Split views and unreadable documents are skipped. Summaries are not part of this prototype."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(minWidth: 740, minHeight: 650)
    .alert(
      "Zevra",
      isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    ) {
      Button("OK") { model.notice = nil }
    } message: {
      Text(model.notice ?? "")
    }
  }
}

private struct CaptureSettingsStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        configuration.isExpanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
          configuration.label
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
      if configuration.isExpanded { configuration.content }
    }
  }
}
