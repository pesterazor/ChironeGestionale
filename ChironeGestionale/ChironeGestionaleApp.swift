//
//  ChironeGestionaleApp.swift
//  ChironeGestionale
//
//  Created by Peste on 21/04/2026.
//

import SwiftUI
import SwiftData

private struct PreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferenze")
                .font(.title2)
                .fontWeight(.semibold)

            Text("In questa sezione verranno configurate le impostazioni dell'app.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 220, alignment: .topLeading)
    }
}

@main
struct ChironeGestionaleApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback per store incompatibile durante sviluppo: evita crash all'avvio.
            // Da sostituire con migrazioni versionate nello sprint di hardening.
            do {
                let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            } catch {
                fatalError("Could not create ModelContainer (persistent/inMemory): \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

        Settings {
            PreferencesView()
        }
    }
}
