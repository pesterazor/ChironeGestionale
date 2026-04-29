import SwiftUI
import AppKit

struct AppLockGateView<Content: View>: View {
    @StateObject private var lockViewModel = AppLockViewModel()
    @AppStorage("security.reauthTimeoutMinutes") private var reauthTimeoutMinutes = 5
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if lockViewModel.isUnlocked {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 46))
                        .foregroundStyle(.secondary)

                    Text("Chirone Gestionale bloccata")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Autenticati con Touch ID o password di sistema per accedere ai dati clinici.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360)

                    if let lastErrorMessage = lockViewModel.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    Button("Sblocca") {
                        lockViewModel.unlock()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .onAppear {
                    lockViewModel.unlock()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            lockViewModel.handleWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            lockViewModel.handleDidBecomeActive(timeoutMinutes: reauthTimeoutMinutes)
        }
    }
}
