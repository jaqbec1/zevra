import Foundation

public struct CapturePolicy: Sendable {
  public var enabled: Bool
  public var allowedDomains: [String]
  public var excludedDomains: [String]
  public var excludedKeywords: [String]

  public init(
    enabled: Bool = false, allowedDomains: [String] = [], excludedDomains: [String] = [],
    excludedKeywords: [String] = ["settings", "login", "account"]
  ) {
    self.enabled = enabled
    self.allowedDomains = allowedDomains
    self.excludedDomains = excludedDomains
    self.excludedKeywords = excludedKeywords
  }

  private static let blockedDomains = [
    "localhost", "local", "internal", "lan", "home.arpa", "mail.google.com", "gmail.com",
    "dash.cloudflare.com", "outlook.com", "outlook.office.com", "office.com", "live.com",
    "proton.me", "protonmail.com", "1password.com", "bitwarden.com", "lastpass.com",
    "paypal.com", "stripe.com", "revolut.com", "wise.com", "ing.pl", "mbank.pl",
    "ipko.pl", "pekao24.pl", "santander.pl", "aliorbank.pl", "wakacje.pl", "atlassian.net",
    "figma.com",
  ]

  public static func domains(from text: String) -> [String] {
    domainEntries(from: text).filter(isDomain)
  }

  public static func invalidDomains(from text: String) -> [String] {
    domainEntries(from: text).filter { !isDomain($0) }
  }

  private static func domainEntries(from text: String) -> [String] {
    text.components(
      separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
    )
    .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    .filter { !$0.isEmpty }
  }

  private static func isDomain(_ value: String) -> Bool {
    value.range(
      of: #"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$"#, options: .regularExpression)
      != nil
  }

  public func acceptedURL(_ raw: String) -> String? {
    guard enabled, raw.count <= 8192 else { return nil }
    var decoded = raw
    for index in 0..<8 {
      guard let next = decoded.removingPercentEncoding else { return nil }
      if next == decoded { break }
      guard index < 7 else { return nil }
      decoded = next
    }
    let lower = decoded.lowercased()
    guard !excludedKeywords.contains(where: { !$0.isEmpty && lower.contains($0.lowercased()) }),
      var parts = URLComponents(string: raw),
      ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
      parts.user == nil, parts.password == nil, parts.port == nil,
      let rawHost = parts.host
    else { return nil }
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    // This prototype never collects IP literals, even public ones.
    guard Self.domains(from: host) == [host],
      !(Self.blockedDomains + excludedDomains).contains(where: { Self.matches(host, $0) }),
      allowedDomains.isEmpty || allowedDomains.contains(where: { Self.matches(host, $0) })
    else { return nil }
    let sensitiveRoute =
      #"(^|[./-])(login|signin|oauth|auth|bank|banking|checkout|payments?|jira|mail|webmail)([./-]|$)"#
    guard
      (host + parts.path).range(
        of: sensitiveRoute, options: [.regularExpression, .caseInsensitive]) == nil,
      lower.range(
        of:
          #"(?:[?&#])[^=&#]*(token|secret|password|passwd|session|auth|api.?key|signature|credential|sso|code)[^=&#]*="#,
        options: .regularExpression) == nil
    else { return nil }
    parts.host = host
    parts.scheme = parts.scheme?.lowercased()
    parts.fragment = nil
    let items = (parts.queryItems ?? []).filter {
      !$0.name.lowercased().hasPrefix("utm_")
        && !["fbclid", "gclid", "ref"].contains($0.name.lowercased())
    }.sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
    parts.queryItems = items.isEmpty ? nil : items
    return parts.string
  }

  private static func matches(_ host: String, _ rule: String) -> Bool {
    let domain = rule.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
  }
}

public struct PageIdentity: Equatable, Sendable {
  public let url: String
  public let title: String
  public init(url: String, title: String) {
    self.url = url
    self.title = title
  }
}

public struct ActivityGate: Sendable {
  public var sessionActive = true
  public var awake = true
  public var screenAwake = true
  public init() {}

  public func permitsCapture(idleSeconds: Double) -> Bool {
    sessionActive && awake && screenAwake && idleSeconds.isFinite && idleSeconds >= 0
      && idleSeconds < 60
  }
}

public struct Observation: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let deviceID: String
  public let url: String
  public var title: String
  public let startedAt: Date
  public var lastSeenAt: Date
  public var activeSeconds: Double

  public init(
    id: UUID, deviceID: String, url: String, title: String, startedAt: Date, lastSeenAt: Date,
    activeSeconds: Double
  ) {
    self.id = id
    self.deviceID = deviceID
    self.url = url
    self.title = title
    self.startedAt = startedAt
    self.lastSeenAt = lastSeenAt
    self.activeSeconds = activeSeconds
  }
}

/// Credits only intervals bracketed by two eligible samples of the same URL.
/// Monotonic time and a bounded gap prevent credit for sleep or process suspension.
public struct AttentionTracker: Sendable {
  private let deviceID: String
  private var current: Observation?
  private var previousUptime: Double?

  public init(deviceID: String) { self.deviceID = deviceID }
  public mutating func reset() {
    current = nil
    previousUptime = nil
  }

  public mutating func sample(_ page: PageIdentity?, uptime: Double, date: Date) -> Observation? {
    guard let page, uptime.isFinite else {
      reset()
      return nil
    }
    let elapsed = uptime - (previousUptime ?? uptime)
    defer { previousUptime = uptime }
    guard var observation = current, observation.url == page.url, elapsed > 0, elapsed <= 5 else {
      current = Observation(
        id: UUID(), deviceID: deviceID, url: page.url, title: page.title, startedAt: date,
        lastSeenAt: date, activeSeconds: 0)
      return nil
    }
    observation.activeSeconds += elapsed
    observation.lastSeenAt = date
    observation.title = page.title
    current = observation
    return observation
  }
}
