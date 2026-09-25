import AppKit
import AttentionCore
import SwiftUI

@main
struct AttentionLogApp: App {
  #if ZEVRA_IMPORT_PREVIEW
    @StateObject private var model = AppModel(demo: true)
  #else
    @StateObject private var model = AppModel()
  #endif

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
  @State private var goalsDraft = ""
  @State private var interestDraft = ""

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
    .onAppear { goalsDraft = model.personalProfile.goals }
    .onChange(of: model.personalProfile.goals) { _, value in goalsDraft = value }
    .sheet(
      item: $model.importDraft, onDismiss: { model.cancelImport() },
      content: { presentedDraft in
        ImportReviewView(
          model: model,
          draft: Binding(
            // SwiftUI can read the sheet's binding while dismissal is animating.
            get: { model.importDraft ?? presentedDraft },
            set: { value in
              guard model.importDraft?.id == presentedDraft.id else { return }
              model.importDraft = value
            }))
      })
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
    let personal = model.personalEvaluations[observation.url]
    let personalIsCurrent = personal?.profileRevision == model.personalProfile.revision
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
          if model.personalProfile.evaluationEnabled,
            let rating = model.personalRating(for: observation)
          {
            Text("·")
            Label(
              rating == .worthwhile ? "You · Worth it" : "You · Not worth it",
              systemImage: "checkmark.circle"
            )
            .foregroundStyle(.primary)
          } else if model.personalProfile.evaluationEnabled, let evaluation = personal,
            let worth = evaluation.worth, let interest = evaluation.interestFit,
            let goal = evaluation.goalFit
          {
            Text("·")
            Label(
              "Worth now \(worth.formatted(.number.precision(.fractionLength(1))))/4",
              systemImage: "sparkles"
            )
            .foregroundStyle(worth >= 3 ? .green : worth < 1.5 ? .orange : .secondary)
            Text("Interest \(interest.formatted(.number.precision(.fractionLength(1))))/4")
            Text("Goals \(goal.formatted(.number.precision(.fractionLength(1))))/4")
            if evaluation.status == "Needs review" {
              Text("Uncertain").foregroundStyle(.orange)
            } else if evaluation.status != "Personal evaluation" {
              Text(evaluation.status).foregroundStyle(.orange)
            }
            if !personalIsCurrent { Text("Older profile").foregroundStyle(.orange) }
          } else if model.personalProfile.evaluationEnabled {
            Text("·")
            Text(personal?.status ?? "Personal evaluation pending")
          } else if let choice = classification?.displayedChoice {
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
              if model.personalProfile.evaluationEnabled {
                if let evaluation = personal {
                  Text(evaluation.basis?.explanation ?? evaluation.status)
                  if !personalIsCurrent { Text("Based on an older profile") }
                  if let confidence = evaluation.confidence {
                    Text("Model confidence \(Int(confidence * 100))%")
                  }
                  Divider()
                }
                Button("Worth my time") { model.rateObservation(observation, as: .worthwhile) }
                Button("Not worth my time") {
                  model.rateObservation(observation, as: .notWorthwhile)
                }
                if model.personalRating(for: observation) != nil {
                  Button("Remove my rating") { model.clearPersonalRating(for: observation) }
                }
              } else if let classification, classification.correction == nil,
                let confidence = classification.confidence
              {
                Text("Jev · \(Int(confidence * 100))% confidence")
                if confidence < 0.6 { Text("Needs review") }
                Divider()
              }
              if !model.personalProfile.evaluationEnabled {
                ForEach(FollowUp.allCases) { choice in
                  Button(choice.rawValue) { model.correct(choice, for: observation) }
                }
              }
            } label: {
              Image(systemName: "ellipsis")
            }
            .help(
              model.personalProfile.evaluationEnabled
                ? "Correct personal evaluation" : "Set a follow-up"
            )
            .accessibilityLabel("Correct evaluation for \(observation.title)")
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
        if model.personalProfile.evaluationEnabled {
          Button("Worth my time") { model.rateObservation(observation, as: .worthwhile) }
          Button("Not worth my time") { model.rateObservation(observation, as: .notWorthwhile) }
          if model.personalRating(for: observation) != nil {
            Button("Remove my rating") { model.clearPersonalRating(for: observation) }
          }
        } else {
          ForEach(FollowUp.allCases) { choice in
            Button(choice.rawValue) { model.correct(choice, for: observation) }
          }
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
          title: "Personal evaluation",
          symbol: "person.crop.circle",
          subtitle: "Let Zevra judge whether a page is worth your time now."
        ) {
          Text(
            "Choose a folder or an export. To filter notes with a Base, choose the notes folder first, then the Base. The Base imports matching titles from its All view. Review the selected materials before saving. Optional OpenAI analysis sends only the titles and links shown in the preview. Saved or watched does not mean worthwhile."
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(model.importingArchive ? "Importing…" : "Choose source…") {
              let panel = NSOpenPanel()
              panel.canChooseDirectories = true
              panel.canChooseFiles = true
              panel.allowsMultipleSelection = false
              panel.prompt = "Review source"
              if panel.runModal() == .OK, let selection = panel.url {
                model.importArchive(selection)
              }
            }
            .disabled(model.demo || model.importingArchive)
            Button("Filter notes with Base…") {
              let sourcePanel = NSOpenPanel()
              sourcePanel.canChooseDirectories = true
              sourcePanel.canChooseFiles = false
              sourcePanel.allowsMultipleSelection = false
              sourcePanel.message =
                "Choose the notes folder to import from. Only notes inside this folder will be read."
              sourcePanel.prompt = "Choose notes folder"
              if sourcePanel.runModal() == .OK, let source = sourcePanel.url {
                let basePanel = NSOpenPanel()
                basePanel.canChooseDirectories = false
                basePanel.canChooseFiles = true
                basePanel.allowsMultipleSelection = false
                basePanel.message =
                  "Choose a .base file. Its All view and global filters will apply to the selected notes folder. Unsupported conditions stop the import."
                basePanel.prompt = "Review filtered notes"
                if basePanel.runModal() == .OK, let base = basePanel.url {
                  model.importArchive(source, base: base)
                }
              }
            }
            .disabled(model.demo || model.importingArchive)
            Spacer()
            Text("\(model.personalProfile.items.count) candidate materials")
              .font(.caption).foregroundStyle(.secondary)
          }
          if model.demo {
            Button("Preview import review") { model.previewImportDemo() }
          }
          Text(
            "Obsidian \(model.personalProfile.items.filter { $0.source == .obsidian }.count) · X \(model.personalProfile.items.filter { $0.source == .x }.count) · YouTube \(model.personalProfile.items.filter { $0.source == .youtube }.count) · Books \(model.personalProfile.items.filter { $0.source == .books }.count)"
          )
          .font(.caption2).foregroundStyle(.secondary)
          Divider()
          Text("Interests to use").font(.subheadline.weight(.medium))
          Text("Suggested words from titles are unverified. Add only topics that fit you.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(model.personalProfile.interests, id: \.self) { interest in
            HStack {
              Text(interest)
              Spacer()
              Button("Remove") { model.removeInterest(interest) }
                .disabled(model.demo)
            }
          }
          HStack {
            TextField("Add an interest", text: $interestDraft)
            Button("Add") {
              model.addInterest(interestDraft)
              interestDraft = ""
            }
            .disabled(
              model.demo || interestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(
                model.personalProfile.suggestedTopics.filter {
                  !model.personalProfile.interests.contains($0)
                }, id: \.self
              ) { topic in
                Button("Use \(topic)") { model.addInterest(topic) }
                  .disabled(model.demo)
              }
            }
          }
          Divider()
          Text("Current goals").font(.subheadline.weight(.medium))
          TextEditor(text: $goalsDraft)
            .frame(minHeight: 76)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .accessibilityLabel("Current goals for personal evaluation")
          HStack {
            Text("Write what matters now. Archived interests are not treated as current goals.")
              .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Save goals") { model.saveGoals(goalsDraft) }
              .disabled(model.demo)
          }
          Divider()
          Text("Calibrate with materials you know").font(.subheadline.weight(.medium))
          Text(
            "Rate at least two worthwhile and two not worthwhile examples. You can correct future pages from their menu."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(model.personalProfile.calibrationCandidates) { item in
            HStack(spacing: 8) {
              Text(item.title).lineLimit(1).help(item.title)
              Text(item.source.rawValue).font(.caption2).foregroundStyle(.secondary)
              Spacer(minLength: 8)
              Button("Worth it") { model.rate(item, as: .worthwhile) }
              Button("Not worth it") { model.rate(item, as: .notWorthwhile) }
            }
            .controlSize(.small)
          }
          ForEach(
            model.personalProfile.items.filter {
              $0.source != .other && model.personalProfile.ratings[$0.id] != nil
            }.prefix(10)
          ) { item in
            HStack(spacing: 8) {
              Text(item.title).lineLimit(1).help(item.title)
              Text(
                model.personalProfile.ratings[item.id] == .worthwhile ? "Worth it" : "Not worth it"
              )
              .font(.caption).foregroundStyle(.secondary)
              Spacer(minLength: 8)
              Button("Change") {
                model.rate(
                  item,
                  as: model.personalProfile.ratings[item.id] == .worthwhile
                    ? .notWorthwhile : .worthwhile)
              }
              Button("Undo") { model.clearRating(item) }
            }
            .controlSize(.small)
          }
          Text(
            "Rated: \(model.personalProfile.worthwhileExamples.count) worthwhile · \(model.personalProfile.notWorthwhileExamples.count) not worthwhile"
          )
          .font(.caption).foregroundStyle(.secondary)
          Divider()
          Toggle(
            "Evaluate pages personally with Jev",
            isOn: Binding(
              get: { model.personalProfile.evaluationEnabled },
              set: { model.setPersonalEvaluation($0) })
          )
          .disabled(
            !model.personalProfile.evaluationEnabled
              && (!model.personalProfile.readyForWorthJudgment || !model.jevEnabled))
          Text(
            "When enabled, Zevra sends a public page excerpt, your saved goals, up to 20 interests you selected and up to 8 examples of each rating to TypeSafe. Unrated archive titles and full notes are not sent to TypeSafe. The result is an estimate, not a measured probability of usefulness."
          )
          .font(.caption).foregroundStyle(.secondary)
        }

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
