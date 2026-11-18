import CryptoKit
import Foundation

/// Echo Actions: voice commands that run a script straight away instead of going to the agent.
/// One script per action, in Raycast's script command format (`# @raycast.title …`), plus an optional
/// Echo-only `# @echo.phrases` line. The format is written up for people and agents in ECHO-ACTIONS.md.
enum EchoActions {
    static let foldersDefaultsKey = "echoActionFolders"
    static let raycastOfferedDefaultsKey = "echoActionsRaycastOffered"
    static let guideFileName = "ECHO-ACTIONS.md"
    static let approvedDefaultsKey = "echoActionsApproved"
    /// A script that exits with this says "not mine": the command goes to the Voice Agent instead.
    static let passExitCode: Int32 = 75
    private static let timeout: TimeInterval = 30

    struct Action: Identifiable, Equatable {
        var id: String { file.path }
        let title: String
        /// Cleaned up the same way as what the user says; the title comes first.
        let phrases: [String]
        let file: URL
        let mode: String
        let summary: String
        let needsConfirmation: Bool
        let takesArgument: Bool
        /// More than one required argument: it can be typed in Raycast but not said.
        let needsTyping: Bool
        let workingFolder: URL
        let isBuiltIn: Bool
    }

    struct Outcome {
        /// Everything the script printed, for the transcript.
        let output: String
        /// The last line, or why it failed.
        let spoken: String
        let failed: Bool
        let passToAgent: Bool
    }

    // MARK: Folders

    static func defaultFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Echo One Actions")
    }

    static var builtInFolder: URL? { Bundle.main.url(forResource: "actions", withExtension: nil) }

    static var userFolders: [URL] {
        get {
            let paths = UserDefaults.standard.stringArray(forKey: foldersDefaultsKey) ?? [defaultFolder().path]
            return paths.map { URL(fileURLWithPath: $0) }
        }
        set { UserDefaults.standard.set(newValue.map(\.path), forKey: foldersDefaultsKey) }
    }

    /// Creates the default folder and keeps the guide in it current, so an agent pointed at the folder
    /// finds the instructions next to the scripts.
    static func prepareDefaultFolder() {
        let folder = defaultFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let bundled = Bundle.main.url(forResource: "ECHO-ACTIONS", withExtension: "md"),
              let guide = try? Data(contentsOf: bundled) else { return }
        let target = folder.appendingPathComponent(guideFileName)
        if (try? Data(contentsOf: target)) != guide { try? guide.write(to: target) }
    }

    static var guideText: String {
        Bundle.main.url(forResource: "ECHO-ACTIONS", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// Folders holding Raycast script commands, found by Spotlight. Excludes ones already added.
    static func findRaycastFolders() async -> [(folder: URL, count: Int)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["@raycast.schemaVersion"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit()
        let known = Set(userFolders.map(\.standardizedFileURL.path) + [builtInFolder?.standardizedFileURL.path].compactMap { $0 })
        var counts: [String: Int] = [:]
        for path in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let folder = (String(path) as NSString).deletingLastPathComponent
            // Skip app bundles, caches and archived copies.
            if folder.contains(".app/") || folder.contains("/Library/") || folder.contains("/_archive/") { continue }
            if known.contains(folder) { continue }
            // Echo One's own copies: the repo's actions folder sits next to the guide.
            let parent = (folder as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: parent + "/" + guideFileName) { continue }
            counts[folder, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { (URL(fileURLWithPath: $0.key), $0.value) }
    }

    // MARK: Loading

    /// The built-ins, then each user folder. A user action replaces a built-in with the same title.
    static func load() -> [Action] {
        var byTitle: [String: Action] = [:]
        var order: [String] = []
        let sources = [builtInFolder.map { ($0, true) }].compactMap { $0 } + userFolders.map { ($0, false) }
        for (folder, isBuiltIn) in sources {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let action = parse(file, isBuiltIn: isBuiltIn) else { continue }
                let key = normalize(action.title)
                if byTitle[key] == nil { order.append(key) }
                byTitle[key] = action
            }
        }
        return order.compactMap { byTitle[$0] }
    }

    static func parse(_ file: URL, isBuiltIn: Bool) -> Action? {
        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              !["md", "json", "txt"].contains(file.pathExtension.lowercased()),
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var fields: [String: String] = [:]
        var arguments: [[String: Any]] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) {
            var rest = line.trimmingCharacters(in: .whitespaces)
            guard let prefix = ["#", "//", "--"].first(where: { rest.hasPrefix($0) }) else { continue }
            rest = rest.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("@raycast.") || rest.hasPrefix("@echo.") else { continue }
            let parts = rest.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("@raycast.argument") {
                let json = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any]
                arguments.append(json ?? [:])
            } else {
                fields[key] = value
            }
        }
        guard fields["@raycast.schemaVersion"] != nil, let title = fields["@raycast.title"], !title.isEmpty else { return nil }
        let extra = (fields["@echo.phrases"] ?? "").split(separator: ",").map { normalize(String($0)) }
        var phrases: [String] = []
        for phrase in [normalize(title)] + extra where !phrase.isEmpty && !phrases.contains(phrase) { phrases.append(phrase) }
        let required = arguments.filter { ($0["optional"] as? Bool) != true }.count
        let workingFolder = fields["@raycast.currentDirectoryPath"].map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: file.deletingLastPathComponent())
        } ?? file.deletingLastPathComponent()
        return Action(
            title: title,
            phrases: phrases,
            file: file,
            mode: fields["@raycast.mode"] ?? "compact",
            summary: fields["@raycast.description"] ?? "",
            needsConfirmation: fields["@raycast.needsConfirmation"] == "true",
            takesArgument: !arguments.isEmpty,
            needsTyping: required > 1,
            workingFolder: workingFolder,
            isBuiltIn: isBuiltIn
        )
    }

    // MARK: Matching

    private static let leadingFillers = ["please", "can you", "could you", "hey"]

    /// "Hey, can you turn on Wi-Fi please?" → "turn on wifi".
    static func normalize(_ text: String) -> String {
        var cleaned = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "-", with: "")
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
            .split(separator: " ").joined(separator: " ")
        var changed = true
        while changed {
            changed = false
            for filler in leadingFillers where cleaned == filler || cleaned.hasPrefix(filler + " ") {
                cleaned = String(cleaned.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if cleaned.hasSuffix(" please") {
                cleaned = String(cleaned.dropLast(" please".count))
                changed = true
            }
        }
        return cleaned
    }

    /// The action whose title or phrase is what was said. An action that takes an argument also matches
    /// when what was said starts with its phrase; the rest is the argument. The longest phrase wins.
    static func match(_ transcript: String, in actions: [Action]) -> (action: Action, argument: String?)? {
        let said = normalize(transcript)
        guard !said.isEmpty else { return nil }
        var best: (action: Action, argument: String?, length: Int)?
        for action in actions where !action.needsTyping {
            for phrase in action.phrases where phrase.count > (best?.length ?? -1) {
                if said == phrase {
                    best = (action, nil, phrase.count)
                } else if action.takesArgument, said.hasPrefix(phrase + " ") {
                    best = (action, String(said.dropFirst(phrase.count + 1)), phrase.count)
                }
            }
        }
        return best.map { ($0.action, $0.argument.map(digitsForNumberWords)) }
    }

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// Speech-to-text often writes numbers as words; scripts expect digits. "thirty percent" → "30 percent",
    /// "three thousand" → "3000", "fortyfive minutes" (from "forty-five") → "45 minutes".
    static func digitsForNumberWords(_ text: String) -> String {
        func value(_ word: String) -> Int? {
            if let number = ones[word] ?? tens[word] { return number }
            for (ten, tenValue) in tens where word.hasPrefix(ten) {
                if let one = ones[String(word.dropFirst(ten.count))], one < 10 { return tenValue + one }
            }
            return nil
        }
        var output: [String] = []
        var total = 0, current = 0, inNumber = false, heldAnd = false
        func flush() {
            if inNumber { output.append(String(total + current)) }
            if heldAnd { output.append("and") }
            total = 0; current = 0; inNumber = false; heldAnd = false
        }
        for word in text.split(separator: " ").map(String.init) {
            if let number = value(word) {
                current += number
                inNumber = true
                heldAnd = false
            } else if inNumber, !heldAnd, word == "hundred" {
                current = max(current, 1) * 100
            } else if inNumber, !heldAnd, word == "thousand" {
                total += max(current, 1) * 1000
                current = 0
            } else if inNumber, !heldAnd, word == "and" {
                // "one hundred and five" is one number; "five and a half" isn't.
                heldAnd = true
            } else {
                flush()
                output.append(word)
            }
        }
        flush()
        return output.joined(separator: " ")
    }

    static func isYes(_ transcript: String) -> Bool {
        ["yes", "yeah", "yep", "yes please", "do it", "go ahead", "go", "sure", "ok", "okay", "confirm",
         "yes do it", "yeah do it", "yes go ahead", "yeah go ahead"]
            .contains(normalize(transcript))
    }

    static func isNo(_ transcript: String) -> Bool {
        ["no", "nope", "cancel", "stop", "never mind", "nevermind", "dont"].contains(normalize(transcript))
    }

    /// "Stop", said on its own, ends whatever the Voice Agent is doing.
    static func isStop(_ transcript: String) -> Bool {
        ["stop", "stop it", "cancel", "cancel that", "never mind", "nevermind", "stop talking", "be quiet", "quiet",
         "shut up"].contains(normalize(transcript))
    }

    // MARK: First run

    /// One of the user's own scripts that hasn't run before, or has changed since it last did, asks first.
    /// Built-ins ship with the app and don't.
    static func needsFirstRunApproval(_ action: Action) -> Bool {
        guard !action.isBuiltIn else { return false }
        let approved = UserDefaults.standard.dictionary(forKey: approvedDefaultsKey) as? [String: String] ?? [:]
        return approved[action.file.path] == nil || approved[action.file.path] != fingerprint(action.file)
    }

    static func approve(_ action: Action) {
        guard !action.isBuiltIn, let print = fingerprint(action.file) else { return }
        var approved = UserDefaults.standard.dictionary(forKey: approvedDefaultsKey) as? [String: String] ?? [:]
        approved[action.file.path] = print
        UserDefaults.standard.set(approved, forKey: approvedDefaultsKey)
    }

    private static func fingerprint(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Running

    /// Thread-safe output buffer filled as the script prints.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func run(_ action: Action, argument: String?) async -> Outcome {
        let process = Process()
        let file = action.file.path
        let arguments = argument.map { [$0] } ?? []
        if FileManager.default.isExecutableFile(atPath: file) {
            process.executableURL = action.file
            process.arguments = arguments
        } else if action.file.pathExtension.lowercased() == "applescript" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [file] + arguments
        } else if let shebang = Self.shebang(action.file) {
            process.executableURL = URL(fileURLWithPath: shebang[0])
            process.arguments = Array(shebang.dropFirst()) + [file] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [file] + arguments
        }
        process.currentDirectoryURL = action.workingFolder
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let output = Pipe(), errors = Pipe()
        let printed = Collected(), errorText = Collected()
        process.standardOutput = output
        process.standardError = errors
        // Read as it arrives rather than to the end: a background child (a timer, caffeinate) that kept the
        // pipe open would otherwise hold Echo One until the timeout.
        output.fileHandleForReading.readabilityHandler = { printed.append($0.availableData) }
        errors.fileHandleForReading.readabilityHandler = { errorText.append($0.availableData) }
        let timedOut = Flag()

        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: finished.terminationStatus)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timedOut.set(); process.terminate() }
            }
        }

        let text = Self.withoutColorCodes(printed.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLine = Self.lastLine(text)
        guard let status else {
            return Outcome(output: "", spoken: "That didn't work: Echo One couldn't start \(action.title).", failed: true, passToAgent: false)
        }
        if timedOut.isSet {
            return Outcome(output: text, spoken: "\(action.title) took too long, so I stopped it.", failed: true, passToAgent: false)
        }
        if status == passExitCode {
            return Outcome(output: text, spoken: "", failed: false, passToAgent: true)
        }
        if status != 0 {
            let reason = lastLine ?? Self.lastLine(Self.withoutColorCodes(errorText.text)) ?? "it stopped with error \(status)."
            return Outcome(output: text, spoken: "That didn't work: " + reason, failed: true, passToAgent: false)
        }
        return Outcome(output: text, spoken: lastLine ?? "Done.", failed: false, passToAgent: false)
    }

    /// `#!/usr/bin/env python3` → ["/usr/bin/env", "python3"].
    private static func shebang(_ file: URL) -> [String]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.hasPrefix("#!") else { return nil }
        let line = text.dropFirst(2).prefix { $0 != "\n" }
        let parts = line.split(separator: " ").map(String.init)
        return parts.isEmpty ? nil : parts
    }

    private static func lastLine(_ text: String) -> String? {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }

    private static func withoutColorCodes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    /// The starting file "New Action" writes.
    static func template(title: String) -> String {
        """
        #!/bin/bash
        # @raycast.schemaVersion 1
        # @raycast.title \(title)
        # @raycast.mode compact
        # @raycast.description What this does, in a sentence.
        # @echo.phrases other ways, to say it

        # Say "\(title.lowercased())" to the Voice Agent to run this. The last line printed is what she says.
        # How to write one (or what to give your agent): ECHO-ACTIONS.md in this folder.

        echo "Done."

        """
    }
}
