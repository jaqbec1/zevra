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

  let demo: Bool
  let deviceID: String
  private var store: ObservationStore?
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
    status = enabled ? "Waiting for an eligible Arc page" : "Capture is paused"
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
        } catch {
          setCapture(false)
          storageFailed = true
          status = "Storage error · capture stopped"
          notice = "Could not save an observation. Capture is paused to avoid silently losing data."
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
    status = "Demo · capture is disabled"
  }
}
