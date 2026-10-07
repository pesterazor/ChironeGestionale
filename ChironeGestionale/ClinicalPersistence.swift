import SwiftData

@MainActor
enum ClinicalPersistence {
    static func perform(in context: ModelContext, changes: () throws -> Void, save: (() throws -> Void)? = nil) throws {
        // Preserve earlier edits before a multi-record change that may need rollback.
        if context.hasChanges { try context.save() }
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }
        do {
            try changes()
            if let save { try save() } else { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }
}
