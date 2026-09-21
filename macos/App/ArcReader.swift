import AppKit
import ApplicationServices
import AttentionCore

@MainActor
struct ArcReader {
  enum Result {
    case page(PageIdentity)
    case unavailable(String)
  }

  func read(policy: CapturePolicy) -> Result {
    guard AXIsProcessTrusted() else { return .unavailable("Accessibility permission needed") }
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier == "company.thebrowser.Browser"
    else {
      return .unavailable("Waiting for Arc")
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = element(root, kAXFocusedWindowAttribute),
      value(window, kAXMinimizedAttribute) as? Bool != true
    else {
      return .unavailable("No active Arc window")
    }
    // Read only document identities, never arbitrary text fields or the page body.
    // A split view or an ambiguous accessibility tree is deliberately not attributed.
    // Arc keeps the sidebar outside the window's page split groups. Traversing
    // the entire window can exhaust the budget on inactive tabs and spaces.
    guard let windowChildren = value(window, kAXChildrenAttribute) as? [AXUIElement] else {
      return .unavailable("Arc document lookup incomplete")
    }
    let contentRoots = windowChildren.filter {
      value($0, kAXRoleAttribute) as? String == kAXSplitGroupRole
    }
    guard !contentRoots.isEmpty else {
      return .unavailable("Arc page content is unavailable")
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 0.4
    var queue: [(AXUIElement, Int)] = contentRoots.map { ($0, 0) }
    var cursor = 0
    var documents: [(String, AXUIElement)] = []
    while cursor < queue.count, cursor < 160, ProcessInfo.processInfo.systemUptime < deadline {
      let (node, depth) = queue[cursor]
      cursor += 1
      if value(node, "AXHidden") as? Bool == true { continue }
      if value(node, kAXRoleAttribute) as? String == "AXWebArea" {
        if let url = urlString(value(node, kAXURLAttribute)) {
          documents.append((url, node))
        }
        continue  // Never traverse article text, links, or form fields.
      }
      if depth < 10, let children = value(node, kAXChildrenAttribute) as? [AXUIElement] {
        guard queue.count + children.count <= 160 else {
          return .unavailable("Arc document lookup incomplete")
        }
        queue.append(contentsOf: children.map { ($0, depth + 1) })
      } else if depth >= 10 {
        return .unavailable("Arc document lookup incomplete")
      }
    }
    guard cursor == queue.count else { return .unavailable("Arc document lookup incomplete") }
    guard documents.count == 1, let document = documents.first else {
      return .unavailable("Arc did not expose one active document")
    }
    guard let url = policy.acceptedURL(document.0) else {
      return .unavailable("Page excluded by your rules")
    }
    // Policy is evaluated before reading or retaining the document title.
    let title = value(document.1, kAXTitleAttribute) as? String ?? ""
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
      return .unavailable("Active application changed")
    }
    return .page(PageIdentity(url: url, title: String(title.prefix(512))))
  }

  private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.04)
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
      return nil
    }
    return result
  }

  private func element(_ root: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let result = value(root, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeDowncast(result, to: AXUIElement.self)
  }

  private func urlString(_ value: CFTypeRef?) -> String? {
    if let url = value as? URL { return url.absoluteString }
    return value as? String
  }
}
