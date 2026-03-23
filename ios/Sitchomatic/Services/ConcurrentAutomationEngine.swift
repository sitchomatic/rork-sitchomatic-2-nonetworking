import Foundation
import WebKit

nonisolated enum EngineState: String, Sendable {
    case idle
    case preWarming
    case preparing
    case running
    case paused
    case stopping
    case completed
    case failed
    case cancelled

    var isActive: Bool { self == .running || self == .paused || self == .preparing || self == .preWarming }

    var displayName: String { rawValue.capitalized }

    var iconName: String {
        switch self {
        case .idle: "circle"
        case .preWarming: "flame"
        case .preparing: "gearshape"
        case .running: "play.fill"
        case .paused: "pause.fill"
        case .stopping: "stop.fill"
        case .completed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "slash.circle"
        }
    }
}

nonisolated struct PreWarmResult: Sendable {
    let sessionsReady: Int
    let sessionsFailed: Int
    let durationMs: Int
}

@Observable
@MainActor
final class ConcurrentAutomationEngine {
    static let shared = ConcurrentAutomationEngine()

    private(set) var state: EngineState = .idle
    private(set) var sessions: [ConcurrentSession] = []
    private(set) var engineLog: [SessionLogLine] = []
    private(set) var currentWave: Int = 0
    private(set) var totalWaves: Int = 0
    private(set) var startTime: Date?
    private(set) var preWarmResult: PreWarmResult?
    private(set) var retryQueue: [LoginCredential] = []
    private(set) var lastWaveFailureRate: Double = 0

    private(set) var isPauseRequested: Bool = false
    private(set) var isAutoPaused: Bool = false
    private var runTask: Task<Void, Never>?
    private var preWarmTask: Task<Void, Never>?
    private var memoryWatchTask: Task<Void, Never>?

    private let orchestrator = PlaywrightOrchestrator.shared
    private let networkManager = SimpleNetworkManager.shared
    private let settings = AutomationSettings.shared
    private let backgroundService = BackgroundTaskService.shared
    private let crashProtection = CrashProtectionService.shared
    private let crashRecovery = WebViewCrashRecoveryService.shared
    private let sessionRecovery = SessionRecoveryService.shared
    private let lifetimeBudget = WebViewLifetimeBudgetService.shared
    private let pool = WebViewPool.shared
    private let fileStorage = PersistentFileStorageService.shared
    private let persistence = PersistenceService.shared
    private let logger = DebugLogger.shared
    private let haptics = HapticService.shared
    private let widgetService = WidgetDataService.shared

    var succeededCount: Int { sessions.filter { $0.phase == .succeeded }.count }
    var failedCount: Int { sessions.filter { $0.phase == .failed }.count }

    var noAccountCount: Int {
        sessions.filter { $0.dualResult?.outcome == .noAccount }.count
    }
    var permDisabledCount: Int {
        sessions.filter { $0.dualResult?.outcome == .permDisabled }.count
    }
    var tempDisabledCount: Int {
        sessions.filter { $0.dualResult?.outcome == .tempDisabled }.count
    }
    var unsureCount: Int {
        sessions.filter { $0.dualResult?.outcome == .unsure }.count
    }
    var errorCount: Int {
        sessions.filter { $0.dualResult?.outcome == .error }.count
    }
    var cancelledCount: Int { sessions.filter { $0.phase == .cancelled }.count }
    var activeCount: Int { sessions.filter { $0.phase.isActive }.count }
    var queuedCount: Int { sessions.filter { $0.phase == .queued }.count }
    var isRunning: Bool { state.isActive }
    var retryableCount: Int { retryQueue.count }

    var overallProgress: Double {
        guard !sessions.isEmpty else { return 0 }
        let terminal = sessions.filter { $0.phase.isTerminal }.count
        return Double(terminal) / Double(sessions.count)
    }

    var elapsedFormatted: String {
        guard let start = startTime else { return "0:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    var healthScore: Double {
        let memoryScore: Double = {
            switch crashProtection.memoryPressureLevel {
            case .safe: return 1.0
            case .elevated: return 0.7
            case .critical: return 0.3
            case .emergency: return 0.0
            }
        }()

        let crashScore: Double = {
            let count = crashProtection.crashCount
            if count == 0 { return 1.0 }
            if count <= 2 { return 0.7 }
            if count <= 5 { return 0.4 }
            return 0.1
        }()

        let successScore: Double = {
            let total = succeededCount + failedCount
            guard total > 0 else { return 1.0 }
            return Double(succeededCount) / Double(total)
        }()

        let recoveryScore = crashRecovery.recoverySuccessRate

        return (memoryScore * 0.3 + crashScore * 0.2 + successScore * 0.3 + recoveryScore * 0.2)
    }

    var effectiveConcurrency: Int {
        let suggested = crashProtection.suggestedConcurrency
        let configured = settings.maxConcurrentPairs
        return min(suggested, configured)
    }

    var engineDiagnostics: String {
        let mem = crashProtection.diagnosticSummary
        let budget = lifetimeBudget.diagnosticSummary
        let poolInfo = pool.diagnosticSummary
        let bg = backgroundService.diagnosticSummary
        return """
        State: \(state.displayName) | Wave: \(currentWave)/\(totalWaves) | Health: \(String(format: "%.0f", healthScore * 100))%
        Sessions: \(succeededCount)ok \(failedCount)fail \(activeCount)active \(queuedCount)queued
        Effective concurrency: \(effectiveConcurrency) (configured: \(settings.maxConcurrentPairs))
        \(mem)
        \(budget)
        Pool: \(poolInfo)
        \(bg)
        Retries queued: \(retryQueue.count) | Last wave fail rate: \(String(format: "%.0f", lastWaveFailureRate * 100))%
        PreWarm: \(preWarmResult.map { "\($0.sessionsReady) ready, \($0.sessionsFailed) failed (\($0.durationMs)ms)" } ?? "none")
        """
    }

    private init() {}

    // MARK: - Pre-Warming

    func preWarmSessions(credentialCount: Int) {
        guard state == .idle || state == .completed || state == .failed || state == .cancelled else { return }
        state = .preWarming
        log(.phase, "Pre-warming sessions for \(credentialCount) credential pairs")

        preWarmTask = Task { @MainActor in
            let startMs = CFAbsoluteTimeGetCurrent()

            let pairsNeeded = min(credentialCount, effectiveConcurrency)
            pool.preWarm(count: min(pairsNeeded * 2, 6), stealthEnabled: true)
            log(.phase, "Pre-warmed \(min(pairsNeeded * 2, 6)) WebViews in pool")

            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startMs) * 1000)
            preWarmResult = PreWarmResult(
                sessionsReady: pairsNeeded,
                sessionsFailed: 0,
                durationMs: durationMs
            )

            log(.network, "Pre-warm complete: \(pairsNeeded) ready (\(durationMs)ms)")
            state = .idle
        }
    }

    func cancelPreWarm() {
        preWarmTask?.cancel()
        preWarmTask = nil
        if state == .preWarming { state = .idle }
    }

    // MARK: - Dual Run (Permanent Dual Mode)

    func startDualRun(
        credentials: [LoginCredential],
        joeFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome,
        ignitionFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome
    ) {
        guard state == .idle || state == .completed || state == .failed || state == .cancelled else { return }

        let concurrency = effectiveConcurrency
        let enabledCredentials = credentials.filter { $0.isEnabled }
        guard !enabledCredentials.isEmpty else {
            log(.error, "No enabled credentials — aborting")
            return
        }

        state = .preparing
        sessions.removeAll()
        engineLog.removeAll()
        retryQueue.removeAll()
        currentWave = 0
        isPauseRequested = false
        isAutoPaused = false
        lastWaveFailureRate = 0
        startTime = Date()

        totalWaves = (enabledCredentials.count + concurrency - 1) / concurrency

        for (index, cred) in enabledCredentials.enumerated() {
            let waveIndex = index / concurrency
            sessions.append(ConcurrentSession(index: index, waveIndex: waveIndex, credential: cred))
        }

        log(.phase, "Dual run starting — \(enabledCredentials.count) credentials, \(concurrency) concurrent pairs, \(totalWaves) waves, health: \(String(format: "%.0f", healthScore * 100))%")
        haptics.runStart()

        sessionRecovery.saveCheckpoint(credentialIndex: 0, waveIndex: 0, phase: "starting")
        crashProtection.startMonitoring()

        backgroundService.beginBackgroundTask(identifier: "sitchomatic.engine") { [weak self] in
            Task { @MainActor in
                self?.log(.error, "Background task expiring — emergency persist + stop")
                self?.emergencyPersistState()
                self?.stop()
            }
        }

        startMemoryWatch()

        runTask = Task { @MainActor in
            await self.executeWaves(
                joeFlow: joeFlow,
                ignitionFlow: ignitionFlow
            )
        }
    }

    // MARK: - Recorded Script Run

    func startRecordedRun(config: WaveConfig) {
        guard state == .idle || state == .completed || state == .failed || state == .cancelled else { return }

        sessions.removeAll()
        engineLog.removeAll()
        currentWave = 0
        isPauseRequested = false
        isAutoPaused = false
        startTime = Date()

        let waveCount = Int(ceil(Double(config.totalSessions) / Double(config.concurrency)))
        totalWaves = waveCount

        for i in 0..<config.totalSessions {
            let waveIdx = i / config.concurrency
            let dummyCred = LoginCredential(username: "session-\(i)", password: "", displayName: "Session \(i)")
            sessions.append(ConcurrentSession(index: i, waveIndex: waveIdx, credential: dummyCred))
        }

        state = .preparing
        log(.phase, "Recorded run: \(config.totalSessions) sessions in \(waveCount) waves (concurrency: \(config.concurrency))")

        backgroundService.beginBackgroundTask(identifier: "sitchomatic.engine.recorded") { [weak self] in
            Task { @MainActor in
                self?.stop()
            }
        }

        runTask = Task { @MainActor in
            await self.executeRecordedWaves(config: config)
        }
    }

    // MARK: - Retry Failed

    func retryFailed(
        joeFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome,
        ignitionFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome
    ) {
        let retryable = retryQueue
        guard !retryable.isEmpty else {
            log(.phase, "No retryable credentials in queue")
            return
        }
        log(.phase, "Retrying \(retryable.count) failed credentials")
        retryQueue.removeAll()
        startDualRun(credentials: retryable, joeFlow: joeFlow, ignitionFlow: ignitionFlow)
    }

    // MARK: - Control

    func pause() {
        guard state == .running else { return }
        isPauseRequested = true
        state = .paused
        log(.phase, "Engine paused — active sessions will finish current step")
    }

    func resume() {
        guard state == .paused else { return }
        isPauseRequested = false
        isAutoPaused = false
        state = .running
        log(.phase, "Engine resumed")
    }

    func stop() {
        guard state.isActive || state == .stopping else { return }
        state = .stopping
        runTask?.cancel()
        preWarmTask?.cancel()
        memoryWatchTask?.cancel()

        for session in sessions where !session.phase.isTerminal {
            session.updatePhase(.cancelled)
        }

        orchestrator.closeAllPages()
        state = .cancelled
        backgroundService.endBackgroundTask(identifier: "sitchomatic.engine")
        backgroundService.endBackgroundTask(identifier: "sitchomatic.engine.recorded")
        sessionRecovery.clearCheckpoint()
        crashProtection.stopMonitoring()
        lifetimeBudget.reset()
        log(.result, "Engine stopped — \(succeededCount) success, \(failedCount) failed, \(cancelledCount) cancelled")
    }

    func enqueueRetry(_ credential: LoginCredential) {
        retryQueue.append(credential)
        log(.phase, "Manually enqueued retry for \(credential.displayName)")
    }

    func reset() {
        stop()
        sessions.removeAll()
        engineLog.removeAll()
        retryQueue.removeAll()
        preWarmResult = nil
        currentWave = 0
        totalWaves = 0
        startTime = nil
        lastWaveFailureRate = 0
        isAutoPaused = false
        crashProtection.resetCrashHistory()
        crashRecovery.reset()
        lifetimeBudget.reset()
        state = .idle
    }

    // MARK: - Private: Memory Watch (Auto-Pause)

    private func startMemoryWatch() {
        memoryWatchTask?.cancel()
        memoryWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { break }

                if self.crashProtection.isMemoryEmergency && self.state == .running && !self.isAutoPaused {
                    self.isAutoPaused = true
                    self.isPauseRequested = true
                    self.state = .paused
                    self.haptics.autoPauseWarning()
                    self.log(.error, "AUTO-PAUSE: Memory emergency (\(String(format: "%.0f", self.crashProtection.currentMemoryUsageMB))MB) — pausing engine")
                    self.pool.handleMemoryPressure()
                }

                if self.isAutoPaused && self.crashProtection.isMemorySafeForNewSession {
                    self.isAutoPaused = false
                    self.isPauseRequested = false
                    self.state = .running
                    self.log(.phase, "AUTO-RESUME: Memory recovered — resuming engine")
                }
            }
        }
    }

    // MARK: - Private: Dual Wave Execution

    private func executeWaves(
        joeFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome,
        ignitionFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome
    ) async {
        state = .running

        if !orchestrator.isReady {
            do {
                try await orchestrator.startSession(speedMode: settings.speedMode)
            } catch {
                state = .failed
                log(.error, "Failed to start orchestrator: \(error.localizedDescription)")
                backgroundService.endBackgroundTask(identifier: "sitchomatic.engine")
                return
            }
        }

        let waveCount = totalWaves
        for waveIdx in 0..<waveCount {
            guard !Task.isCancelled else { break }

            while isPauseRequested && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { break }

            if crashProtection.isInCooldown {
                log(.phase, "Waiting for crash cooldown (\(String(format: "%.0f", crashProtection.cooldownRemainingSeconds))s)...")
                await crashProtection.waitForCooldown()
            }

            if crashProtection.shouldReduceConcurrency {
                log(.phase, "Memory pressure detected — inserting cooldown before wave \(waveIdx + 1)")
                pool.handleMemoryPressure()
                try? await Task.sleep(for: .seconds(3))

                if !crashProtection.isMemorySafeForNewSession {
                    let recovered = await crashProtection.waitForMemoryToDrop(timeout: 15)
                    if !recovered {
                        log(.error, "Memory did not recover — proceeding with reduced concurrency")
                    }
                }
            }

            if backgroundService.isBackgroundTimeLow {
                log(.phase, "Background time low — pausing after current wave")
                isPauseRequested = true
                state = .paused
                emergencyPersistState()
                continue
            }

            lifetimeBudget.beginNewWave()
            currentWave = waveIdx + 1
            let waveSessions = sessions.filter { $0.waveIndex == waveIdx }
            log(.phase, "Wave \(waveIdx + 1)/\(waveCount) — \(waveSessions.count) paired sessions (eff. concurrency: \(effectiveConcurrency))")

            sessionRecovery.saveFullCheckpoint(EngineCheckpoint(
                waveIndex: waveIdx,
                credentialIndex: waveSessions.first?.index ?? 0,
                phase: "running",
                completedCredentialIDs: sessions.filter { $0.phase == .succeeded }.map { $0.credential.id.uuidString },
                failedCredentialIDs: sessions.filter { $0.phase == .failed }.map { $0.credential.id.uuidString },
                pendingCredentialIDs: sessions.filter { !$0.phase.isTerminal }.map { $0.credential.id.uuidString },
                timestamp: Date(),
                engineState: state.rawValue,
                succeededCount: succeededCount,
                failedCount: failedCount
            ))

            await withTaskGroup(of: Void.self) { group in
                for session in waveSessions {
                    group.addTask { @MainActor in
                        await self.executePairedSession(
                            session,
                            joeFlow: joeFlow,
                            ignitionFlow: ignitionFlow
                        )
                    }
                }
            }

            let waveSucceeded = waveSessions.filter { $0.phase == .succeeded }.count
            let waveFailed = waveSessions.filter { $0.phase == .failed }.count
            lastWaveFailureRate = waveSessions.isEmpty ? 0 : Double(waveFailed) / Double(waveSessions.count)
            log(.result, "Wave \(waveIdx + 1) complete — \(waveSucceeded) succeeded, \(waveFailed) failed (health: \(String(format: "%.0f", healthScore * 100))%)")
            haptics.waveComplete()

            let retryableSessions = waveSessions.filter { session in
                guard let result = session.dualResult else { return false }
                return result.outcome.shouldRetry
            }
            if !retryableSessions.isEmpty && settings.autoRetryOnFailure {
                let retryCredentials = retryableSessions.map { $0.credential }
                retryQueue.append(contentsOf: retryCredentials)
                log(.phase, "Added \(retryCredentials.count) credentials to retry queue")
            }

            persistWaveResults(waveSessions)

            if waveIdx < waveCount - 1 && !Task.isCancelled {
                var delay = settings.interWaveDelaySeconds
                if lastWaveFailureRate > 0.5 {
                    delay *= 2.0
                    log(.phase, "High failure rate (\(String(format: "%.0f", lastWaveFailureRate * 100))%) — doubling inter-wave delay")
                }
                let jitter = Double.random(in: 0...0.5)
                log(.phase, "Inter-wave delay: \(String(format: "%.1f", delay + jitter))s")
                try? await Task.sleep(for: .seconds(delay + jitter))
            }
        }

        if !Task.isCancelled {
            state = .completed
            sessionRecovery.clearCheckpoint()
            crashProtection.stopMonitoring()
            memoryWatchTask?.cancel()
            haptics.engineCompleted()
            widgetService.updateFromEngine(self)
            log(.result, "Run complete — \(succeededCount) success, \(noAccountCount) no acc, \(permDisabledCount) perm, \(tempDisabledCount) temp, \(unsureCount) unsure, \(errorCount) error | health: \(String(format: "%.0f", healthScore * 100))%")
        }

        backgroundService.endBackgroundTask(identifier: "sitchomatic.engine")
    }

    private func executePairedSession(
        _ session: ConcurrentSession,
        joeFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome,
        ignitionFlow: @escaping @Sendable @MainActor (PlaywrightPage, LoginCredential, SpeedMode) async throws -> DualLoginOutcome
    ) async {
        session.updatePhase(.launching)

        if crashRecovery.isCredentialBlacklisted(session.credential.id.uuidString) {
            session.setError("Credential temporarily blacklisted due to repeated crashes")
            session.updatePhase(.failed)
            log(.error, "Skipping blacklisted credential: \(session.credential.displayName)")
            return
        }

        guard lifetimeBudget.recordCreation(), lifetimeBudget.recordCreation() else {
            session.setError("WebView lifetime budget exhausted")
            session.updatePhase(.failed)
            lifetimeBudget.recordDestruction()
            return
        }

        if crashProtection.isMemoryEmergency {
            log(.error, "Memory EMERGENCY — skipping credential \(session.credential.displayName)")
            session.setError("Memory emergency — session skipped")
            session.updatePhase(.failed)
            lifetimeBudget.recordDestruction()
            lifetimeBudget.recordDestruction()
            return
        }

        let backoff = crashRecovery.backoffDuration(for: session.credential.id.uuidString)
        if backoff > 0 {
            log(.phase, "Backoff \(String(format: "%.1f", backoff))s for \(session.credential.displayName)")
            try? await Task.sleep(for: .seconds(backoff))
        }

        var attempt = 0
        let maxAttempts = settings.autoRetryOnFailure ? settings.maxRetryAttempts : 1

        while attempt < maxAttempts && !Task.isCancelled {
            attempt += 1

            if attempt > 1 {
                let backoffMs = min(1000 * attempt, 5000) + Int.random(in: 0...500)
                log(.phase, "Retry attempt \(attempt)/\(maxAttempts) for \(session.credential.displayName) — backoff \(backoffMs)ms")
                session.updatePhase(.launching)
                try? await Task.sleep(for: .milliseconds(backoffMs))
            }

            let result = await orchestrator.executeDualLogin(
                credential: session.credential,
                joeURL: settings.joeURL,
                ignitionURL: settings.ignitionURL,
                joeFlow: joeFlow,
                ignitionFlow: ignitionFlow
            )

            session.updateProxy(result.proxyUsed)
            session.setDualResult(result)

            if let joeScreen = result.joeScreenshot { session.setJoeScreenshot(joeScreen) }
            if let ignScreen = result.ignitionScreenshot { session.setIgnitionScreenshot(ignScreen) }

            switch result.outcome {
            case .success:
                session.updatePhase(.succeeded)
                lifetimeBudget.recordDestruction()
                lifetimeBudget.recordDestruction()
                crashRecovery.recordRecoverySuccess(pageID: session.credential.id.uuidString)
                haptics.credentialSuccess()
                session.log(.result, "\(result.outcome.longName) (joe: \(result.joeOutcome.shortName), ignition: \(result.ignitionOutcome.shortName), \(String(format: "%.1f", result.duration))s)")
                updateCredentialResult(session.credential, outcome: result)
                return

            case .noAccount:
                session.setError(result.errorMessage ?? "No account found")
                session.updatePhase(.failed)
                lifetimeBudget.recordDestruction()
                lifetimeBudget.recordDestruction()
                haptics.credentialFailure()
                session.log(.result, "\(result.outcome.longName) — no retry")
                updateCredentialResult(session.credential, outcome: result)
                return

            case .permDisabled:
                session.setError(result.errorMessage ?? "Permanently disabled")
                session.updatePhase(.failed)
                lifetimeBudget.recordDestruction()
                lifetimeBudget.recordDestruction()
                haptics.credentialFailure()
                session.log(.result, "\(result.outcome.longName) — no retry")
                updateCredentialResult(session.credential, outcome: result)
                return

            case .tempDisabled, .error:
                if attempt >= maxAttempts {
                    session.setError(result.errorMessage ?? result.outcome.shortName)
                    session.updatePhase(.failed)
                    lifetimeBudget.recordDestruction()
                    lifetimeBudget.recordDestruction()
                    session.log(.result, "\(result.outcome.longName) — max retries exhausted")
                    crashRecovery.recordRecoveryFailure(pageID: session.credential.id.uuidString)
                    updateCredentialResult(session.credential, outcome: result)
                    return
                }

                if result.outcome == .error {
                    crashRecovery.recordRecovery(pageID: session.credential.id.uuidString, phase: "paired-session")
                    crashProtection.recordCrash()
                    pool.reportProcessTermination()
                }

                session.log(.phase, "Attempt \(attempt): \(result.outcome.shortName) — will retry")
                continue

            case .unsure:
                session.setError(result.errorMessage ?? "Needs review")
                session.updatePhase(.failed)
                lifetimeBudget.recordDestruction()
                lifetimeBudget.recordDestruction()
                haptics.credentialFailure()
                session.log(.result, "\(result.outcome.longName) — joe: \(result.joeOutcome.shortName), ignition: \(result.ignitionOutcome.shortName)")
                updateCredentialResult(session.credential, outcome: result)
                return
            }
        }
    }

    // MARK: - Private: Credential Result Tracking

    private func updateCredentialResult(_ credential: LoginCredential, outcome: DualLoginResult) {
        var credentials = persistence.loadCredentials()
        guard let idx = credentials.firstIndex(where: { $0.id == credential.id }) else { return }

        credentials[idx].totalAttempts += 1
        credentials[idx].lastAttemptDate = Date()
        credentials[idx].lastOutcome = outcome.outcome.rawValue

        if outcome.outcome == .success {
            credentials[idx].successCount += 1
        } else {
            credentials[idx].failCount += 1
        }

        persistence.saveCredentials(credentials)

        let attempt = LoginAttempt(
            credentialID: credential.id,
            outcome: outcome.outcome.rawValue,
            joeOutcome: outcome.joeOutcome.rawValue,
            ignitionOutcome: outcome.ignitionOutcome.rawValue,
            duration: outcome.duration,
            proxyUsed: outcome.proxyUsed,
            errorMessage: outcome.errorMessage,
            speedMode: settings.speedMode.rawValue
        )
        var attempts = persistence.loadAttempts()
        attempts.append(attempt)
        if attempts.count > 1000 {
            attempts = Array(attempts.suffix(1000))
        }
        persistence.saveAttempts(attempts)
        widgetService.updateFromEngine(self)
    }

    private func persistWaveResults(_ waveSessions: [ConcurrentSession]) {
        for session in waveSessions where session.phase.isTerminal {
            if let result = session.dualResult {
                let summary = "\(session.credential.displayName): \(result.outcome.shortName) (joe: \(result.joeOutcome.shortName), ign: \(result.ignitionOutcome.shortName), \(String(format: "%.1f", result.duration))s)"
                fileStorage.save(text: summary, filename: "results/wave-\(session.waveIndex)/\(session.credential.id.uuidString).txt")
            }
        }
    }

    // MARK: - Private: Recorded Wave Execution

    private func executeRecordedWaves(config: WaveConfig) async {
        state = .running
        log(.phase, "Starting recorded wave execution")

        if !orchestrator.isReady {
            do {
                try await orchestrator.startSession(speedMode: settings.speedMode)
            } catch {
                state = .failed
                log(.error, "Failed to start orchestrator: \(error.localizedDescription)")
                backgroundService.endBackgroundTask(identifier: "sitchomatic.engine.recorded")
                return
            }
        }

        let waveCount = totalWaves
        for waveIdx in 0..<waveCount {
            guard !Task.isCancelled else { break }

            while isPauseRequested && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { break }

            currentWave = waveIdx + 1
            let waveSessions = sessions.filter { $0.waveIndex == waveIdx }
            log(.phase, "Wave \(waveIdx + 1)/\(waveCount) — launching \(waveSessions.count) sessions")

            await withTaskGroup(of: Void.self) { group in
                for session in waveSessions {
                    group.addTask { @MainActor in
                        await self.executeRecordedSession(session, config: config)
                    }
                }
            }

            let waveSucceeded = waveSessions.filter { $0.phase == .succeeded }.count
            let waveFailed = waveSessions.filter { $0.phase == .failed }.count
            log(.result, "Wave \(waveIdx + 1) complete — \(waveSucceeded) succeeded, \(waveFailed) failed")

            if waveIdx < waveCount - 1 && !Task.isCancelled {
                log(.phase, "Waiting \(Int(config.delayBetweenWaves))s before next wave")
                try? await Task.sleep(for: .seconds(config.delayBetweenWaves))
            }
        }

        if !Task.isCancelled {
            state = .completed
            log(.result, "Recorded run complete — \(succeededCount)/\(sessions.count) succeeded, \(failedCount) failed")
        }

        backgroundService.endBackgroundTask(identifier: "sitchomatic.engine.recorded")
    }

    private func executeRecordedSession(_ session: ConcurrentSession, config: WaveConfig) async {
        session.updatePhase(.launching)

        session.updateProxy("NordVPN (External)")
        session.log(.network, "Network: NordVPN external")

        let page: PlaywrightPage
        do {
            page = try await orchestrator.newPage()
        } catch {
            session.setError("Failed to create page: \(error.localizedDescription)")
            session.updatePhase(.failed)
            return
        }

        do {
            switch config.script {
            case .recorded(let actions):
                try await executeRecordedActions(actions, on: page, session: session, config: config)
            case .custom(let block):
                session.updatePhase(.running)
                try await block(page)
                session.updatePhase(.succeeded)
            }
        } catch is CancellationError {
            session.updatePhase(.cancelled)
        } catch {
            session.setError(error.localizedDescription)
            session.updatePhase(.failed)

            if config.captureScreenshots {
                if let screenshot = try? await page.screenshot() {
                    session.setJoeScreenshot(screenshot)
                }
            }
        }

        orchestrator.closePage(page)
    }

    private func executeRecordedActions(
        _ actions: [RecordedAction],
        on page: PlaywrightPage,
        session: ConcurrentSession,
        config: WaveConfig
    ) async throws {
        session.updateProgress(completed: 0, total: actions.count)

        for (index, action) in actions.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            while isPauseRequested && !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(200))
            }

            let speed = settings.speedMode

            switch action.kind {
            case .navigation:
                session.updatePhase(.navigating)
                if let url = action.value {
                    session.updateURL(url)
                    session.log(.action, "goto(\(url))")
                    try await page.goto(url)
                    try await Task.sleep(for: .milliseconds(speed.actionDelayWithVariance()))
                }

            case .click:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "click(\(selector))")
                    try await page.locator(selector).click()
                    try await Task.sleep(for: .milliseconds(speed.actionDelayWithVariance()))
                }

            case .fill:
                session.updatePhase(.fillingForm)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "fill(\(selector), \(String(value.prefix(20))))")
                    try await page.locator(selector).fill(value)
                    try await Task.sleep(for: .milliseconds(speed.typingDelayWithVariance()))
                }

            case .check:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "check(\(selector))")
                    try await page.locator(selector).check()
                    try await Task.sleep(for: .milliseconds(speed.actionDelayWithVariance()))
                }

            case .uncheck:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "uncheck(\(selector))")
                    try await page.locator(selector).uncheck()
                    try await Task.sleep(for: .milliseconds(speed.actionDelayWithVariance()))
                }

            case .select:
                session.updatePhase(.running)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "select(\(selector), \(value))")
                    try await page.locator(selector).selectOption(value)
                    try await Task.sleep(for: .milliseconds(speed.actionDelayWithVariance()))
                }

            case .pressEnter:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "press Enter on \(selector)")
                    try await page.locator(selector).type("Enter")
                    try await Task.sleep(for: .milliseconds(speed.postSubmitWaitMs))
                }

            case .assertVisible:
                session.updatePhase(.asserting)
                if let selector = action.selector {
                    session.log(.action, "expect(\(selector)).toBeVisible()")
                    try await page.expect(page.locator(selector)).toBeVisible()
                }

            case .assertText:
                session.updatePhase(.asserting)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "expect(\(selector)).toContainText(\(value))")
                    try await page.expect(page.locator(selector)).toContainText(value)
                }

            case .assertValue:
                session.updatePhase(.asserting)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "expect(\(selector)).toHaveValue(\(value))")
                    try await page.expect(page.locator(selector)).toHaveValue(value)
                }

            case .waitForTimeout:
                session.updatePhase(.waitingForElement)
                if let ms = action.value.flatMap({ Int($0) }) {
                    session.log(.action, "wait \(ms)ms")
                    try await page.waitForTimeout(ms)
                }
            }

            session.updateProgress(completed: index + 1, total: actions.count)
            session.updateURL(page.url())

            if config.captureScreenshots && (action.kind == .navigation || index == actions.count - 1) {
                if let screenshot = try? await page.screenshot() {
                    session.setJoeScreenshot(screenshot)
                }
            }
        }

        session.updatePhase(.succeeded)
    }

    // MARK: - Private: Emergency State Persistence

    private func emergencyPersistState() {
        sessionRecovery.saveFullCheckpoint(EngineCheckpoint(
            waveIndex: currentWave - 1,
            credentialIndex: sessions.first(where: { $0.phase.isActive })?.index ?? 0,
            phase: "emergency",
            completedCredentialIDs: sessions.filter { $0.phase == .succeeded }.map { $0.credential.id.uuidString },
            failedCredentialIDs: sessions.filter { $0.phase == .failed }.map { $0.credential.id.uuidString },
            pendingCredentialIDs: sessions.filter { !$0.phase.isTerminal }.map { $0.credential.id.uuidString },
            timestamp: Date(),
            engineState: state.rawValue,
            succeededCount: succeededCount,
            failedCount: failedCount
        ))

        let stateDict: [String: String] = [
            "engineState": state.rawValue,
            "currentWave": "\(currentWave)",
            "totalWaves": "\(totalWaves)",
            "succeeded": "\(succeededCount)",
            "failed": "\(failedCount)",
            "active": "\(activeCount)",
            "healthScore": String(format: "%.2f", healthScore),
            "memoryMB": String(format: "%.0f", crashProtection.currentMemoryUsageMB),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: stateDict),
           let str = String(data: data, encoding: .utf8) {
            fileStorage.save(data: Data(str.utf8), filename: "engine_emergency_state.json")
            logger.log("Emergency engine state persisted", category: .automation, level: .critical)
        }
    }

    // MARK: - Private: Logging

    private func log(_ category: SessionLogLine.Category, _ message: String) {
        engineLog.append(SessionLogLine(timestamp: Date(), category: category, message: message))
        let level: DebugLogger.LogLevel = category == .error ? .error : .info
        logger.log("[Engine] \(message)", category: .automation, level: level)
    }
}

nonisolated enum AutomationScript: Sendable {
    case recorded([RecordedAction])
    case custom(@Sendable (PlaywrightPage) async throws -> Void)
}

nonisolated struct WaveConfig: Sendable {
    let concurrency: Int
    let delayBetweenWaves: TimeInterval
    let targetURL: String
    let script: AutomationScript
    let totalSessions: Int
    let captureScreenshots: Bool

    init(
        concurrency: Int = 3,
        delayBetweenWaves: TimeInterval = 2.0,
        targetURL: String = "",
        script: AutomationScript = .recorded([]),
        totalSessions: Int = 6,
        captureScreenshots: Bool = true
    ) {
        self.concurrency = max(1, min(concurrency, 12))
        self.delayBetweenWaves = delayBetweenWaves
        self.targetURL = targetURL
        self.script = script
        self.totalSessions = max(1, totalSessions)
        self.captureScreenshots = captureScreenshots
    }
}
