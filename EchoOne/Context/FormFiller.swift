import AppKit
import ApplicationServices

/// BETA prototype — fills text fields in the frontmost window from a stored profile.
///
/// Strategy:
/// 1. Walk the frontmost app's Accessibility tree, collecting text-entry elements.
/// 2. Derive a human label for each field (title / placeholder / linked label).
/// 3. Match the label against a small profile (name, email, phone, …) by keyword.
/// 4. Write the value via `AXUIElementSetAttributeValue(kAXValue)`; for browsers — which
///    expose AX fields but honor value writes inconsistently — focus the field and paste
///    via `TextPaster` instead.
///
/// Secure fields (passwords) are always skipped.
///
/// This is intentionally heuristic and behind a beta flag. See the feasibility note in the
/// session plan for productionization steps.
@MainActor
struct FormFiller {

    // MARK: Profile

    /// Canonical fields the prototype knows how to fill.
    enum FieldKind: String, CaseIterable {
        case fullName, firstName, lastName, email, phone
        case address, city, state, zip, company, website

        /// UserDefaults key the value is stored under.
        var defaultsKey: String { "formFill_\(rawValue)" }

        /// Lowercased substrings that, if present in a field's label, map it to this kind.
        /// Order across `allCases` matters — more specific kinds are tried first below.
        var keywords: [String] {
            switch self {
            case .firstName: return ["first name", "given name", "fname"]
            case .lastName:  return ["last name", "surname", "family name", "lname"]
            case .fullName:  return ["full name", "your name", "name"]
            case .email:     return ["email", "e-mail"]
            case .phone:     return ["phone", "mobile", "tel", "cell"]
            case .address:   return ["address", "street"]
            case .city:      return ["city", "town"]
            case .state:     return ["state", "province", "region"]
            case .zip:       return ["zip", "postal", "postcode"]
            case .company:   return ["company", "organization", "organisation", "business", "employer"]
            case .website:   return ["website", "url", "web site"]
            }
        }
    }

    struct Profile {
        var values: [FieldKind: String]

        /// Loads whatever the user has saved in Settings; missing/empty fields are omitted.
        static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> Profile {
            var values: [FieldKind: String] = [:]
            for kind in FieldKind.allCases {
                if let v = defaults.string(forKey: kind.defaultsKey),
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    values[kind] = v
                }
            }
            return Profile(values: values)
        }

        var isEmpty: Bool { values.isEmpty }
    }

    struct Result {
        var filled: Int = 0
        var skippedSecure: Int = 0
        var unmatched: Int = 0
        var profileEmpty: Bool = false
        var noFieldsFound: Bool = false
    }

    // MARK: Dependencies

    private let textPaster: TextPaster

    init(textPaster: TextPaster = TextPaster()) {
        self.textPaster = textPaster
    }

    // MARK: Entry point

    /// Fills the frontmost window's form fields from `profile`. Returns a summary.
    @discardableResult
    func fillFrontmostForm(profile: Profile = .loadFromDefaults()) -> Result {
        var result = Result()
        guard !profile.isEmpty else {
            result.profileEmpty = true
            return result
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return result }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let root = focusedWindow(of: appElement) ?? appElement
        let usepaste = Self.isBrowser(bundleIdentifier: app.bundleIdentifier)

        var fields: [AXUIElement] = []
        collectFields(under: root, into: &fields, depth: 0)
        if fields.isEmpty {
            result.noFieldsFound = true
            return result
        }

        var usedKinds = Set<FieldKind>()
        for field in fields {
            let subrole = stringAttribute(field, kAXSubroleAttribute)
            if subrole == (kAXSecureTextFieldSubrole as String) {
                result.skippedSecure += 1
                continue
            }

            let label = labelText(for: field)
            guard let kind = matchKind(label: label, alreadyUsed: usedKinds),
                  let value = profile.values[kind] else {
                result.unmatched += 1
                continue
            }

            if write(value: value, to: field, preferPaste: usepaste) {
                usedKinds.insert(kind)
                result.filled += 1
            } else {
                result.unmatched += 1
            }
        }
        return result
    }

    // MARK: Field collection

    private static let maxDepth = 60
    private static let maxNodes = 4000

    private func collectFields(under element: AXUIElement, into fields: inout [AXUIElement], depth: Int) {
        guard depth < Self.maxDepth, fields.count < Self.maxNodes else { return }

        let role = stringAttribute(element, kAXRoleAttribute)
        if let role, Self.fillableRoles.contains(role) {
            fields.append(element)
        }

        for child in children(of: element) {
            collectFields(under: child, into: &fields, depth: depth + 1)
        }
    }

    private static let fillableRoles: Set<String> = [
        kAXTextFieldRole as String,   // secure fields share this role; skipped later by subrole
        "AXTextArea",                 // no SDK constant; matched by literal role string
        kAXComboBoxRole as String
    ]

    // MARK: Label derivation

    /// Builds one lowercased label string from every signal a field exposes.
    private func labelText(for field: AXUIElement) -> String {
        var parts: [String] = []
        for attr in [
            kAXTitleAttribute,
            kAXPlaceholderValueAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute
        ] {
            if let s = stringAttribute(field, attr) { parts.append(s) }
        }
        // A linked label element (e.g. the <label> in many native/web forms).
        if let titleElement = elementAttribute(field, kAXTitleUIElementAttribute) {
            if let s = stringAttribute(titleElement, kAXValueAttribute) { parts.append(s) }
            if let s = stringAttribute(titleElement, kAXTitleAttribute) { parts.append(s) }
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// Picks the most specific unused field kind whose keyword appears in `label`.
    /// `FieldKind.allCases` is declared most-specific-first (firstName/lastName before fullName).
    private func matchKind(label: String, alreadyUsed: Set<FieldKind>) -> FieldKind? {
        guard !label.isEmpty else { return nil }
        for kind in FieldKind.allCases where !alreadyUsed.contains(kind) {
            if kind.keywords.contains(where: { label.contains($0) }) {
                return kind
            }
        }
        return nil
    }

    // MARK: Writing values

    /// Writes `value` into `field`. Returns true on apparent success.
    private func write(value: String, to field: AXUIElement, preferPaste: Bool) -> Bool {
        if !preferPaste {
            let status = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, value as CFTypeRef)
            if status == .success {
                // Verify — some apps report success without applying the value.
                if stringAttribute(field, kAXValueAttribute) == value { return true }
            }
        }
        return pasteInto(field: field, value: value)
    }

    /// Focuses the field, selects any existing contents, and pastes via the clipboard.
    private func pasteInto(field: AXUIElement, value: String) -> Bool {
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, true as CFTypeRef)
        // Select existing text so the paste replaces rather than appends, when supported.
        if let existing = stringAttribute(field, kAXValueAttribute), !existing.isEmpty {
            var range = CFRangeMake(0, (existing as NSString).length)
            if let axRange = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, axRange)
            }
        }
        return textPaster.paste(text: value) == .pasted
    }

    // MARK: AX helpers

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        elementAttribute(appElement, kAXFocusedWindowAttribute)
            ?? elementAttribute(appElement, kAXMainWindowAttribute)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let s = value as? String else {
            return nil
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier?.lowercased() else { return false }
        let browsers = [
            "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
            "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser",
            "com.operasoftware.opera", "com.vivaldi.vivaldi"
        ]
        return browsers.contains(where: { id.contains($0) })
    }
}
