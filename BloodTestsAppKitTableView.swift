import SwiftUI
import AppKit

struct BloodTestsAppKitTableView: NSViewRepresentable {
    let rows: [BloodTestRowRecord]
    let columns: [BloodTestColumnRecord]
    let rowNameForID: (UUID) -> String
    let setRowName: (UUID, String) -> Void
    let cellValueForIDs: (UUID, UUID) -> String
    let setCellValue: (UUID, UUID, String) -> Void
    let canDeleteRow: (UUID) -> Bool
    let deleteRow: (UUID) -> Void
    let onHeaderEditColumn: (UUID) -> Void
    let onHeaderAddAfterColumn: (UUID) -> Void
    let onHeaderDeleteColumn: (UUID) -> Void
    @Binding var selectedColumnID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BloodTestsSplitContainerView {
        let container = BloodTestsSplitContainerView()
        context.coordinator.attach(container: container)
        context.coordinator.reloadStructureIfNeeded()
        context.coordinator.reloadData()
        return container
    }

    func updateNSView(_ nsView: BloodTestsSplitContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reloadStructureIfNeeded()
        context.coordinator.reloadData()

        if let selectedColumnID, !columns.contains(where: { $0.id == selectedColumnID }) {
            DispatchQueue.main.async {
                self.selectedColumnID = nil
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: BloodTestsAppKitTableView
        private weak var container: BloodTestsSplitContainerView?
        private weak var leftTable: NSTableView?
        private weak var rightTable: BloodTestsNSTableView?
        private var renderedColumnIDs: [UUID] = []
        private var isSyncingScroll = false

        init(_ parent: BloodTestsAppKitTableView) {
            self.parent = parent
        }

        func attach(container: BloodTestsSplitContainerView) {
            self.container = container
            self.leftTable = container.leftTable
            self.rightTable = container.rightTable

            container.leftTable.delegate = self
            container.leftTable.dataSource = self
            container.rightTable.delegate = self
            container.rightTable.dataSource = self
            container.rightTable.onHeaderClicked = { [weak self] columnID in
                DispatchQueue.main.async {
                    self?.parent.selectedColumnID = columnID
                    self?.reloadData()
                }
            }
            container.rightTable.onHeaderRightClicked = { [weak self] columnID in
                DispatchQueue.main.async {
                    self?.parent.selectedColumnID = columnID
                    self?.reloadData()
                }
            }
            container.rightTable.onHeaderContextMenuClosed = { [weak self] in
                DispatchQueue.main.async {
                    self?.parent.selectedColumnID = nil
                    self?.reloadData()
                }
            }
            container.rightTable.onHeaderContextAction = { [weak self] action, columnID in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.selectedColumnID = columnID
                    switch action {
                    case .edit: self.parent.onHeaderEditColumn(columnID)
                    case .addAfter: self.parent.onHeaderAddAfterColumn(columnID)
                    case .delete: self.parent.onHeaderDeleteColumn(columnID)
                    }
                }
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(leftDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: container.leftScroll.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(rightDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: container.rightScroll.contentView
            )
            container.leftScroll.contentView.postsBoundsChangedNotifications = true
            container.rightScroll.contentView.postsBoundsChangedNotifications = true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func leftDidScroll(_ note: Notification) {
            guard !isSyncingScroll, let container else { return }
            isSyncingScroll = true
            let y = container.leftScroll.contentView.bounds.origin.y
            var origin = container.rightScroll.contentView.bounds.origin
            origin.y = y
            container.rightScroll.contentView.scroll(to: origin)
            container.rightScroll.reflectScrolledClipView(container.rightScroll.contentView)
            isSyncingScroll = false
        }

        @objc private func rightDidScroll(_ note: Notification) {
            guard !isSyncingScroll, let container else { return }
            isSyncingScroll = true
            let y = container.rightScroll.contentView.bounds.origin.y
            var origin = container.leftScroll.contentView.bounds.origin
            origin.y = y
            container.leftScroll.contentView.scroll(to: origin)
            container.leftScroll.reflectScrolledClipView(container.leftScroll.contentView)
            isSyncingScroll = false
        }

        func reloadStructureIfNeeded() {
            guard let leftTable, let rightTable else { return }

            if leftTable.tableColumns.isEmpty {
                let leftColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("testName"))
                leftColumn.title = "Esame"
                leftColumn.width = 260
                leftColumn.minWidth = 220
                leftColumn.maxWidth = 320
                leftColumn.resizingMask = .userResizingMask
                leftTable.addTableColumn(leftColumn)
            }

            let currentColumnIDs = parent.columns.map(\.id)
            if renderedColumnIDs == currentColumnIDs, rightTable.tableColumns.count == currentColumnIDs.count {
                updateRightHeaderTitlesAndSelection()
                return
            }

            rightTable.tableColumns.forEach { rightTable.removeTableColumn($0) }
            for column in parent.columns {
                let identifier = NSUserInterfaceItemIdentifier(column.id.uuidString)
                let newColumn = NSTableColumn(identifier: identifier)
                newColumn.title = column.dateText.isEmpty ? "Data" : column.dateText
                newColumn.width = 140
                newColumn.minWidth = 120
                newColumn.maxWidth = 140
                newColumn.resizingMask = .userResizingMask
                newColumn.headerCell = SelectableHeaderCell(textCell: newColumn.title)
                rightTable.addTableColumn(newColumn)
            }

            renderedColumnIDs = currentColumnIDs
            updateRightHeaderTitlesAndSelection()
        }

        func reloadData() {
            leftTable?.reloadData()
            rightTable?.reloadData()
            updateRightHeaderTitlesAndSelection()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count, let tableColumn else { return nil }
            let rowModel = parent.rows[row]

            let cellView = NSTableCellView()
            cellView.wantsLayer = true
            let textField = EditableTableTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isBordered = false
            textField.focusRingType = .none
            textField.lineBreakMode = .byTruncatingTail
            textField.delegate = self
            textField.rowID = rowModel.id
            textField.drawsBackground = false

            if tableView == leftTable {
                textField.columnID = nil
                textField.isEditable = false
                textField.isSelectable = true
                textField.stringValue = parent.rowNameForID(rowModel.id)
                cellView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            } else {
                guard let columnID = UUID(uuidString: tableColumn.identifier.rawValue) else { return nil }
                textField.columnID = columnID
                textField.isEditable = true
                textField.isSelectable = true
                textField.stringValue = parent.cellValueForIDs(rowModel.id, columnID)
                if parent.selectedColumnID == columnID {
                    cellView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
                } else {
                    cellView.layer?.backgroundColor = NSColor.clear.cgColor
                }
            }

            cellView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                textField.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 3),
                textField.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -3)
            ])
            cellView.textField = textField
            return cellView
        }

        func tableView(_ tableView: NSTableView, menuFor event: NSEvent) -> NSMenu? {
            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)
            guard row >= 0, row < parent.rows.count else { return nil }

            let rowModel = parent.rows[row]
            let menu = NSMenu()
            if parent.canDeleteRow(rowModel.id) {
                let deleteItem = NSMenuItem(title: "Rimuovi voce", action: #selector(deleteRowFromMenu(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = rowModel.id.uuidString
                menu.addItem(deleteItem)
            }
            return menu.items.isEmpty ? nil : menu
        }

        @objc private func deleteRowFromMenu(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let rowID = UUID(uuidString: raw) else { return }
            parent.deleteRow(rowID)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? EditableTableTextField, let rowID = textField.rowID else { return }
            if let columnID = textField.columnID {
                parent.setCellValue(rowID, columnID, textField.stringValue)
            } else {
                parent.setRowName(rowID, textField.stringValue)
            }
        }

        private func updateRightHeaderTitlesAndSelection() {
            guard let rightTable else { return }
            for tableColumn in rightTable.tableColumns {
                guard let columnID = UUID(uuidString: tableColumn.identifier.rawValue) else { continue }
                if let model = parent.columns.first(where: { $0.id == columnID }) {
                    tableColumn.title = model.dateText.isEmpty ? "Data" : model.dateText
                }
                let headerCell: SelectableHeaderCell
                if let existing = tableColumn.headerCell as? SelectableHeaderCell {
                    headerCell = existing
                } else {
                    headerCell = SelectableHeaderCell(textCell: tableColumn.title)
                    tableColumn.headerCell = headerCell
                }
                headerCell.isSelectedColumn = (parent.selectedColumnID == columnID)
            }
            rightTable.headerView?.needsDisplay = true
        }
    }
}

final class BloodTestsSplitContainerView: NSView {
    let leftScroll = NSScrollView()
    let rightScroll = NSScrollView()
    let leftTable = NSTableView()
    let rightTable = BloodTestsNSTableView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        leftScroll.translatesAutoresizingMaskIntoConstraints = false
        rightScroll.translatesAutoresizingMaskIntoConstraints = false

        leftScroll.documentView = leftTable
        leftScroll.hasVerticalScroller = true
        leftScroll.hasHorizontalScroller = false
        leftScroll.autohidesScrollers = true
        leftScroll.drawsBackground = false
        leftScroll.borderType = .noBorder

        let headerView = BloodTestsNSTableHeaderView()
        headerView.owner = rightTable
        rightTable.headerView = headerView
        rightTable.usesAlternatingRowBackgroundColors = true
        rightTable.allowsMultipleSelection = false
        rightTable.allowsEmptySelection = true
        rightTable.selectionHighlightStyle = .none
        rightTable.columnAutoresizingStyle = .noColumnAutoresizing
        rightTable.intercellSpacing = .zero
        if #available(macOS 11.0, *) {
            rightTable.style = .fullWidth
        }

        leftTable.usesAlternatingRowBackgroundColors = false
        leftTable.allowsMultipleSelection = false
        leftTable.allowsEmptySelection = true
        leftTable.selectionHighlightStyle = .none
        leftTable.headerView = NSTableHeaderView()
        leftTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        leftTable.intercellSpacing = .zero
        if #available(macOS 11.0, *) {
            leftTable.style = .fullWidth
        }

        rightScroll.documentView = rightTable
        rightScroll.hasVerticalScroller = true
        rightScroll.hasHorizontalScroller = true
        rightScroll.autohidesScrollers = true
        rightScroll.drawsBackground = false
        rightScroll.borderType = .noBorder

        let stack = NSStackView(views: [leftScroll, rightScroll])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.distribution = .fill
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftScroll.widthAnchor.constraint(equalToConstant: 270)
        ])
    }
}

final class BloodTestsNSTableView: NSTableView, NSMenuDelegate {
    enum HeaderContextAction {
        case edit
        case addAfter
        case delete
    }

    var onHeaderClicked: ((UUID?) -> Void)?
    var onHeaderRightClicked: ((UUID?) -> Void)?
    var onHeaderContextAction: ((HeaderContextAction, UUID) -> Void)?
    var onHeaderContextMenuClosed: (() -> Void)?
    private var activeHeaderContextMenu: NSMenu?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow == -1 {
            let columnIndex = column(at: point)
            if columnIndex >= 0 {
                let identifier = tableColumns[columnIndex].identifier.rawValue
                onHeaderClicked?(UUID(uuidString: identifier))
            } else {
                onHeaderClicked?(nil)
            }
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Header right-click is handled by BloodTestsNSTableHeaderView.
        super.rightMouseDown(with: event)
    }

    func headerContextMenu(for event: NSEvent, in headerView: NSTableHeaderView) -> NSMenu? {
        let pointInHeader = headerView.convert(event.locationInWindow, from: nil)
        let columnIndex = headerView.column(at: pointInHeader)
        guard columnIndex >= 0 else {
            onHeaderRightClicked?(nil)
            return nil
        }
        let identifier = tableColumns[columnIndex].identifier.rawValue
        guard let columnID = UUID(uuidString: identifier) else {
            onHeaderRightClicked?(nil)
            return nil
        }
        onHeaderRightClicked?(columnID)
        return makeHeaderContextMenu(for: columnID)
    }

    private func makeHeaderContextMenu(for columnID: UUID) -> NSMenu {
        let menu = NSMenu(title: "Colonna")
        menu.delegate = self

        let editItem = NSMenuItem(title: "Modifica data…", action: #selector(runHeaderEdit(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = columnID.uuidString
        menu.addItem(editItem)

        let addAfterItem = NSMenuItem(title: "Aggiungi colonna dopo", action: #selector(runHeaderAddAfter(_:)), keyEquivalent: "")
        addAfterItem.target = self
        addAfterItem.representedObject = columnID.uuidString
        menu.addItem(addAfterItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Elimina colonna", action: #selector(runHeaderDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = columnID.uuidString
        deleteItem.isEnabled = tableColumns.count > 1 // keeps at least one date column
        menu.addItem(deleteItem)
        activeHeaderContextMenu = menu
        return menu
    }

    @objc private func runHeaderEdit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let columnID = UUID(uuidString: raw) else { return }
        onHeaderContextAction?(.edit, columnID)
    }

    @objc private func runHeaderAddAfter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let columnID = UUID(uuidString: raw) else { return }
        onHeaderContextAction?(.addAfter, columnID)
    }

    @objc private func runHeaderDelete(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let columnID = UUID(uuidString: raw) else { return }
        onHeaderContextAction?(.delete, columnID)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === activeHeaderContextMenu else { return }
        activeHeaderContextMenu = nil
        onHeaderContextMenuClosed?()
    }
}

private final class SelectableHeaderCell: NSTableHeaderCell {
    var isSelectedColumn: Bool = false

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame, in: controlView)
        guard isSelectedColumn else { return }

        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        let indicatorHeight: CGFloat = 2
        let indicatorRect = NSRect(
            x: cellFrame.minX + 1,
            y: cellFrame.minY + 1,
            width: max(0, cellFrame.width - 2),
            height: indicatorHeight
        )
        NSBezierPath(rect: indicatorRect).fill()
    }
}

private final class BloodTestsNSTableHeaderView: NSTableHeaderView {
    weak var owner: BloodTestsNSTableView?

    override func menu(for event: NSEvent) -> NSMenu? {
        owner?.headerContextMenu(for: event, in: self)
    }
}

private final class EditableTableTextField: NSTextField {
    var rowID: UUID?
    var columnID: UUID?
}
