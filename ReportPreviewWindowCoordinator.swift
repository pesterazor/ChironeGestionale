import SwiftUI
import AppKit
import PDFKit

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
                Spacer()
                Button("Salva") { onSave() }
                Button("Stampa") { onPrint() }
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
            onSave: {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Salva referto"
                alert.informativeText = "Funzionalità in preparazione."
                alert.addButton(withTitle: "OK")
                alert.runModal()
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
}
