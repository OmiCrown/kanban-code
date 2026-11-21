import SwiftUI
import KanbanCodeCore

/// Pre-launch confirmation dialog showing editable prompt, options, and editable command.
/// Also used for resume — shows the resume command with remote toggle.
struct LaunchConfirmationDialog: View {
    let cardId: String
    let projectPath: String
    let initialPrompt: String
    var worktreeName: String?
    let hasExistingWorktree: Bool
    let isGitRepo: Bool
    let hasRemoteConfig: Bool
    let remoteHost: String?
    /// Remote backend of this launch. When set it decides the remote row, and
    /// `hasRemoteConfig` / `remoteHost` are ignored.
    var remoteOptions: RemoteLaunchOptions?
    let isResume: Bool
    let sessionId: String?
    let assistant: CodingAssistant
    let initialServiceId: String?
    let modelOverride: String?
    /// The launch command the card was started with; nil means plain `claude`.
    let initialLauncherCommand: String?
    @Binding var isPresented: Bool
    /// Boxd machine the user picked. Called just before `onLaunch` when the
    /// launch runs on boxd.
    var onMachineChoice: (BoxdMachineChoice) -> Void = { _ in }
    /// Asks the caller to remove the machine of this card. The caller confirms.
    var onRemoveMachine: (() -> Void)?
    /// Branch names in use, so a name made from the prompt does not repeat one.
    var takenWorktreeNames: Set<String> = []
    var onLaunch: (String, Bool, String?, Bool, Bool, String?, [ImageAttachment], String?, String?) -> Void = { _, _, _, _, _, _, _, _, _ in } // (editedPrompt, createWorktree, worktreeBranch, runRemotely, skipPermissions, commandOverride, images, apiServiceId, launcherCommand)

    private let settingsStore = SettingsStore()
    @State private var settings = Settings()
    @State private var apiServices: [APIService] = []
    @State private var selectedServiceId: String?
    @State private var prompt: String
    @State private var images: [ImageAttachment]
    @State private var command: String = ""
    @State private var commandEdited: Bool = false
    /// Every command the form made itself; a field with any other text was edited by the user.
    @State private var generatedCommands = GeneratedText()
    /// The command that starts Claude Code: `claude` or a launcher's command.
    @State private var selectedLauncher: String
    /// Set once the user picks a launcher here, or the card brought one.
    @State private var launcherPicked: Bool
    @State private var worktreeBranch: String = ""
    @State private var createWorktree: Bool
    @State private var runRemotely: Bool
    @State private var machineChoice: BoxdMachineChoice
    @AppStorage("dangerouslySkipPermissions") private var dangerouslySkipPermissions = true

    init(
        cardId: String,
        projectPath: String,
        initialPrompt: String,
        worktreeName: String? = nil,
        hasExistingWorktree: Bool = false,
        isGitRepo: Bool = false,
        hasRemoteConfig: Bool = false,
        remoteHost: String? = nil,
        remoteOptions: RemoteLaunchOptions? = nil,
        isResume: Bool = false,
        sessionId: String? = nil,
        promptImagePaths: [String] = [],
        assistant: CodingAssistant = .claude,
        initialServiceId: String? = nil,
        modelOverride: String? = nil,
        initialLauncherCommand: String? = nil,
        isPresented: Binding<Bool>,
        onLaunch: @escaping (String, Bool, String?, Bool, Bool, String?, [ImageAttachment], String?, String?) -> Void = { _, _, _, _, _, _, _, _, _ in },
        onMachineChoice: @escaping (BoxdMachineChoice) -> Void = { _ in },
        onRemoveMachine: (() -> Void)? = nil,
        takenWorktreeNames: Set<String> = []
    ) {
        self.cardId = cardId
        self.projectPath = projectPath
        self.initialPrompt = initialPrompt
        self.worktreeName = worktreeName
        self.hasExistingWorktree = hasExistingWorktree
        self.isGitRepo = isGitRepo
        self.hasRemoteConfig = hasRemoteConfig
        self.remoteHost = remoteHost
        self.remoteOptions = remoteOptions
        self.isResume = isResume
        self.sessionId = sessionId
        self.assistant = assistant
        self.initialServiceId = initialServiceId
        self.modelOverride = modelOverride
        self.initialLauncherCommand = initialLauncherCommand
        self._selectedLauncher = State(initialValue: initialLauncherCommand ?? ClaudeLauncherResolver.plain)
        self._launcherPicked = State(initialValue: initialLauncherCommand != nil)
        self._isPresented = isPresented
        self.onMachineChoice = onMachineChoice
        self.onRemoveMachine = onRemoveMachine
        self.takenWorktreeNames = takenWorktreeNames
        self.onLaunch = onLaunch
        self._selectedServiceId = State(initialValue: initialServiceId)
        self._prompt = State(initialValue: initialPrompt)
        self._images = State(initialValue: promptImagePaths.compactMap { ImageAttachment.fromPath($0) })
        let mode = remoteOptions?.mode ?? .mutagen
        let cardMachine = remoteOptions?.cardMachine
        let remoteDefault = remoteOptions == nil
            ? (UserDefaults.standard.object(forKey: "runRemotely_\(projectPath)") as? Bool ?? true)
            : RemoteLaunchOptions.initialRunRemotely(
                lastRunRemote: remoteOptions?.lastRunRemote, cardMachine: cardMachine,
                ownerMachine: remoteOptions?.ownerMachine, mode: mode, projectPath: projectPath)
        self._runRemotely = State(initialValue: remoteDefault)
        self._machineChoice = State(initialValue: remoteOptions?.initialMachineChoice(projectPath: projectPath)
            ?? cardMachine.map { BoxdMachineChoice.existing($0) } ?? .newMachine)
        self._createWorktree = State(initialValue: UserDefaults.standard.object(forKey: "createWorktree_\(projectPath)") as? Bool ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isResume ? "Resume Session" : "Launch Session")
                        .font(.app(.title3))
                        .fontWeight(.semibold)

                    // Project path (read-only)
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(projectPath)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // API Service picker
                    let servicesForAssistant = apiServices.filter { $0.assistant == assistant }
                    if !servicesForAssistant.isEmpty {
                        Picker("API Service", selection: $selectedServiceId) {
                            Text("Default").tag(String?.none)
                            ForEach(servicesForAssistant) { service in
                                Text(service.name).tag(String?.some(service.id))
                            }
                        }
                        .onChange(of: selectedServiceId) {
                            refreshCommand()
                        }
                    }

                    // Worktree name (if applicable, launch only)
                    if !isResume, let name = worktreeName {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Session ID (resume only)
                    if isResume, let sid = sessionId {
                        HStack(spacing: 6) {
                            AssistantIcon(assistant: assistant)
                                .frame(width: CGFloat(14).scaled, height: CGFloat(14).scaled)
                                .opacity(0.5)
                            Text(sid)
                                .font(.app(.caption).monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    // Launch command picker (Claude Code only, when launchers exist).
                    // A started card keeps its command, so a resume shows it disabled.
                    if assistant == .claude && !settings.claudeLaunchers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Launch with", selection: Binding(
                                get: { selectedLauncher },
                                set: { selectedLauncher = $0; launcherPicked = true }
                            )) {
                                Text(ClaudeLauncherEditing.plainName).tag(ClaudeLauncherResolver.plain)
                                ForEach(settings.claudeLaunchers) { launcher in
                                    Text(launcher.name).tag(launcher.command)
                                }
                            }
                            .disabled(isResume || effectiveRunRemotely)
                            if isResume {
                                Label("A started card keeps its launch command", systemImage: "info.circle")
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            } else if effectiveRunRemotely {
                                Label("applies to local runs", systemImage: "info.circle")
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Editable prompt (launch only)
                    if !isResume {
                        PromptSection(
                            text: $prompt,
                            images: $images,
                            minHeight: 120,
                            onSubmit: submitForm,
                            onEscape: { isPresented = false }
                        )
                    }

                    // Checkboxes
                    VStack(alignment: .leading, spacing: 6) {
                        if !isResume && !hasExistingWorktree && assistant.supportsWorktree {
                            Toggle("Create worktree", isOn: isGitRepo ? $createWorktree : .constant(false))
                                .font(.app(.callout))
                                .disabled(!isGitRepo)
                            if !isGitRepo {
                                Label("Not a git repository", systemImage: "info.circle")
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 20)
                            }
                            if createWorktree && isGitRepo {
                                HStack {
                                    Text("Branch name")
                                        .font(.app(.callout))
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $worktreeBranch, prompt: Text("Leave empty for a random name"))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.app(.callout))
                                    Button {
                                        worktreeBranch = WorktreeSlug.make(
                                            from: prompt,
                                            fallback: cardId,
                                            taken: takenWorktreeNames
                                        )
                                    } label: {
                                        Image(systemName: "wand.and.stars")
                                    }
                                    .help("Make a name from the prompt")
                                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                .padding(.leading, 20)
                            }
                        }

                        remoteSection

                        Toggle("Dangerously skip permissions", isOn: $dangerouslySkipPermissions)
                            .font(.app(.callout))
                    }

                    // Editable command
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        if runsOnBoxd {
                            Text("on machine \(selectedMachineLabel)")
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                            if createWorktree && isGitRepo && assistant.supportsWorktree {
                                Text("The worktree is created on the machine and on this Mac, so the command has no --worktree flag.")
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        CommandTextEditor(text: $command, onSubmit: submitForm, onEscape: { isPresented = false })
                            .font(.app(.caption).monospaced())
                            .frame(minHeight: 36, maxHeight: 120)
                            .padding(4)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            .onChange(of: command) {
                                if generatedCommands.isEdit(command) {
                                    commandEdited = true
                                }
                            }
                    }
                }
                .padding(20)
            }

            // Buttons pinned outside scroll area
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(isResume ? "Resume" : "Launch", action: submitForm)
                .keyboardShortcut(.defaultAction)
                .disabled(!isResume && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .frame(width: 500)
        .frame(maxHeight: 700)
        .onAppear {
            applyPreviewToCommand()
        }
        .task { await reloadServices() }
        .onReceive(NotificationCenter.default.publisher(for: .kanbanCodeSettingsChanged)) { _ in
            Task { await reloadServices() }
        }
        .onChange(of: prompt) {
            refreshCommand()
        }
        .onChange(of: selectedLauncher) {
            refreshCommand()
        }
        .onChange(of: runRemotely) {
            rememberRunRemotely()
            refreshCommand()
        }
        .onChange(of: machineChoice) {
            refreshCommand()
        }
        .onChange(of: createWorktree) {
            UserDefaults.standard.set(createWorktree, forKey: "createWorktree_\(projectPath)")
            refreshCommand()
        }
        .onChange(of: worktreeBranch) {
            refreshCommand()
        }
        .onChange(of: dangerouslySkipPermissions) {
            refreshCommand()
        }
    }

    // MARK: - Remote row

    @ViewBuilder
    private var remoteSection: some View {
        if remoteMode.runsOnMachines, canRunRemotely, let remoteOptions {
            RunTargetPicker(remote: remoteOptions, runRemotely: $runRemotely, machineChoice: $machineChoice)
        } else {
            Toggle(remoteToggleLabel, isOn: canRunRemotely ? $runRemotely : .constant(false))
                .font(.app(.callout))
                .disabled(!canRunRemotely)
        }

        if let hint = remoteHint {
            Label(hint, systemImage: "info.circle")
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }

        if isResume, let machine = remoteOptions?.cardMachine {
            Text("Machine \(machine): \(remoteOptions?.cardMachineState?.label ?? "unknown")")
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            if !effectiveRunRemotely {
                Label("Continues locally from the mirrored transcript. The machine is kept.", systemImage: "info.circle")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }

        if runsOnBoxd, let machine = remoteOptions?.cardMachine,
           remoteOptions?.boxd?.sshMachine(named: machine) == nil, let onRemoveMachine {
            Button("Remove machine", role: .destructive, action: onRemoveMachine)
                .controlSize(.small)
                .padding(.leading, 20)
        }
    }

    private var selectedMachineLabel: String {
        machineChoice.machineName ?? "new machine"
    }

    private var remoteToggleLabel: String {
        switch remoteMode {
        case .ssh: "Run on an ssh machine"
        case .boxd: "Run on boxd"
        case .mutagen: "Run remotely"
        }
    }

    private var remoteHint: String? {
        guard !canRunRemotely else { return nil }
        switch remoteMode {
        case .ssh:
            return "Add an ssh machine in Settings > Remote"
        case .boxd:
            if remoteOptions?.boxd == nil { return "Configure boxd in Settings > Remote" }
            return "Install the boxd CLI to run on boxd"
        case .mutagen:
            if remoteOptions?.mutagen != nil { return "Project not under remote sync path" }
            return "Configure remote execution in Settings > Remote"
        }
    }

    private func rememberRunRemotely() {
        // A card that already has a machine keeps the toggle on by itself, so
        // its value is not the project default.
        guard remoteOptions?.cardMachine == nil, remoteOptions?.ownerMachine == nil else { return }
        RemoteLaunchOptions.rememberRunRemotely(runRemotely, mode: remoteMode, projectPath: projectPath)
    }

    // MARK: - Actions

    private func reloadServices() async {
        let loaded = (try? await settingsStore.read()) ?? Settings()
        settings = loaded
        applyDefaultLauncher()
        apiServices = loaded.apiServices
        // If the current selection still exists keep it; otherwise fall back to default.
        let currentStillValid = selectedServiceId.flatMap { id in
            apiServices.first { $0.id == id }
        } != nil
        if !currentStillValid {
            selectedServiceId = initialServiceId == nil
                ? loaded.defaultAPIServiceIds[assistant.rawValue]
                : nil
        }
        refreshCommand()
    }

    /// Preselects the launcher of the project's profile for a launch, until the
    /// card or the user has chosen one (a choice whose launcher was deleted in
    /// Settings is dropped). A resume keeps the card's command.
    private func applyDefaultLauncher() {
        guard !isResume else { return }
        let pickStillListed = selectedLauncher == ClaudeLauncherResolver.plain
            || settings.claudeLaunchers.contains { $0.command == selectedLauncher }
        guard !(launcherPicked && pickStillListed) else { return }
        selectedLauncher = ClaudeLauncherResolver.defaultCommand(
            forProjectPath: projectPath,
            profiles: settings.claudeProfiles,
            launchers: settings.claudeLaunchers)
    }

    private func submitForm() {
        if !isResume {
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        }
        let override = commandEdited ? command : nil
        // A resume keeps the card's own command, which the engine reads.
        let launcherCommand = isResume ? nil : ClaudeLauncherResolver.choice(
            commandEdited: commandEdited,
            command: command,
            selected: selectedLauncher,
            assistant: assistant,
            runsRemotely: effectiveRunRemotely,
            launchers: settings.claudeLaunchers)
        let branch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if runsOnBoxd {
            onMachineChoice(machineChoice)
            if remoteOptions?.cardMachine == nil, remoteOptions?.ownerMachine == nil {
                RemoteLaunchOptions.rememberMachineChoice(machineChoice, projectPath: projectPath)
            }
        }
        onLaunch(prompt, effectiveCreateWorktree, branch.isEmpty ? nil : branch, effectiveRunRemotely, dangerouslySkipPermissions, override, images, selectedServiceId, launcherCommand)
        isPresented = false
    }

    // MARK: - Computed

    private var remoteMode: RemoteMode {
        remoteOptions?.mode ?? .mutagen
    }

    private var canRunRemotely: Bool {
        remoteOptions?.canRunRemotely(projectPath: projectPath) ?? hasRemoteConfig
    }

    private var effectiveCreateWorktree: Bool {
        !isResume && !hasExistingWorktree && createWorktree && isGitRepo && assistant.supportsWorktree
    }

    private var effectiveRunRemotely: Bool {
        runRemotely && canRunRemotely
    }

    /// True when the session runs on a machine: an ssh machine or boxd.
    private var runsOnBoxd: Bool {
        remoteMode.runsOnMachines && effectiveRunRemotely
    }

    /// Puts the current preview in the field, and remembers it as the form's own.
    private func applyPreviewToCommand() {
        let preview = commandPreview
        generatedCommands.record(preview)
        command = preview
    }

    /// Follows the options while the user has not edited the command.
    private func refreshCommand() {
        if !commandEdited { applyPreviewToCommand() }
    }

    private var commandPreview: String {
        var parts: [String] = []

        if effectiveRunRemotely && remoteMode == .mutagen {
            parts.append("SHELL=~/.kanban-code/remote/zsh")
            if assistant.requiresRemotePathWrapper {
                parts.append("PATH=~/.kanban-code/remote:$PATH")
            }
        }

        let template = settings.commandTemplate(for: assistant, remote: effectiveRunRemotely)
        let service = selectedServiceId.flatMap { id in apiServices.first { $0.id == id } }
        // Remote runs always use plain `claude`.
        let binaryOverride: String? = assistant == .claude && !effectiveRunRemotely ? selectedLauncher : nil
        if isResume, let sid = sessionId {
            let resumeCmd = assistant.resumeCommand(
                sessionId: sid,
                skipPermissions: dangerouslySkipPermissions,
                service: service,
                modelOverride: modelOverride,
                binaryOverride: binaryOverride
            )
            let templated = CodingAssistant.applyCommandTemplate(resumeCmd, template: template)
            parts.append("cd \(projectPath) && \(templated)")
        } else {
            let branch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveWorktreeName: String?
            // On boxd the app creates the worktree, so the command carries no
            // worktree flag.
            if effectiveCreateWorktree && !runsOnBoxd {
                effectiveWorktreeName = (worktreeName?.isEmpty == false) ? worktreeName : branch
            } else {
                effectiveWorktreeName = nil
            }
            let launchCmd = assistant.launchCommand(
                skipPermissions: dangerouslySkipPermissions,
                worktreeName: effectiveWorktreeName,
                service: service,
                modelOverride: modelOverride,
                binaryOverride: binaryOverride
            )
            parts.append(CodingAssistant.applyCommandTemplate(launchCmd, template: template))
        }

        return parts.joined(separator: " \\\n  ")
    }

    static func truncatePrompt(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.components(separatedBy: .newlines)
            .joined(separator: " ")
        if singleLine.count <= maxLength { return singleLine }
        return String(singleLine.prefix(maxLength)) + "..."
    }
}
