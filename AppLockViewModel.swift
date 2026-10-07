import Foundation
import LocalAuthentication
import Combine
import AppKit

@MainActor
final class AppLockViewModel: ObservableObject {
    static let shared = AppLockViewModel()

    @Published private(set) var isAuthenticating = false
    private var activeContext: LAContext?
    private var activeRequestID: UUID?
    private let makeContext: () -> LAContext

    init(makeContext: @escaping () -> LAContext = { LAContext() }) {
        self.makeContext = makeContext
    }

    static var isUITestUnlockEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITEST_DISABLE_LOCK") &&
            ProcessInfo.processInfo.arguments.contains("-UITEST_IN_MEMORY_STORE")
        #else
        false
        #endif
    }

    var permitsClinicalAccess: Bool { isUnlocked || Self.isUITestUnlockEnabled }

    @Published private(set) var isUnlocked = false
    @Published var lastErrorMessage: String?
    private var backgroundedAt: Date?

    func unlock() {
        guard !isUnlocked, !isAuthenticating else { return }
        lastErrorMessage = nil
        let context = makeContext()
        context.localizedCancelTitle = "Annulla"

        var authError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            lastErrorMessage = authError?.localizedDescription ?? "Autenticazione non disponibile su questo Mac."
            return
        }

        let requestID = UUID()
        activeContext = context
        activeRequestID = requestID
        isAuthenticating = true
        let reason = "Sblocca Chirone Gestionale per accedere ai dati clinici."
        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self, self.activeRequestID == requestID else { return }
                self.activeRequestID = nil
                self.activeContext = nil
                self.isAuthenticating = false
                if success {
                    self.lastErrorMessage = nil
                    self.isUnlocked = true
                    self.backgroundedAt = nil
                    SecureDataCipher.shared.prewarmKey()
                    AuditTrailService.shared.log(.appUnlocked)
                } else {
                    self.lastErrorMessage = error?.localizedDescription ?? "Autenticazione non riuscita."
                    let code = (error as NSError?)?.code ?? -1
                    AuditTrailService.shared.log(.appLockFailed, metadata: ["code": "\(code)"])
                }
            }
        }
    }

    func handleWillResignActive() {
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func handleDidBecomeActive(timeoutMinutes: Int) {
        guard isUnlocked else { return }

        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        if Self.requiresReauthentication(backgroundedAt: backgroundedAt, now: Date(), timeoutMinutes: timeoutMinutes) {
            lock()
        }
    }

    static func requiresReauthentication(backgroundedAt: Date, now: Date, timeoutMinutes: Int) -> Bool {
        let elapsed = now.timeIntervalSince(backgroundedAt)
        return elapsed < 0 || elapsed >= Double(min(240, max(1, timeoutMinutes))) * 60
    }

    func lock() {
        for window in NSApp.windows {
            window.makeFirstResponder(nil)
        }
        activeRequestID = nil
        activeContext?.invalidate()
        activeContext = nil
        isAuthenticating = false
        backgroundedAt = nil
        isUnlocked = false
        SecureDataCipher.shared.invalidateSessionCache()
        AuditTrailService.shared.log(.appLocked)
    }
}
