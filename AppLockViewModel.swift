import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AppLockViewModel: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastErrorMessage: String?
    private var backgroundedAt: Date?

    func unlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Annulla"

        var authError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            lastErrorMessage = authError?.localizedDescription ?? "Autenticazione non disponibile su questo Mac."
            return
        }

        let reason = "Sblocca Chirone Gestionale per accedere ai dati clinici."
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if success {
                    self.lastErrorMessage = nil
                    self.isUnlocked = true
                    self.backgroundedAt = nil
                } else {
                    self.lastErrorMessage = error?.localizedDescription ?? "Autenticazione non riuscita."
                }
            }
        }
    }

    func handleWillResignActive() {
        backgroundedAt = Date()
    }

    func handleDidBecomeActive(timeoutMinutes: Int) {
        guard isUnlocked else { return }

        let timeout = max(1, timeoutMinutes)
        guard let backgroundedAt else { return }

        let elapsed = Date().timeIntervalSince(backgroundedAt)
        if elapsed >= Double(timeout) * 60 {
            lock()
        }
    }

    func lock() {
        isUnlocked = false
    }
}
