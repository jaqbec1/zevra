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
    .defaultSize(width: 1060, height: 760)
    #if ZEVRA_IMPORT_PREVIEW
      .commands {
        CommandMenu("Preview") {
          Button("Light appearance") { NSApp.appearance = NSAppearance(named: .aqua) }
          Button("Dark appearance") { NSApp.appearance = NSAppearance(named: .darkAqua) }
          Button("High contrast light") {
            NSApp.appearance = NSAppearance(named: .accessibilityHighContrastAqua)
          }
          Button("High contrast dark") {
            NSApp.appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua)
          }
        }
      }
    #endif
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
  private enum Panel: String, CaseIterable, Identifiable {
    case library = "Saved materials"
    case visits = "Browsing history"
    case general = "General"
    case capture = "Capture & privacy"
    case suggestions = "AI suggestions"
    case profile = "Interests & goals"

    var id: String { rawValue }
    var symbol: String {
      switch self {
      case .library: "books.vertical"
      case .visits: "clock"
      case .general: "gearshape"
      case .capture: "hand.raised"
      case .suggestions: "sparkles"
      case .profile: "person.crop.circle"
      }
    }

    var summary: String {
      switch self {
      case .library: "Imported notes, bookmarks and pages you have rated."
      case .visits: "Pages recorded automatically while you use Arc."
      case .general: "App startup and storage on this Mac."
      case .capture: "Choose which browsing activity Zevra can record."
      case .suggestions: "Control when AI is used and what it receives."
      case .profile: "Tell personal evaluation what matters to you now."
      }
    }
  }

  @ObservedObject var model: AppModel
  @State private var panel: Panel? = .library
  @State private var pendingKey = ""
  @State private var goalsDraft = ""
  @State private var interestDraft = ""

  private var isSearching: Bool {
    !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.green.gradient, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
          Text("Zevra").font(.title2.weight(.semibold))
          if model.demo { Text("Preview").font(.caption).foregroundStyle(ZevraStyle.secondaryText) }
        }
        .padding(16)
        List(selection: $panel) {
          Section {
            navigationItem(.library)
            navigationItem(.visits)
          } header: {
            Text("Your content").foregroundStyle(ZevraStyle.secondaryText)
          }
          Section {
            navigationItem(.general)
            navigationItem(.capture)
            navigationItem(.suggestions)
            navigationItem(.profile)
          } header: {
            Text("Settings").foregroundStyle(ZevraStyle.secondaryText)
          }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Main navigation")
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          Label(model.status, systemImage: captureSymbol)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
          if !model.demo {
            Button {
              model.setCapture(!model.capturing)
            } label: {
              Label(
                model.capturing ? "Pause capture" : "Resume capture",
                systemImage: model.capturing ? "pause" : "play")
            }
            .disabled(model.storageFailed)
            .buttonStyle(.bordered)
          }
        }
        .padding(16)
      }
      .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 270)
    } detail: {
      switch panel ?? .library {
      case .library:
        ImportedLibraryView(model: model, chooseSource: chooseSource, chooseBase: chooseBase)
      case .visits:
        library
      case .general, .capture, .suggestions, .profile:
        settings
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 860, minHeight: 600)
    .modifier(ZevraWindowSurface())
    .tint(.primary)
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
            get: { model.importDraft ?? presentedDraft },
            set: { value in
              guard model.importDraft?.id == presentedDraft.id else { return }
              model.importDraft = value
            }))
      })
  }

  private var captureSymbol: String {
    if model.demo { return "eye" }
    if model.storageFailed || !model.accessibilityGranted { return "exclamationmark.triangle" }
    return model.capturing ? "record.circle" : "pause.circle"
  }

  private func navigationItem(_ item: Panel) -> some View {
    Label(item.rawValue, systemImage: item.symbol)
      .font(.body.weight(panel == item ? .semibold : .regular))
      .padding(.vertical, 5)
      .tag(item)
      .help(item.summary)
  }

  private var library: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Browsing history").font(.title.weight(.semibold))
          Text("Pages recorded automatically while you use Arc.")
            .font(.body).foregroundStyle(ZevraStyle.secondaryText)
          Text(
            "\(model.observations.count) \(model.observations.count == 1 ? "visit" : "visits") shown"
          )
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
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
        Image(systemName: "magnifyingglass").foregroundStyle(ZevraStyle.secondaryText)
        TextField(
          "Search titles or URLs", text: $model.searchText,
          prompt: Text("Search titles or URLs").foregroundStyle(ZevraStyle.secondaryText)
        )
        .textFieldStyle(.plain)
        .accessibilityLabel("Search visits")
        if !model.searchText.isEmpty {
          Button {
            model.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(ZevraStyle.secondaryText)
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
          isSearching ? "No matching visits" : "No visits yet",
          systemImage: isSearching ? "magnifyingglass" : "square.stack",
          description: Text(
            isSearching
              ? "Try a different title or URL."
              : "Spend a few seconds on an eligible page in Arc. Recorded visits appear here. Imported notes and bookmarks live in Saved materials."
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
      .font(.caption)
      .foregroundStyle(ZevraStyle.secondaryText)
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
        .foregroundStyle(ZevraStyle.secondaryText)
        .frame(width: 36, height: 36)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(observation.title.isEmpty ? "Untitled page" : observation.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
        Text(observation.url)
          .font(.caption)
          .foregroundStyle(ZevraStyle.secondaryText)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(observation.url)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "\(observation.deviceID == model.deviceID ? "This Mac" : "Another Mac") · \(observation.lastSeenAt.formatted(date: .abbreviated, time: .shortened))"
          )
          if model.personalProfile.evaluationEnabled,
            let rating = model.personalRating(for: observation)
          {
            Label(
              rating == .worthwhile ? "You · Worth it" : "You · Not worth it",
              systemImage: "checkmark.circle"
            )
            .foregroundStyle(.primary)
          } else if model.personalProfile.evaluationEnabled, let evaluation = personal,
            let worth = evaluation.worth, let interest = evaluation.interestFit,
            let goal = evaluation.goalFit
          {
            Label(
              "Worth now \(worth.formatted(.number.precision(.fractionLength(1))))/4",
              systemImage: "sparkles"
            )
            .foregroundStyle(.primary)
            Text(
              "Interest \(interest.formatted(.number.precision(.fractionLength(1))))/4 · Goals \(goal.formatted(.number.precision(.fractionLength(1))))/4"
            )
            if evaluation.status == "Needs review" {
              Label("Uncertain", systemImage: "questionmark.circle").foregroundStyle(.primary)
            } else if evaluation.status != "Personal evaluation" {
              Text(evaluation.status).foregroundStyle(.primary)
            }
            if !personalIsCurrent { Text("Older profile").foregroundStyle(.primary) }
          } else if model.personalProfile.evaluationEnabled {
            Text(personal?.status ?? "Personal evaluation pending")
          } else if let choice = classification?.displayedChoice {
            Label(
              "\(classification?.correction == nil ? "Jev" : "You") · \(choice.rawValue)",
              systemImage: classification?.correction == nil ? "sparkle" : "checkmark.circle"
            )
            .foregroundStyle(
              classification?.correction == nil ? ZevraStyle.secondaryText : Color.primary)
            if classification?.correction == nil {
              if classification?.status == "Needs review" {
                Label("Needs review", systemImage: "exclamationmark.triangle").foregroundStyle(
                  .primary)
              } else if classification?.status != "Jev suggestion",
                let status = classification?.status
              {
                Text(status)
              }
            }
          } else if let classification {
            Text(classification.status)
          }
        }
        .font(.caption)
        .foregroundStyle(ZevraStyle.secondaryText)
      }
      Spacer(minLength: 12)
      VStack(alignment: .trailing, spacing: 10) {
        Text(
          Duration.seconds(observation.activeSeconds).formatted(
            .units(allowed: [.minutes, .seconds], width: .abbreviated))
        )
        .monospacedDigit()
        .font(.caption.weight(.medium))
        .foregroundStyle(ZevraStyle.secondaryText)
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
    let destination = panel ?? .general
    return ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 6) {
          Text(destination.rawValue).font(.title.weight(.semibold))
          Text(destination.summary).foregroundStyle(ZevraStyle.secondaryText)
        }
        switch destination {
        case .general:
          generalSettings
        case .capture:
          captureSettings
        case .suggestions:
          suggestionSettings
        case .profile:
          profileSettings
        default:
          EmptyView()
        }
      }
      .frame(maxWidth: 700, alignment: .leading)
      .padding(28)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .id(destination)
  }

  private var generalSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      settingsSection("Startup") {
        Toggle(
          "Launch Zevra at login",
          isOn: Binding(
            get: { model.loginEnabled }, set: { model.setLogin($0) })
        )
        .disabled(model.demo)
        Text(model.loginStatus).foregroundStyle(ZevraStyle.secondaryText)
      }
      settingsSection("Storage") {
        Label(model.syncStatus, systemImage: "internaldrive")
        Text("Imported notes, bookmarks and your personal profile are stored on this Mac.")
          .foregroundStyle(ZevraStyle.secondaryText)
      }
    }
  }

  private var captureSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      settingsSection("Arc activity") {
        Toggle(
          "Record browsing activity",
          isOn: Binding(
            get: { model.capturing }, set: { model.setCapture($0) })
        )
        .disabled(model.demo || model.storageFailed)
        Text("Saves page titles, links and estimated active time in Browsing history.")
          .foregroundStyle(ZevraStyle.secondaryText)
        HStack(alignment: .top) {
          Label(
            model.accessibilityGranted ? "Accessibility enabled" : "Accessibility needed",
            systemImage: model.accessibilityGranted
              ? "checkmark.circle" : "exclamationmark.triangle")
          Spacer()
          Button("Grant access…") { model.requestAccessibility() }
            .disabled(model.demo || model.accessibilityGranted)
        }
        Text("Permission is used to identify the active Arc document.")
          .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
      }
      settingsSection("Site exclusions") {
        Text(
          "Excluded sites are not recorded or sent to AI. Existing visits stay on disk but are hidden."
        )
        .foregroundStyle(ZevraStyle.secondaryText)
        VStack(alignment: .leading, spacing: 6) {
          Text("Excluded domains").font(.body.weight(.medium))
          TextField(
            "Excluded domains", text: $model.excludedDomains,
            prompt: Text("example.com, another-site.com").foregroundStyle(ZevraStyle.secondaryText)
          )
          .accessibilityLabel("Excluded domains")
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Only record these domains (optional)").font(.body.weight(.medium))
          TextField(
            "Allowed domains", text: $model.allowedDomains,
            prompt: Text("Leave empty to allow other eligible sites").foregroundStyle(
              ZevraStyle.secondaryText)
          )
          .accessibilityLabel("Allowed domains (optional)")
        }
        Text(
          "Separate domains with commas. Subdomains are included. Built-in sensitive-site exclusions always apply."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        Button("Save site rules") { model.applyRules() }.disabled(model.demo)
      }
    }
    .textFieldStyle(.roundedBorder)
  }

  private var suggestionSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      settingsSection("Browsing suggestions · TypeSafe") {
        Toggle(
          "Classify eligible pages with Jev",
          isOn: Binding(get: { model.jevEnabled }, set: { model.setJevEnabled($0) })
        )
        .disabled(model.demo || !model.hasJevKey)
        Text("Suggestions start after 10 seconds of active attention on an eligible page.")
          .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        Text(
          "When enabled, Zevra fetches a public page excerpt and sends its title, domain and excerpt to TypeSafe. Private or excluded pages stay out. No old visits are sent when you turn it on."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
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
          .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
      }
      settingsSection("Personal evaluation · TypeSafe") {
        Toggle(
          "Evaluate pages personally with Jev",
          isOn: Binding(
            get: { model.personalProfile.evaluationEnabled },
            set: { model.setPersonalEvaluation($0) })
        )
        .disabled(
          model.demo
            || (!model.personalProfile.evaluationEnabled
              && (!model.personalProfile.readyForWorthJudgment || !model.jevEnabled))
        )
        Text(
          "When enabled, Zevra sends a public page excerpt, your saved goals, up to 20 interests you selected and up to 8 examples of each rating to TypeSafe. Unrated archive titles and full notes are not sent to TypeSafe. The result is an estimate, not a measured probability of usefulness."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        if !model.personalProfile.readyForWorthJudgment || !model.jevEnabled {
          Label(
            "Requires Jev, current goals and at least two examples of each rating.",
            systemImage: "info.circle"
          )
          .font(.callout)
        }
        Button("Set interests, goals and examples") { panel = .profile }
      }
      settingsSection("Import analysis · OpenAI") {
        Text(
          "Optional analysis is available when reviewing an import in Saved materials. You choose when to send selected titles and links, then approve the results before saving."
        )
        .foregroundStyle(ZevraStyle.secondaryText)
        Button("Go to saved materials") { panel = .library }
      }
    }
  }

  private var profileSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      settingsSection("Current goals") {
        TextEditor(text: $goalsDraft)
          .frame(minHeight: 76)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .accessibilityLabel("Current goals for personal evaluation")
        HStack {
          Text("Write what matters now. Archived interests are not treated as current goals.")
            .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
          Spacer()
          Button("Save goals") { model.saveGoals(goalsDraft) }
            .disabled(model.demo)
        }

      }
      settingsSection("Interests") {
        Text("Suggested words from titles are unverified. Add only topics that fit you.")
          .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
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
        DisclosureGroup("Suggestions from imported titles") {
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

        }

      }
      settingsSection("Examples for personal evaluation") {
        Text(
          "Rate at least two worthwhile and two not worthwhile examples. You can correct future pages from their menu."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        ForEach(model.personalProfile.calibrationCandidates) { item in
          HStack(spacing: 8) {
            Text(item.title).lineLimit(1).help(item.title)
            Text(item.source.rawValue).font(.callout).foregroundStyle(ZevraStyle.secondaryText)
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
            .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
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
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)

        if model.personalProfile.items.isEmpty {
          Text("Import some materials first, then rate examples you know.")
          Button("Go to saved materials") { panel = .library }
        }
        Button("Configure AI suggestions") { panel = .suggestions }
      }
    }
    .textFieldStyle(.roundedBorder)
  }

  private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline).accessibilityAddTraits(.isHeader)
      Divider()
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func chooseSource() {
    if model.demo {
      model.previewImportDemo()
      return
    }
    let picker = NSOpenPanel()
    picker.canChooseDirectories = true
    picker.canChooseFiles = true
    picker.allowsMultipleSelection = false
    picker.prompt = "Review source"
    if picker.runModal() == .OK, let source = picker.url { model.importArchive(source) }
  }

  private func chooseBase() {
    guard !model.demo else { return }
    let sourcePanel = NSOpenPanel()
    sourcePanel.canChooseDirectories = true
    sourcePanel.canChooseFiles = false
    sourcePanel.allowsMultipleSelection = false
    sourcePanel.message =
      "Choose the notes folder to import from. Only notes inside this folder will be read."
    sourcePanel.prompt = "Choose notes folder"
    guard sourcePanel.runModal() == .OK, let source = sourcePanel.url else { return }
    let basePanel = NSOpenPanel()
    basePanel.canChooseDirectories = false
    basePanel.canChooseFiles = true
    basePanel.allowsMultipleSelection = false
    basePanel.message =
      "Choose a .base file to filter the selected notes folder. Unsupported conditions stop the import."
    basePanel.prompt = "Review filtered notes"
    if basePanel.runModal() == .OK, let base = basePanel.url {
      reviewBase(source: source, base: base)
    }
  }

  private func reviewBase(source: URL, base: URL) {
    let scoped = base.startAccessingSecurityScopedResource()
    defer { if scoped { base.stopAccessingSecurityScopedResource() } }
    do {
      let names = try ArchiveImporter.baseViewNames(at: base)
      guard let first = names.first else { return }
      var selected = first
      if names.count > 1 {
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        picker.addItems(withTitles: names)
        picker.setAccessibilityLabel("Base view")
        if names.contains("All") { picker.selectItem(withTitle: "All") }
        let alert = NSAlert()
        alert.messageText = "Choose Base view"
        alert.informativeText =
          "This view and the Base's global filters select notes from your chosen folder. Unsupported conditions stop the import."
        alert.accessoryView = picker
        alert.addButton(withTitle: "Review notes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
          let name = picker.titleOfSelectedItem
        else { return }
        selected = name
      }
      model.importArchive(source, base: base, viewName: selected)
    } catch let error as ArchiveImporter.ImportError {
      model.notice = error.localizedDescription
    } catch {
      model.notice = "Could not read the selected Base. Check file access and try again."
    }
  }

}

// Opaque neutral text keeps secondary content readable in both appearances.
private struct ZevraWindowSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  private var opaque: Bool { reduceTransparency || contrast == .increased }

  func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      surface(content).containerBackground(.clear, for: .window)
    } else {
      surface(content)
    }
  }

  private func surface(_ content: Content) -> some View {
    content.background {
      WindowMaterial(opaque: opaque)
        .overlay(Color(nsColor: .windowBackgroundColor).opacity(opaque ? 1 : 0.35))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}

private struct WindowMaterial: NSViewRepresentable {
  var opaque: Bool

  func makeNSView(context: Context) -> SurfaceView {
    let view = SurfaceView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    view.opaqueSurface = opaque
    return view
  }

  func updateNSView(_ view: SurfaceView, context: Context) {
    view.opaqueSurface = opaque
  }

  final class SurfaceView: NSVisualEffectView {
    var opaqueSurface = false {
      didSet { configureWindow() }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureWindow()
    }

    private func configureWindow() {
      window?.isOpaque = opaqueSurface
      window?.backgroundColor = opaqueSurface ? .windowBackgroundColor : .clear
    }
  }
}

enum ZevraStyle {
  static let secondaryText = Color(
    nsColor: NSColor(name: nil) { appearance in
      let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(white: dark ? 0.76 : 0.34, alpha: 1)
    })
}
