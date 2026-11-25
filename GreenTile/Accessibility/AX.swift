import AppKit
import ApplicationServices

/// Maps an Accessibility window to its Quartz window number. This is a long-standing private
/// symbol of the Accessibility framework (used by most window managers); there is no public
/// equivalent.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, typed wrappers around the C Accessibility API.
enum AX {
    // MARK: Reading

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        elementsIfAvailable(element, attribute) ?? []
    }

    /// Like `elements`, but `nil` when the query itself failed (timeout, unresponsive app), so
    /// callers can tell that apart from a genuinely empty list.
    static func elementsIfAvailable(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let array = copy(element, attribute) as? [AnyObject] else { return nil }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var out = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &out) ? out : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var out = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &out) ? out : nil
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    // MARK: Windows

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    static func zoomButton(of window: AXUIElement) -> AXUIElement? {
        element(window, kAXZoomButtonAttribute)
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        bool(window, "AXFullScreen") ?? false
    }

    /// Moves and resizes `window`. Size is applied before and after the move because some apps
    /// clamp the size against the display the window is leaving, and `AXEnhancedUserInterface`
    /// (set by some assistive tools) makes frame changes animate slowly, so it is suspended.
    static func setFrame(_ window: AXUIElement, to frame: CGRect) {
        let app = AXUIElementCreateApplication(pid(of: window))
        let enhanced = bool(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, false as CFBoolean) }
        defer {
            if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, true as CFBoolean) }
        }
        setSize(window, frame.size)
        setPosition(window, frame.origin)
        setSize(window, frame.size)
    }

    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    /// Brings `window` (and its app) to the front.
    static func raise(_ window: AXUIElement) {
        let app = AXUIElementCreateApplication(pid(of: window))
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, true as CFBoolean)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Brings `window` in front of other windows without making its app the active one.
    static func raiseWithoutActivating(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
