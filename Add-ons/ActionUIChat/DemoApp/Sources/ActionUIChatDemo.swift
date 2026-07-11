// Add-ons/ActionUIChat/DemoApp/Sources/ActionUIChatDemo.swift
//
// Dedicated macOS demo app for the ActionUIChat ACP transport: launch a real Agent Client
// Protocol agent (OpenCode, claude-code-acp, ...) as a subprocess and host the session in
// a Chat element - streamed replies, thoughts, tool-call cards, and permission approvals.
//
// Why a dedicated app instead of another ActionUIAddOnTestApp resource: an ACP demo
// document is inherently machine-specific (which agent binary, which working directory)
// and macOS-only (the agent is a subprocess), so it cannot ship as a committed static
// JSON in the shared multiplatform test app. And GUI apps do not inherit the user's
// shell PATH (agents typically live in ~/.opencode/bin, /opt/homebrew/bin, ...), so a
// bare "opencode" in transport.command resolves in a terminal but not when launched from
// Finder or Xcode. This host does what a real embedding app would do: offer a launcher
// UI for the agent command + working directory and resolve the command through the
// user's login shell.
//
// The document itself is the STATIC bundled Resources/ChatDemo.json - the ActionUI way:
// static JSON describes the UI, and the host injects the runtime/session-specific parts
// (the resolved transport.command and cwd) into the element's non-visual config block.
// loadView loads the document's model tree synchronously, the element's view is built
// lazily on first render, so setElementConfig(.."transport"..) between the two lands
// before the Chat element exists - no JSON is ever generated.

import SwiftUI
import AppKit
import ActionUI
import ActionUISwiftAdapter
import ActionUIChat

@main
struct ActionUIChatDemoApp: App {

    init() {
        ActionUISwift.setLogger(ConsoleLogger(maxLevel: .info))
        ActionUIChat.register()

        // Every chat action lands in the in-app event log (and on the console), so the
        // demo doubles as a visualization of the action IDs a host can observe
        // (sendActionID, messageActionID, approveToolActionID, ...).
        ActionUISwift.setDefaultActionHandler { actionID, _, viewID, _, _ in
            let line = "[action] \(actionID) (element \(viewID))"
            print(line)
            Task { @MainActor in
                ActionEventLog.shared.append(line)
            }
        }
    }

    var body: some Scene {
        WindowGroup("ActionUI Chat Demo") {
            ChatDemoView()
                .frame(minWidth: 480, minHeight: 480)
        }
        .defaultSize(width: 720, height: 720)
    }
}

/// One running chat: the loaded (and transport-injected) document view plus its identity.
/// The view is built ONCE in start() - loadView registers the document's model tree in
/// its init, so building it in a SwiftUI body would re-load the static document on every
/// render and reset the injected properties.
struct ChatSession {
    let number: Int
    let windowUUID: String
    let view: AnyView
    let commandDisplay: String
    let cwdDisplay: String
}

/// Root view: the launcher (configure the agent) or a running chat session.
struct ChatDemoView: View {
    /// The Chat element's id in the bundled Resources/ChatDemo.json.
    private let chatElementID = 1

    @State private var commandLine = "opencode acp"
    @State private var workingDirectory = "~"
    @State private var session: ChatSession?
    @State private var isStarting = false
    @State private var startError: String?
    @State private var nextSessionNumber = 1
    @State private var demoSession: DemoSession?

    var body: some View {
        if let demoSession {
            DemoSessionView(session: demoSession) { self.demoSession = nil }
        } else if let session {
            ChatSessionView(session: session,
                            onNewSession: { startSession() },
                            onConfigure: { self.session = nil })
        } else {
            launcher
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Host an ACP agent")
                .font(.title2.bold())
            Text("The Chat element launches the agent as a subprocess (newline-delimited JSON-RPC over stdio) and hosts the session: streamed replies, thoughts, tool-call cards, and permission approvals. The agent must be installed and authenticated (e.g. \"opencode auth login\").")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Agent command", text: $commandLine)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Menu("Presets") {
                    Button("OpenCode") {
                        commandLine = "opencode acp"
                    }
                    Button("Claude Code (claude-code-acp)") {
                        commandLine = "claude-code-acp"
                    }
                    Button("Gemini CLI") {
                        commandLine = "gemini --experimental-acp"
                    }
                }
                .fixedSize()
            }
            Text("Whitespace-separated argv. A bare command name is resolved through your login shell's PATH; an absolute or ~ path is used directly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Working directory", text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("Choose...") {
                    chooseWorkingDirectory()
                }
            }
            Text("The agent operates on this directory (the ACP session cwd).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let startError {
                Text(startError)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Start Chat") {
                    startSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isStarting || commandLine.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider().padding(.vertical, 4)

            // Scripted person-to-person / group demos: no agent, no wire - the built-in local-p2p
            // transport drives a full dual-alignment conversation (timestamps, delivery status,
            // reactions, replies, edits, files, voice, member/call events, typing, paged history).
            Text("Scripted demos (no agent needed)")
                .font(.headline)
            Text("Dual-alignment person-to-person and group chat driven by the built-in local-p2p transport.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Person-to-Person Demo") {
                    startDemo(resource: "ChatPeople", title: "Person-to-Person")
                }
                Button("Group Demo") {
                    startDemo(resource: "ChatGroup", title: "Group Chat")
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func startDemo(resource: String, title: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            startError = "The bundled \(resource).json resource is missing."
            return
        }
        let windowUUID = "chat-demo-\(resource)-\(nextSessionNumber)"
        nextSessionNumber += 1
        let view = AnyView(ActionUISwift.loadView(from: url, windowUUID: windowUUID, isContentView: true))
        demoSession = DemoSession(title: title, view: view)
    }

    private func startSession() {
        Task {
            await start()
        }
    }

    private func start() async {
        startError = nil
        isStarting = true
        defer {
            isStarting = false
        }
        let argv = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = argv.first else {
            startError = "Enter an agent command."
            return
        }
        guard let resolved = await resolveExecutable(executable) else {
            startError = "\"\(executable)\" was not found on the login shell's PATH (or is not executable). Try an absolute path."
            return
        }
        var command = argv
        command[0] = resolved
        guard let documentURL = Bundle.main.url(forResource: "ChatDemo", withExtension: "json") else {
            startError = "The bundled ChatDemo.json resource is missing."
            return
        }
        let number = nextSessionNumber
        nextSessionNumber += 1
        let windowUUID = "chat-acp-demo-\(number)"
        // The ActionUI pattern: load the STATIC document (this registers its model tree
        // synchronously), then inject the runtime/session-specific transport through the
        // element's non-visual config block. The element's view is built lazily on first
        // render, so the injected transport is what the Chat element starts with.
        let view = AnyView(ActionUISwift.loadView(from: documentURL, windowUUID: windowUUID, isContentView: true))
        ActionUISwift.setElementConfig(windowUUID: windowUUID,
                                       viewID: chatElementID,
                                       key: "transport",
                                       value: ["command": command, "cwd": workingDirectory])
        session = ChatSession(number: number,
                              windowUUID: windowUUID,
                              view: view,
                              commandDisplay: command.joined(separator: " "),
                              cwdDisplay: workingDirectory)
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Working Directory"
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}

/// A scripted person-to-person / group demo: a loaded example document (protocol local-p2p,
/// no agent, no injection) and its title.
struct DemoSession: Identifiable {
    let id = UUID()
    let title: String
    let view: AnyView
}

/// Presents a scripted demo with a back button to the launcher.
struct DemoSessionView: View {
    let session: DemoSession
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Demos", systemImage: "chevron.left")
                }
                Spacer()
                Text(session.title).font(.headline)
                Spacer()
                // Balance the leading button so the title stays centered.
                Label("Demos", systemImage: "chevron.left").hidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            session.view
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The running session: a header naming the agent, the Chat element itself, and a footer
/// showing the most recent action the chat fired at the host. Swapping the session (New
/// Session / Configure) tears the old chat view down, which stops the transport and
/// terminates the agent subprocess (ChatRootView.onDisappear -> ChatStore.teardown).
struct ChatSessionView: View {
    let session: ChatSession
    let onNewSession: () -> Void
    let onConfigure: () -> Void
    @ObservedObject private var eventLog = ActionEventLog.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            session.view
                .id(session.number)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.commandDisplay)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("cwd: \(session.cwdDisplay)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("New Session") {
                onNewSession()
            }
            Button("Configure...") {
                onConfigure()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text(eventLog.lines.last ?? "Actions fired by the chat appear here (chat.send, chat.message, chat.tool.approve, ...)")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            if !eventLog.lines.isEmpty {
                Text("\(eventLog.lines.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// The action IDs fired by the chat, collected for the session footer.
@MainActor
final class ActionEventLog: ObservableObject {
    static let shared = ActionEventLog()
    @Published private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
        if lines.count > 200 {
            lines.removeFirst(lines.count - 200)
        }
    }
}

/// Resolves the agent executable: absolute and ~ paths are checked directly; a bare name
/// is looked up through the user's LOGIN shell, because a GUI app inherits only the
/// minimal launchd PATH (no ~/.opencode/bin, /opt/homebrew/bin, ...).
private func resolveExecutable(_ name: String) async -> String? {
    if name.hasPrefix("/") || name.hasPrefix("~") {
        let path = (name as NSString).expandingTildeInPath
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: loginShellLookup(name))
        }
    }
}

/// `command -v` in an INTERACTIVE login shell (-l -i); blocking (run + drain + wait),
/// call off the main thread. -i matters: PATH exports conventionally live in ~/.zshrc,
/// which a non-interactive login shell never sources (it reads only .zshenv/.zprofile),
/// so plain -l misses agents installed via ~/.zshrc PATH lines (opencode among them).
/// The rc noise an interactive shell may produce is tolerated by the output filtering
/// below; its prompt goes to stderr, which is discarded.
private func loginShellLookup(_ name: String) -> String? {
    let quoted = "'" + name.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-i", "-c", "command -v -- " + quoted]
    // A GUI app's environment has no TERM; give rc scripts a harmless one.
    var environment = ProcessInfo.processInfo.environment
    if environment["TERM"] == nil {
        environment["TERM"] = "dumb"
    }
    process.environment = environment
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    // The output is one small line; a synchronous drain is fine here (this is not the
    // long-lived pipe reading that ACPConnection must do with readabilityHandler).
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }
    // Profile scripts may echo onto stdout before the lookup result: take the last
    // non-empty line and require an executable absolute path.
    let candidates = String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard let path = candidates.last(where: { !$0.isEmpty && $0.hasPrefix("/") }) else {
        return nil
    }
    guard FileManager.default.isExecutableFile(atPath: path) else {
        return nil
    }
    return path
}
