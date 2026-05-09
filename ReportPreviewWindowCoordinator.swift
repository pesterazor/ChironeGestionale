import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

private struct ReportPDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

private struct ReportPreviewContentView: View {
    let title: String
    let document: PDFDocument
    let onClose: () -> Void
    let onSave: () -> Void
    let onPrint: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Anteprima referto")
                    .font(.headline)
                    .accessibilityIdentifier("report_preview_title")
                Spacer()
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ReportPDFPreviewView(document: document)
                .frame(minHeight: 520)

            Divider()

            HStack {
                Button("Chiudi") { onClose() }
                    .accessibilityIdentifier("report_preview_close_button")
                Spacer()
                Button("Salva") { onSave() }
                    .accessibilityIdentifier("report_preview_save_button")
                Button("Stampa") { onPrint() }
                    .accessibilityIdentifier("report_preview_print_button")
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 780, minHeight: 640)
    }
}

@MainActor
final class ReportPreviewWindowCoordinator {
    static let shared = ReportPreviewWindowCoordinator()

    private var window: NSWindow?

    private init() {}

    func present(document: PDFDocument, title: String) {
        let contentView = ReportPreviewContentView(
            title: title,
            document: document,
            onClose: { [weak self] in
                self?.window?.close()
            },
            onSave: { [weak self] in
                self?.saveReport(document: document, title: title)
            },
            onPrint: {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Stampa referto"
                alert.informativeText = "Funzionalità in preparazione."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)

        let previewWindow = window ?? NSWindow(contentViewController: hostingController)
        previewWindow.contentViewController = hostingController
        previewWindow.title = "Anteprima referto"
        previewWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        previewWindow.setContentSize(NSSize(width: 860, height: 720))
        previewWindow.minSize = NSSize(width: 700, height: 560)
        previewWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = previewWindow
    }

    private func saveReport(document: PDFDocument, title: String) {
        guard let data = document.dataRepresentation() else {
            showInfoAlert(title: "Salvataggio non riuscito", message: "Impossibile serializzare il PDF del referto.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Salva referto"
        panel.nameFieldStringValue = defaultReportFilename(title: title)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            showInfoAlert(title: "Referto salvato", message: "Il referto PDF è stato salvato correttamente.")
        } catch {
            showInfoAlert(title: "Salvataggio non riuscito", message: error.localizedDescription)
        }
    }

    private func defaultReportFilename(title: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let normalizedTitle = sanitizedFilenameComponent(title)
        return "Referto-\(normalizedTitle)-\(formatter.string(from: .now)).pdf"
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(mapped).replacingOccurrences(of: "__", with: "_")
        let result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "Paziente" : result
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
