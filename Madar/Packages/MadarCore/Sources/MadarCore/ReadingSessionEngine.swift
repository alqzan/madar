import Foundation

/// R03: a paused segment remains pending until its owning command is acknowledged.
/// The command ID and payload stay fixed, including when a write succeeded but its caller lost the reply.
public struct PendingReadingSessionQueue: Equatable, Sendable {
    public struct Write: Equatable, Sendable {
        public let sessionID: UUID
        public let commandID: UUID
        public let payload: [String: JSONValue]
    }
    private var writes: [Write] = []
    private var attempt: (commandID: UUID, authorizationEpoch: Int)?
    private var failedEpoch: Int?
    public private(set) var authorizationEpoch = 0
    public var isEmpty: Bool { writes.isEmpty }
    public var canAttempt: Bool { !writes.isEmpty && attempt == nil && failedEpoch != authorizationEpoch }

    public init() {}

    public mutating func enqueue(sessionID: UUID, payload: [String: JSONValue], commandID: UUID = UUID()) {
        // Keep an attempted snapshot immutable, but retain a newer update for the same session.
        // Compare only its latest queued value: a later change back to an older value is still an update.
        guard writes.last(where: { $0.sessionID == sessionID })?.payload != payload else { return }
        writes.append(Write(sessionID: sessionID, commandID: commandID, payload: payload))
    }

    /// A new authorized foreground grants one retry after a failure, without replacing its command ID.
    public mutating func authorizedForegroundReturned() { authorizationEpoch += 1 }

    public mutating func beginNext() -> Write? {
        guard canAttempt, let write = writes.first else { return nil }
        attempt = (write.commandID, authorizationEpoch)
        return write
    }

    public mutating func finish(commandID: UUID, acknowledged: Bool) {
        guard let attempt, attempt.commandID == commandID else { return }
        self.attempt = nil
        if acknowledged {
            writes.removeAll { $0.commandID == commandID }
            failedEpoch = nil
        } else {
            // If access returned during the attempt, that newer authorization can retry it.
            failedEpoch = attempt.authorizationEpoch
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.writes == rhs.writes && lhs.attempt?.commandID == rhs.attempt?.commandID
            && lhs.attempt?.authorizationEpoch == rhs.attempt?.authorizationEpoch
            && lhs.failedEpoch == rhs.failedEpoch && lhs.authorizationEpoch == rhs.authorizationEpoch
    }
}

/// Counts only foreground reading activity within the agreed idle window.
public struct ActiveReadingClock: Equatable, Sendable {
    public private(set) var activeSeconds: Int = 0
    private var lastActivity: Date?
    private var lastTick: Date?
    private var foreground: Bool
    private var fractionalSeconds: TimeInterval = 0
    private let idleLimit: TimeInterval

    public init(startedAt: Date, foreground: Bool = true, idleLimit: TimeInterval = 5 * 60) {
        self.foreground = foreground
        self.idleLimit = max(0, idleLimit)
        lastActivity = foreground ? startedAt : nil
        lastTick = startedAt
    }

    public mutating func advance(to now: Date) {
        guard let lastTick else { return }
        defer { self.lastTick = now }
        guard foreground, let lastActivity, now > lastTick else { return }

        let start = max(lastTick, lastActivity)
        let end = min(now, lastActivity.addingTimeInterval(idleLimit))
        guard end > start else {
            if now >= lastActivity.addingTimeInterval(idleLimit) { self.lastActivity = nil }
            return
        }
        let total = fractionalSeconds + end.timeIntervalSince(start)
        let whole = Int(total.rounded(.down))
        activeSeconds += whole
        fractionalSeconds = total - Double(whole)
        if now >= lastActivity.addingTimeInterval(idleLimit) { self.lastActivity = nil }
    }

    public mutating func interaction(at now: Date) {
        advance(to: now)
        guard foreground else { return }
        lastActivity = now
        lastTick = now
    }

    public mutating func setForeground(_ isForeground: Bool, at now: Date) {
        advance(to: now)
        foreground = isForeground
        lastActivity = nil
        lastTick = isForeground ? now : nil
    }

    /// Starts a new stored segment without granting a new idle allowance.
    public mutating func startSegment(at now: Date) {
        advance(to: now)
        activeSeconds = 0
        fractionalSeconds = 0
    }
}

/// Counts forward positions once; explicit jumps and fast seeks do not count as reading.
public struct ReadingPositionProgress: Equatable, Sendable {
    public private(set) var pagesCounted = 0
    public private(set) var furthestPosition = 0
    private var previousPosition: Int?
    private var previousChange: Date?

    public init(startingAt position: Int? = nil, at date: Date? = nil) {
        previousPosition = position
        previousChange = date
        furthestPosition = max(0, position ?? 0)
    }

    public mutating func observe(position: Int, at date: Date, explicitJump: Bool = false) {
        guard position >= 0 else { return }
        guard let previousPosition else {
            self.previousPosition = position
            previousChange = date
            furthestPosition = max(furthestPosition, position)
            return
        }
        let delta = position - previousPosition
        if explicitJump || (delta > 0 && delta > 20 && previousChange.map { date.timeIntervalSince($0) < 60 } == true) {
            self.previousPosition = position
            previousChange = date
            furthestPosition = max(furthestPosition, position)
            return
        }
        if delta > 0, position > furthestPosition {
            pagesCounted += position - max(previousPosition, furthestPosition)
        }
        self.previousPosition = position
        previousChange = date
        furthestPosition = max(furthestPosition, position)
    }
}

/// R01: navigator positions are never page numbers. An unknown printed total stays unknown.
public enum ReadingPageEstimate {
    public static func page(progression: Double?, totalPages: Int?) -> Int? {
        guard let progression, progression.isFinite, (0...1).contains(progression),
              let totalPages, totalPages > 0 else { return nil }
        return Int((progression * Double(totalPages)).rounded(.down))
    }
}

/// R06: installed in the resource bytes before WebKit parses any author content.
public enum ReadingDocumentPolicy {
    public static let content = "default-src 'self' data: blob:; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self' data: blob:; media-src 'self' data: blob:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    /// EPUB XHTML must have a head. Reject malformed prefixes rather than serving them without a policy.
    /// This only scans the prolog and the two opening elements; it does not rewrite the book's content.
    public static func secure(_ source: String) -> String? {
        var cursor = source.startIndex
        var sawHTML = false
        while cursor < source.endIndex {
            if source[cursor].isWhitespace || source[cursor] == "\u{FEFF}" {
                cursor = source.index(after: cursor); continue
            }
            let tail = source[cursor...]
            if tail.hasPrefix("<!--") {
                guard let end = tail.range(of: "-->") else { return nil }
                cursor = end.upperBound; continue
            }
            if tail.hasPrefix("<?xml ") {
                guard !sawHTML, let end = tail.range(of: "?>") else { return nil }
                cursor = end.upperBound; continue
            }
            guard source[cursor] == "<" else { return nil }
            var end = source.index(after: cursor)
            var quote: Character?
            while end < source.endIndex {
                let character = source[end]
                if let active = quote { if character == active { quote = nil } }
                else if character == "\"" || character == "'" { quote = character }
                else if character == ">" { break }
                end = source.index(after: end)
            }
            guard end < source.endIndex else { return nil }
            let tag = String(source[source.index(after: cursor)..<end])
            if tag.lowercased().hasPrefix("!doctype ") {
                // Internal entities can expand into active markup before our policy.
                guard !sawHTML, !tag.contains("[") else { return nil }
                cursor = source.index(after: end); continue
            }
            guard let name = tag.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first else { return nil }
            if name.lowercased() == "html", !sawHTML { sawHTML = true }
            else if name.lowercased() == "head", sawHTML, !tag.hasSuffix("/") {
                let insertion = source.index(after: end)
                let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(content)\" />"
                return String(source[..<insertion]) + policy + String(source[insertion...])
            } else { return nil }
            cursor = source.index(after: end)
        }
        return nil
    }
}
