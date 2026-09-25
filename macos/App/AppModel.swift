import AppKit
import ApplicationServices
import AttentionCore
import CloudKit
import Combine
import CoreData
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var observations: [Observation] = []
  @Published private(set) var hasMoreObservations = false
  @Published var searchText = "" {
    didSet {
      visibleLimit = 100
      refresh()
    }
  }
  @Published private(set) var capturing = false
  @Published private(set) var status = "Capture is paused"
  @Published private(set) var syncStatus = "Local build · iCloud not configured"
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var loginEnabled = false
  @Published private(set) var loginStatus = "Launch at login is off"
  @Published private(set) var storageFailed = false
  @Published var allowedDomains = ""
  @Published var excludedDomains = ""
  @Published var notice: String?
  @Published private(set) var jevEnabled = false
  @Published private(set) var hasJevKey = false
  @Published private(set) var classifications: [String: ClassificationRecord] = [:]
  @Published private(set) var personalProfile = PersonalProfile()
  @Published private(set) var personalEvaluations: [String: PersonalEvaluation] = [:]
  @Published private(set) var importingArchive = false

  @Published var importDraft: ImportDraft?
  @Published private(set) var analyzingImport = false
  @Published private(set) var hasOpenAIKey = false
  @Published var importError: String?
  private var importAnalysis: Task<Void, Never>?

  let demo: Bool
  let deviceID: String
  private var store: ObservationStore?
  private var classificationStore: ClassificationStore?
  private var personalProfileStore: PersonalProfileStore?
  private var personalEvaluationStore: PersonalEvaluationStore?
  private var classificationTasks: [String: Task<Void, Never>] = [:]
  private var classificationTaskIDs: [String: UUID] = [:]
  private var personalTasks: [String: Task<Void, Never>] = [:]
  private var personalTaskIDs: [String: UUID] = [:]
  private var tracker: AttentionTracker
  private var polling: Task<Void, Never>?
  private var subscriptions: [NSObjectProtocol] = []
  private var activity = ActivityGate()
  private var cloudContainer: String?
  private var policy = CapturePolicy()
  private var visibleLimit = 100
  private let defaults = UserDefaults.standard

  private var viewingPolicy: CapturePolicy {
    var value = policy
    value.enabled = true
    return value
  }

  init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
    self.demo = demo
    deviceID = demo ? "demo-mac" : defaults.string(forKey: "deviceID") ?? UUID().uuidString
    tracker = AttentionTracker(deviceID: deviceID)
    if !demo {
      defaults.set(deviceID, forKey: "deviceID")
      allowedDomains = defaults.string(forKey: "allowedDomains") ?? ""
      excludedDomains = defaults.string(forKey: "excludedDomains") ?? ""
      policy = CapturePolicy(
        allowedDomains: CapturePolicy.domains(from: allowedDomains),
        excludedDomains: CapturePolicy.domains(from: excludedDomains))
      if Bundle.main.object(forInfoDictionaryKey: "AttentionCloudEnabled") as? String == "YES" {
        cloudContainer =
          Bundle.main.object(forInfoDictionaryKey: "AttentionCloudContainer") as? String
      }
    }
    do {
      let url =
        demo
        ? nil
        : try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("com.jamatyka.AttentionLog/observations.sqlite")
      store = try ObservationStore(url: url, cloudContainer: cloudContainer)
      let classificationURL = url?.deletingLastPathComponent().appendingPathComponent(
        "classifications.json")
      do {
        classificationStore = try ClassificationStore(url: classificationURL)
        classifications = classificationStore?.records ?? [:]
      } catch {
        notice = "Saved suggestions could not be read. Jev is paused until this is resolved."
      }
      do {
        let base = url?.deletingLastPathComponent()
        personalProfileStore = try PersonalProfileStore(
          url: base?.appendingPathComponent("personal-profile.json"))
        personalEvaluationStore = try PersonalEvaluationStore(
          url: base?.appendingPathComponent("personal-evaluations.json"))
        personalProfile = personalProfileStore?.profile ?? PersonalProfile()
        personalEvaluations = personalEvaluationStore?.records ?? [:]
      } catch {
        notice = "Personal profile could not be read. Personal evaluation is paused."
      }
      if demo { try loadDemo() }
      refresh()
    } catch {
      storageFailed = true
      status = "Storage unavailable · capture stopped"
      notice = "The local database could not be opened. Existing data has not been replaced."
    }
    guard !demo else {
      syncStatus = "Demo · synthetic data only"
      return
    }
    subscribe()
    hasJevKey = APIKeyCredential.jev.load() != nil
    hasOpenAIKey = APIKeyCredential.openAI.load() != nil
    jevEnabled = defaults.bool(forKey: "jevEnabled") && classificationStore != nil && hasJevKey
    refreshPermissions()
    if cloudContainer != nil {
      syncStatus = "iCloud configured · waiting for sync"
      NSApplication.shared.registerForRemoteNotifications()
      checkCloudAccount()
    }
    // Startup restores only this installation's explicit opt-in, never another Mac's.
    if defaults.bool(forKey: "captureEnabled"), !storageFailed { setCapture(true) }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { break }
        self?.tick()
      }
    }
  }

  func applyRules() {
    guard !demo else { return }
    guard CapturePolicy.invalidDomains(from: allowedDomains).isEmpty,
      CapturePolicy.invalidDomains(from: excludedDomains).isEmpty
    else {
      notice =
        "Use domain names such as example.com, separated by commas or spaces. Remove URLs and wildcards. Your saved rules have not changed."
      return
    }
    allowedDomains = CapturePolicy.domains(from: allowedDomains).joined(separator: ", ")
    excludedDomains = CapturePolicy.domains(from: excludedDomains).joined(separator: ", ")
    defaults.set(allowedDomains, forKey: "allowedDomains")
    defaults.set(excludedDomains, forKey: "excludedDomains")
    policy = CapturePolicy(
      enabled: capturing, allowedDomains: CapturePolicy.domains(from: allowedDomains),
      excludedDomains: CapturePolicy.domains(from: excludedDomains))
    tracker.reset()
    for task in classificationTasks.values { task.cancel() }
    classificationTasks.removeAll()
    classificationTaskIDs.removeAll()
    for task in personalTasks.values { task.cancel() }
    personalTasks.removeAll()
    personalTaskIDs.removeAll()
    refresh()
    notice = "Rules saved on this Mac. Existing records are retained; excluded pages are hidden."
  }

  func setCapture(_ enabled: Bool) {
    guard !demo else { return }
    guard !enabled || (!storageFailed && store != nil) else { return }
    let savedAllowed = CapturePolicy.domains(from: defaults.string(forKey: "allowedDomains") ?? "")
    let savedExcluded = CapturePolicy.domains(
      from: defaults.string(forKey: "excludedDomains") ?? "")
    capturing = enabled
    defaults.set(enabled, forKey: "captureEnabled")
    policy = CapturePolicy(
      enabled: enabled, allowedDomains: savedAllowed, excludedDomains: savedExcluded)
    tracker.reset()
    if !enabled {
      for task in classificationTasks.values { task.cancel() }
      classificationTasks.removeAll()
      classificationTaskIDs.removeAll()
      for task in personalTasks.values { task.cancel() }
      personalTasks.removeAll()
      personalTaskIDs.removeAll()
    }
    status = enabled ? "Waiting for an eligible Arc page" : "Capture is paused"
  }

  func setJevEnabled(_ enabled: Bool) {
    guard !demo else { return }
    if enabled && (classificationStore == nil || !hasJevKey) {
      notice = "Add your TypeSafe API key before enabling Jev."
      return
    }
    jevEnabled = enabled
    defaults.set(enabled, forKey: "jevEnabled")
    if !enabled {
      for task in classificationTasks.values { task.cancel() }
      classificationTasks.removeAll()
      classificationTaskIDs.removeAll()
      for task in personalTasks.values { task.cancel() }
      personalTasks.removeAll()
      personalTaskIDs.removeAll()
      if personalProfile.evaluationEnabled { setPersonalEvaluation(false) }
    }
  }

  func saveGoals(_ text: String) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.goals = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    updateProfile(updated, using: personalProfileStore)
  }

  func rate(_ item: ArchiveItem, as rating: MaterialRating) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.ratings[item.id] = rating
    updateProfile(updated, using: personalProfileStore)
  }

  func clearRating(_ item: ArchiveItem) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.ratings[item.id] = nil
    updateProfile(updated, using: personalProfileStore)
  }

  func addInterest(_ interest: String) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    let cleaned = String(interest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    guard !cleaned.isEmpty, updated.interests.count < 20,
      !updated.interests.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
    else { return }
    updated.interests.append(cleaned)
    updateProfile(updated, using: personalProfileStore)
  }

  func removeInterest(_ interest: String) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.interests.removeAll { $0 == interest }
    updateProfile(updated, using: personalProfileStore)
  }

  func removeArchiveItem(_ item: ArchiveItem) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.items.removeAll { $0.id == item.id }
    updated.ratings[item.id] = nil
    updateProfile(updated, using: personalProfileStore)
  }

  func rateObservation(_ observation: Observation, as rating: MaterialRating) {
    guard !demo, let personalProfileStore,
      viewingPolicy.acceptedURL(observation.url) == observation.url
    else { return }
    let item = ArchiveItem(title: observation.title, source: .other, identity: observation.url)
    var updated = personalProfile
    if !updated.items.contains(where: { $0.id == item.id }) { updated.items.append(item) }
    updated.ratings[item.id] = rating
    updated.pageRatings[observation.url] = rating
    updateProfile(updated, using: personalProfileStore)
  }

  func personalRating(for observation: Observation) -> MaterialRating? {
    personalProfile.pageRatings[observation.url]
  }

  func clearPersonalRating(for observation: Observation) {
    guard !demo, let personalProfileStore else { return }
    var updated = personalProfile
    updated.pageRatings[observation.url] = nil
    let item = ArchiveItem(title: observation.title, source: .other, identity: observation.url)
    updated.ratings[item.id] = nil
    updateProfile(updated, using: personalProfileStore)
  }

  func importArchive(_ selection: URL, base: URL? = nil, viewName: String? = nil) {
    guard !demo, !importingArchive, personalProfileStore != nil else { return }
    importingArchive = true
    Task {
      defer { importingArchive = false }
      do {
        let imported = try await Task.detached(priority: .userInitiated) {
          let scoped = selection.startAccessingSecurityScopedResource()
          let baseScoped = base?.startAccessingSecurityScopedResource() == true
          defer {
            if scoped { selection.stopAccessingSecurityScopedResource() }
            if baseScoped { base?.stopAccessingSecurityScopedResource() }
          }
          return try ArchiveImporter.read(selection: selection, base: base, viewName: viewName)
        }.value
        guard !imported.isEmpty else {
          notice = "No candidate materials found in this source."
          return
        }
        importError = nil
        importDraft = ImportDraft(candidates: imported)
      } catch let error as ArchiveImporter.ImportError {
        notice = error.localizedDescription
      } catch {
        notice =
          "Could not read the selected archive or Base. Check file access and try again. Nothing was imported."
      }
    }
  }

  func saveOpenAIKey(_ value: String) {
    guard !demo else { return }
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else {
      importError = "Enter a valid OpenAI API key."
      return
    }
    if APIKeyCredential.openAI.save(key) {
      hasOpenAIKey = true
      importError = nil
    } else {
      importError = "Could not save the OpenAI key in this Mac's Keychain."
    }
  }

  func removeOpenAIKey() {
    guard !demo else { return }
    importAnalysis?.cancel()
    importAnalysis = nil
    analyzingImport = false
    APIKeyCredential.openAI.remove()
    hasOpenAIKey = APIKeyCredential.openAI.load() != nil
    if hasOpenAIKey { importError = "Could not remove the OpenAI key. Try again." }
  }

  func analyzeImport() {
    guard !demo, !analyzingImport, let draft = importDraft else { return }
    guard let key = APIKeyCredential.openAI.load() else {
      importError = ModelImport.Failure.missingKey.localizedDescription
      return
    }
    do {
      let candidates = try draft.selectedMaterials(policy: viewingPolicy)
      importError = nil
      analyzingImport = true
      importAnalysis = Task {
        do {
          let result = try await ModelImport.analyze(candidates: candidates, apiKey: key)
          guard !Task.isCancelled, importDraft?.id == draft.id else { return }
          var reviewed = draft
          let analyzed = Dictionary(uniqueKeysWithValues: result.materials.map { ($0.id, $0) })
          reviewed.materials = draft.materials.map { analyzed[$0.id] ?? $0 }
          reviewed.interests = result.interests
          reviewed.intentions = result.intentions
          reviewed.modelGenerated = true
          importDraft = reviewed
        } catch {
          guard !Task.isCancelled, importDraft?.id == draft.id else { return }
          importError = error.localizedDescription
        }
        analyzingImport = false
        importAnalysis = nil
      }
    } catch { importError = error.localizedDescription }
  }

  func cancelImport() {
    importAnalysis?.cancel()
    importAnalysis = nil
    analyzingImport = false
    importDraft = nil
    importError = nil
  }

  func saveReviewedImport() {
    guard !analyzingImport, let draft = importDraft, let personalProfileStore else { return }
    do {
      let updated = try draft.applying(to: personalProfile, policy: viewingPolicy)
      guard updated.revision != personalProfile.revision else {
        cancelImport()
        return
      }
      if updateProfile(updated, using: personalProfileStore) {
        cancelImport()
        notice =
          demo
          ? "Demo: approved results saved in memory only."
          : "Approved materials and profile changes saved on this Mac."
      } else {
        importError = "Could not save the profile. Your draft is still available; try again."
        notice = nil
      }
    } catch { importError = error.localizedDescription }
  }

  func previewImportDemo() {
    guard demo else { return }
    var draft = ImportDraft(candidates: [
      ArchiveItem(title: "A practical guide to compiler design", source: .obsidian),
      ArchiveItem(title: "Building a local-first reading archive", source: .youtube),
    ])
    draft.materials[0].topic = "Compilers"
    draft.materials[0].link = "https://example.com/compilers"
    draft.interests = [
      ImportSuggestion(text: "Compiler design", sourceIDs: [draft.materials[0].id])
    ]
    draft.intentions = [
      ImportSuggestion(text: "Learn how parsers work", sourceIDs: [draft.materials[0].id])
    ]
    draft.modelGenerated = true
    importDraft = draft
  }

  func setPersonalEvaluation(_ enabled: Bool) {
    guard !demo, let personalProfileStore else { return }
    guard !enabled || (jevEnabled && hasJevKey && personalProfile.readyForWorthJudgment) else {
      notice =
        "Add current goals and rate at least two worthwhile and two not worthwhile examples first."
      return
    }
    var updated = personalProfile
    updated.evaluationEnabled = enabled
    updateProfile(updated, using: personalProfileStore)
  }

  @discardableResult
  private func updateProfile(_ updated: PersonalProfile, using store: PersonalProfileStore) -> Bool
  {
    do {
      try store.update(updated)
      personalProfile = updated
      for task in personalTasks.values { task.cancel() }
      personalTasks.removeAll()
      personalTaskIDs.removeAll()
      return true
    } catch {
      notice = "Could not save the personal profile. Previous data is unchanged."
      return false
    }
  }

  func saveJevKey(_ value: String) {
    guard !demo else { return }
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      notice = "Enter a TypeSafe API key."
      return
    }
    if APIKeyCredential.jev.save(key) {
      for task in classificationTasks.values { task.cancel() }
      classificationTasks.removeAll()
      classificationTaskIDs.removeAll()
      hasJevKey = true
      notice =
        jevEnabled
        ? "TypeSafe key updated in this Mac's Keychain."
        : "TypeSafe key saved in this Mac's Keychain. Jev is still off until enabled."
    } else {
      notice = "The key could not be saved in Keychain. Jev remains unavailable."
    }
  }

  func removeJevKey() {
    setJevEnabled(false)
    APIKeyCredential.jev.remove()
    hasJevKey = false
  }

  func correct(_ choice: FollowUp, for observation: Observation) {
    guard !demo, let classificationStore else { return }
    let pageURL = observation.url
    var record =
      classifications[pageURL]
      ?? ClassificationRecord(
        title: observation.title, fingerprint: nil, suggestion: nil, confidence: nil,
        correction: nil, status: "Your choice", checkedAt: Date(), attemptCount: 0)
    record.correction = choice
    do {
      try classificationStore.update(record, for: pageURL)
      classifications = classificationStore.records
    } catch {
      notice = "Could not save your correction. Please try again."
    }
  }

  func requestAccessibility() {
    guard !demo else { return }
    // The UI explains the scope before this user-initiated system prompt.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refreshPermissions()
  }

  func setLogin(_ enabled: Bool) {
    guard !demo else { return }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      notice = "Could not change launch at login. Check System Settings → General → Login Items."
    }
    refreshPermissions()
  }

  func refreshPermissions() {
    accessibilityGranted = AXIsProcessTrusted()
    let login = SMAppService.mainApp.status
    loginEnabled = login == .enabled
    loginStatus =
      login == .requiresApproval
      ? "Approve in System Settings → Login Items"
      : (loginEnabled ? "Launch at login is on" : "Launch at login is off")
  }

  func refresh() {
    do {
      let results =
        try store?.recent(
          limit: visibleLimit + 1, search: searchText, policy: viewingPolicy) ?? []
      hasMoreObservations = results.count > visibleLimit
      observations = Array(results.prefix(visibleLimit))
    } catch {
      observations = []
      hasMoreObservations = false
      notice = "Could not read saved materials. Try refreshing or reopening the app."
    }
  }

  func loadMore() {
    visibleLimit += 100
    refresh()
  }

  func openMaterial(_ observation: Observation) {
    guard let url = materialURL(observation) else { return }
    if !NSWorkspace.shared.open(url) {
      notice = "Could not open this link. Check your default browser or copy the link instead."
    }
  }

  func copyLink(_ observation: Observation) {
    guard let url = materialURL(observation) else { return }
    NSPasteboard.general.clearContents()
    if !NSPasteboard.general.setString(url.absoluteString, forType: .string) {
      notice = "Could not copy this link. Try again."
    }
  }

  private func materialURL(_ observation: Observation) -> URL? {
    guard viewingPolicy.acceptedURL(observation.url) != nil,
      let url = URL(string: observation.url)
    else {
      notice = "This link is unavailable under your current site rules."
      return nil
    }
    return url
  }

  private func tick() {
    refreshPermissions()
    guard capturing, !storageFailed else { return }
    guard accessibilityGranted else {
      tracker.reset()
      status = "Accessibility permission needed · capture blocked"
      return
    }
    guard
      activity.permitsCapture(
        idleSeconds: CGEventSource.secondsSinceLastEventType(
          // kCGAnyInputEventType: .null is a specific event, not all input.
          .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!))
    else {
      tracker.reset()
      status = "Idle · time is not counted"
      return
    }
    switch ArcReader().read(policy: policy) {
    case .unavailable(let reason):
      tracker.reset()
      status = reason
    case .page(let page):
      status = "Observing an eligible Arc page"
      if let observation = tracker.sample(
        page, uptime: ProcessInfo.processInfo.systemUptime, date: Date())
      {
        do {
          try store?.save(observation)
          refresh()
          maybeClassify(observation)
          maybeEvaluatePersonally(observation)
        } catch {
          setCapture(false)
          storageFailed = true
          status = "Storage error · capture stopped"
          notice = "Could not save an observation. Capture is paused to avoid silently losing data."
        }
      }
    }
  }

  private func maybeClassify(_ observation: Observation) {
    guard jevEnabled, !personalProfile.evaluationEnabled, let classificationStore,
      policy.acceptedURL(observation.url) == observation.url,
      classificationTasks[observation.url] == nil,
      (try? store?.activeSeconds(for: observation.url)) ?? 0 >= 10
    else { return }
    let pageURL = observation.url
    let previous = classificationStore.record(for: pageURL)
    if let previous {
      if previous.correction != nil { return }
      if previous.suggestion != nil && previous.title == observation.title
        && Date().timeIntervalSince(previous.checkedAt) < 3600
      {
        return
      }
      if previous.suggestion == nil && previous.title == observation.title
        && (previous.attemptCount >= 3 || Date().timeIntervalSince(previous.checkedAt) < 300)
      {
        return
      }
    }
    guard let key = APIKeyCredential.jev.load() else {
      hasJevKey = false
      setJevEnabled(false)
      return
    }
    let title = observation.title
    let currentPolicy = policy
    let taskID = UUID()
    classificationTaskIDs[pageURL] = taskID
    classificationTasks[pageURL] = Task { [weak self] in
      defer {
        if self?.classificationTaskIDs[pageURL] == taskID {
          self?.classificationTasks[pageURL] = nil
          self?.classificationTaskIDs[pageURL] = nil
        }
      }
      do {
        let evidence = try await JevService.evidence(
          pageURL: pageURL, title: title, policy: currentPolicy)
        guard !Task.isCancelled, let self, self.jevEnabled,
          self.policy.acceptedURL(pageURL) == pageURL,
          classificationStore.record(for: pageURL)?.correction == nil
        else { return }
        if previous?.fingerprint == evidence.fingerprint {
          if var unchanged = classificationStore.record(for: pageURL) {
            unchanged.checkedAt = Date()
            if unchanged.suggestion != nil {
              unchanged.status =
                (unchanged.confidence ?? 0) < 0.6
                ? "Needs review" : "Jev suggestion"
            }
            try classificationStore.update(unchanged, for: pageURL)
            self.classifications = classificationStore.records
          }
          return
        }
        let (suggestion, confidence) = try await JevService.classify(evidence, key: key)
        guard !Task.isCancelled, self.jevEnabled,
          self.policy.acceptedURL(pageURL) == pageURL
        else { return }
        let correction = classificationStore.record(for: pageURL)?.correction
        let result = ClassificationRecord(
          title: title, fingerprint: evidence.fingerprint, suggestion: suggestion,
          confidence: confidence, correction: correction,
          status: confidence < 0.6 ? "Needs review" : "Jev suggestion",
          checkedAt: Date(), attemptCount: 0)
        try classificationStore.update(result, for: pageURL)
        self.classifications = classificationStore.records
      } catch {
        guard !Task.isCancelled, let self, self.jevEnabled,
          self.policy.acceptedURL(pageURL) == pageURL
        else { return }
        let existing = classificationStore.record(for: pageURL)
        let status: String
        if case JevService.Failure.noPublicExcerpt = error {
          status = "No public excerpt"
        } else {
          status = "Jev unavailable"
        }
        let result = ClassificationRecord(
          title: title, fingerprint: existing?.fingerprint,
          suggestion: existing?.suggestion, confidence: existing?.confidence,
          correction: existing?.correction, status: status, checkedAt: Date(),
          attemptCount: (existing?.title == title ? existing?.attemptCount ?? 0 : 0) + 1)
        do {
          try classificationStore.update(result, for: pageURL)
          self.classifications = classificationStore.records
        } catch {
          self.notice = "Could not save a Jev result. Saved visits are unaffected."
        }
      }
    }
  }

  private func maybeEvaluatePersonally(_ observation: Observation) {
    guard jevEnabled, personalProfile.evaluationEnabled,
      personalProfile.readyForWorthJudgment, let personalEvaluationStore,
      personalProfile.pageRatings[observation.url] == nil,
      policy.acceptedURL(observation.url) == observation.url,
      personalTasks[observation.url] == nil,
      (try? store?.activeSeconds(for: observation.url)) ?? 0 >= 10,
      let key = APIKeyCredential.jev.load()
    else { return }
    let pageURL = observation.url
    let profile = personalProfile
    let previous = personalEvaluationStore.record(for: pageURL)
    if let previous, previous.title == observation.title {
      if previous.profileRevision == profile.revision, previous.ready,
        ["Personal evaluation", "Needs review"].contains(previous.status),
        Date().timeIntervalSince(previous.checkedAt) < 3600
      {
        return
      }
      if previous.lastAttemptedRevision == profile.revision,
        previous.attemptCount >= 3
          || Date().timeIntervalSince(previous.checkedAt) < 300
      {
        return
      }
    }
    let policy = self.policy
    let title = observation.title
    let taskID = UUID()
    personalTaskIDs[pageURL] = taskID
    personalTasks[pageURL] = Task { [weak self] in
      defer {
        if self?.personalTaskIDs[pageURL] == taskID {
          self?.personalTasks[pageURL] = nil
          self?.personalTaskIDs[pageURL] = nil
        }
      }
      do {
        let evidence = try await JevService.evidence(
          pageURL: pageURL, title: title, policy: policy)
        guard !Task.isCancelled, let self, self.jevEnabled,
          self.personalProfile.evaluationEnabled,
          self.personalProfile.revision == profile.revision,
          self.policy.acceptedURL(pageURL) == pageURL
        else { return }
        if previous?.evidenceFingerprint == evidence.fingerprint,
          previous?.profileRevision == profile.revision, var unchanged = previous,
          unchanged.ready, ["Personal evaluation", "Needs review"].contains(unchanged.status)
        {
          unchanged.checkedAt = Date()
          try personalEvaluationStore.update(unchanged, for: pageURL)
          self.personalEvaluations = personalEvaluationStore.records
          return
        }
        let result = try await PersonalJevService.evaluate(
          evidence: evidence, profile: profile, key: key)
        guard !Task.isCancelled, self.jevEnabled,
          self.personalProfile.evaluationEnabled,
          self.personalProfile.revision == profile.revision,
          self.policy.acceptedURL(pageURL) == pageURL
        else { return }
        try personalEvaluationStore.update(result, for: pageURL)
        self.personalEvaluations = personalEvaluationStore.records
      } catch {
        guard !Task.isCancelled, let self, self.jevEnabled,
          self.personalProfile.evaluationEnabled,
          self.personalProfile.revision == profile.revision,
          self.policy.acceptedURL(pageURL) == pageURL
        else { return }
        let status: String
        if case JevService.Failure.noPublicExcerpt = error {
          status = "No public excerpt"
        } else {
          status = "Personal evaluation unavailable"
        }
        var result =
          previous
          ?? PersonalEvaluation(
            title: title, evidenceFingerprint: nil, profileRevision: profile.revision,
            worth: nil, interestFit: nil, goalFit: nil, confidence: nil, basis: nil,
            status: status, checkedAt: Date(), attemptCount: 0)
        result.status = status
        result.checkedAt = Date()
        result.attemptCount =
          (previous?.lastAttemptedRevision == profile.revision ? previous?.attemptCount ?? 0 : 0)
          + 1
        result.lastAttemptedRevision = profile.revision
        do {
          try personalEvaluationStore.update(result, for: pageURL)
          self.personalEvaluations = personalEvaluationStore.records
        } catch {
          self.notice = "Could not save a personal evaluation. Saved visits are unaffected."
        }
      }
    }
  }

  private func subscribe() {
    let workspace = NSWorkspace.shared.notificationCenter
    enum ActivitySource: Sendable { case system, screen, session }
    let activityChanges: [(Notification.Name, ActivitySource, Bool)] = [
      (NSWorkspace.willSleepNotification, .system, false),
      (NSWorkspace.didWakeNotification, .system, true),
      (NSWorkspace.screensDidSleepNotification, .screen, false),
      (NSWorkspace.screensDidWakeNotification, .screen, true),
      (NSWorkspace.sessionDidResignActiveNotification, .session, false),
      (NSWorkspace.sessionDidBecomeActiveNotification, .session, true),
    ]
    for (name, source, value) in activityChanges {
      subscriptions.append(
        workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            switch source {
            case .system: self?.activity.awake = value
            case .screen: self?.activity.screenAwake = value
            case .session: self?.activity.sessionActive = value
            }
            self?.tracker.reset()
          }
        })
    }
    subscriptions.append(
      workspace.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.tracker.reset() }
      })
    subscriptions.append(
      NotificationCenter.default.addObserver(
        forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      })
    subscriptions.append(
      NotificationCenter.default.addObserver(
        forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard
          let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event
        else { return }
        let finished = event.endDate != nil
        let succeeded = event.succeeded
        let kind = event.type == .import ? "Download" : event.type == .export ? "Upload" : "Setup"
        Task { @MainActor in
          self?.syncStatus =
            finished
            ? (succeeded
              ? "iCloud · \(kind) completed" : "iCloud · \(kind) failed; local data retained")
            : "iCloud · \(kind) in progress"
          if finished && succeeded { self?.refresh() }
        }
      })
  }

  private func checkCloudAccount() {
    guard let cloudContainer else { return }
    Task {
      do {
        let status = try await CKContainer(identifier: cloudContainer).accountStatus()
        if status != .available {
          syncStatus = "iCloud unavailable · sign in or check account access"
        }
      } catch { syncStatus = "iCloud account check failed · local data retained" }
    }
  }

  private func loadDemo() throws {
    let examples = [
      (
        "Designing software that stays out of your way", "https://example.com/quiet-software",
        420.0, "demo-mac"
      ),
      ("A field guide to attention", "https://example.org/attention", 185.0, "second-demo-mac"),
      ("Notes on local-first applications", "https://example.net/local-first", 92.0, "demo-mac"),
    ]
    for (index, example) in examples.enumerated() {
      try store?.save(
        Observation(
          id: UUID(), deviceID: example.3, url: example.1, title: example.0,
          startedAt: Date().addingTimeInterval(-Double(index + 1) * 600),
          lastSeenAt: Date().addingTimeInterval(-Double(index) * 600), activeSeconds: example.2))
    }
    try classificationStore?.update(
      ClassificationRecord(
        title: examples[0].0, fingerprint: "demo", suggestion: .read, confidence: 0.82,
        correction: nil, status: "Jev suggestion", checkedAt: Date(), attemptCount: 0),
      for: examples[0].1)
    try classificationStore?.update(
      ClassificationRecord(
        title: examples[1].0, fingerprint: "demo", suggestion: .keep, confidence: 0.51,
        correction: nil, status: "Needs review", checkedAt: Date(), attemptCount: 0),
      for: examples[1].1)
    classifications = classificationStore?.records ?? [:]
    let demoItems = [
      ArchiveItem(title: "A practical guide to compiler architecture", source: .obsidian),
      ArchiveItem(title: "Building a small language from scratch", source: .youtube),
      ArchiveItem(title: "Another productivity app to try", source: .x),
      ArchiveItem(title: "Generic list of best developer tools", source: .x),
    ]
    let demoRatings = Dictionary(
      uniqueKeysWithValues: zip(
        demoItems.map(\.id),
        [MaterialRating.worthwhile, .worthwhile, .notWorthwhile, .notWorthwhile]))
    let demoProfile = PersonalProfile(
      goals: "Understand compiler design well enough to build a small language",
      interests: ["Compiler design", "Local-first software"],
      items: demoItems, ratings: demoRatings, evaluationEnabled: true)
    try personalProfileStore?.update(demoProfile)
    personalProfile = demoProfile
    try personalEvaluationStore?.update(
      PersonalEvaluation(
        title: examples[0].0, evidenceFingerprint: "demo", profileRevision: demoProfile.revision,
        worth: 3.3, interestFit: 3.6, goalFit: 3.1, confidence: 0.77,
        basis: .both, status: "Personal evaluation", checkedAt: Date(), attemptCount: 0),
      for: examples[0].1)
    personalEvaluations = personalEvaluationStore?.records ?? [:]
    status = "Demo · capture is disabled"
  }
}
