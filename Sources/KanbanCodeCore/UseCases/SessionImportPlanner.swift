import Foundation

/// One session the Import dialog can bring onto the board.
public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    /// A running instance: the name Claude gave it. Else the session's own title.
    public let title: String
    public let projectPath: String?
    /// The profile whose `projects` folder holds the transcript.
    public let profilePath: String?
    public let transcriptPath: String
    public let modifiedTime: Date
    public let messageCount: Int
    public let isRunning: Bool

    public init(
        sessionId: String, title: String, projectPath: String?, profilePath: String?,
        transcriptPath: String, modifiedTime: Date, messageCount: Int, isRunning: Bool
    ) {
        self.sessionId = sessionId
        self.title = title
        self.projectPath = projectPath
        self.profilePath = profilePath
        self.transcriptPath = transcriptPath
        self.modifiedTime = modifiedTime
        self.messageCount = messageCount
        self.isRunning = isRunning
    }
}

/// Finished sessions of one project in one profile.
public struct ImportGroup: Identifiable, Equatable, Sendable {
    public var id: String { (projectPath ?? "") + "|" + (profilePath ?? "") }
    public let projectPath: String?
    public let profilePath: String?
    /// Newest first.
    public let candidates: [ImportCandidate]

    public init(projectPath: String?, profilePath: String?, candidates: [ImportCandidate]) {
        self.projectPath = projectPath
        self.profilePath = profilePath
        self.candidates = candidates
    }
}

public struct ImportOffer: Equatable, Sendable {
    /// Newest first.
    public let running: [ImportCandidate]
    /// Ordered by the newest session of each group.
    public let finished: [ImportGroup]
    /// What is ticked when the dialog opens.
    public let defaultSelection: Set<String>
}

public enum SessionImportPlanner {
    /// What the dialog offers: the running instances that have a transcript,
    /// and the other sessions grouped by project and profile. Headless runs,
    /// other assistants and `excludedSessionIds` are left out.
    /// `ProfileSessionDiscovery` already keeps one copy of a transcript found
    /// in two profiles (the newer one), so none is listed twice.
    public static func plan(
        sessions: [Session], running: [RunningSession],
        excludedSessionIds: Set<String>, defaultPerGroup: Int = 10
    ) -> ImportOffer {
        let usable = sessions.filter {
            $0.assistant == .claude && !$0.isHeadless && $0.jsonlPath != nil
                && !excludedSessionIds.contains($0.id)
        }
        let byId = Dictionary(usable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var runningCandidates: [ImportCandidate] = []
        var runningIds = Set<String>()
        for instance in running {
            guard let session = byId[instance.sessionId], runningIds.insert(instance.sessionId).inserted
            else { continue }
            let title = instance.name.flatMap { $0.isEmpty ? nil : $0 } ?? title(of: session)
            runningCandidates.append(candidate(session, title: title, isRunning: true))
        }
        runningCandidates.sort { $0.modifiedTime > $1.modifiedTime }

        let finishedSessions = usable.filter { !runningIds.contains($0.id) }
        let grouped = Dictionary(grouping: finishedSessions) {
            GroupKey(projectPath: $0.projectPath, profilePath: $0.configDirectory)
        }
        let groups: [ImportGroup] = grouped.map { key, members in
            let candidates = members
                .sorted { $0.modifiedTime > $1.modifiedTime }
                .map { candidate($0, title: title(of: $0), isRunning: false) }
            return ImportGroup(projectPath: key.projectPath, profilePath: key.profilePath, candidates: candidates)
        }
        .sorted {
            let a = $0.candidates.first?.modifiedTime ?? .distantPast
            let b = $1.candidates.first?.modifiedTime ?? .distantPast
            return a != b ? a > b : $0.id < $1.id
        }

        var selection = Set(runningCandidates.map(\.sessionId))
        for group in groups {
            selection.formUnion(group.candidates.prefix(defaultPerGroup).map(\.sessionId))
        }
        return ImportOffer(running: runningCandidates, finished: groups, defaultSelection: selection)
    }

    /// The card an import makes. `.manual` and named, so discovery-only
    /// archiving keeps it; its column is left to `AssignColumn`.
    public static func makeLink(_ candidate: ImportCandidate, now: Date = .now) -> Link {
        Link(
            name: candidate.title,
            projectPath: candidate.projectPath,
            column: .allSessions,
            createdAt: now,
            updatedAt: now,
            lastActivity: candidate.modifiedTime,
            source: .manual,
            sessionLink: SessionLink(sessionId: candidate.sessionId, sessionPath: candidate.transcriptPath))
    }

    // MARK: - Private

    private struct GroupKey: Hashable {
        let projectPath: String?
        let profilePath: String?
    }

    private static func candidate(_ session: Session, title: String, isRunning: Bool) -> ImportCandidate {
        ImportCandidate(
            sessionId: session.id, title: title, projectPath: session.projectPath,
            profilePath: session.configDirectory, transcriptPath: session.jsonlPath ?? "",
            modifiedTime: session.modifiedTime, messageCount: session.messageCount,
            isRunning: isRunning)
    }

    /// Never empty: an empty name would make the card discovery-only again.
    private static func title(of session: Session) -> String {
        if let name = session.name, !name.isEmpty { return name }
        if let prompt = session.firstPrompt {
            let text = InjectedPromptText.strip(prompt)
            if !text.isEmpty { return String(text.prefix(100)) }
        }
        return "Session " + session.id.prefix(8)
    }
}
