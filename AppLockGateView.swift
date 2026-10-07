import SwiftUI
import AppKit

struct AppLockGateView<Content: View>: View {
    @ObservedObject private var lockViewModel = AppLockViewModel.shared
    @AppStorage("security.reauthTimeoutMinutes") private var reauthTimeoutMinutes = 5
    @State private var hasPresentedContent = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            // Keep an opened clinical form mounted while locked so its unsaved draft survives.
            // Never construct clinical content before the first successful authentication.
            if hasPresentedContent || lockViewModel.permitsClinicalAccess {
                content()
                    .opacity(lockViewModel.permitsClinicalAccess ? 1 : 0)
                    .disabled(!lockViewModel.permitsClinicalAccess)
                    .allowsHitTesting(lockViewModel.permitsClinicalAccess)
                    .accessibilityHidden(!lockViewModel.permitsClinicalAccess)
            }
            if !lockViewModel.permitsClinicalAccess {
                lockScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: lockViewModel.isUnlocked, initial: true) { _, unlocked in
            if unlocked { hasPresentedContent = true }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
            lockViewModel.lock()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            lockViewModel.handleWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            lockViewModel.handleDidBecomeActive(timeoutMinutes: reauthTimeoutMinutes)
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("Chirone Gestionale bloccata")
                .font(.title3.weight(.semibold))
            Text("Autenticati con Touch ID o password di sistema per accedere ai dati clinici.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            if let error = lockViewModel.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Button(lockViewModel.isAuthenticating ? "Autenticazione in corso…" : "Sblocca") {
                lockViewModel.unlock()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(lockViewModel.isAuthenticating)
        }
        .padding(24)
        .onAppear { lockViewModel.unlock() }
    }
}
