import AppKit

/// Edits a profile in a sheet: its name, symbol, and triggers. Changes apply
/// only when the sheet is saved.
@MainActor
final class NativeProfileEditor {
    static let symbols = [
        "house.fill", "briefcase.fill", "person.fill", "gamecontroller.fill", "moon.stars.fill", "sparkles",
        "paintbrush.fill", "music.note", "film.fill", "book.fill", "airplane", "car.fill", "leaf.fill",
        "flame.fill", "bolt.fill", "heart.fill"
    ]
    var draft: DockProfile
    let isNew: Bool
    let sheet: NativeFormSheetController
    private let nameField = NSTextField()
    private lazy var sheets = NativeSheetPresenter(owner: sheet)

    /// Shows the editor for `profileID`, or for a new profile when it's nil.
    static func present(profileID: String?, from presenter: NativeSheetPresenter) async {
        let service = ProfileService.shared
        let existing = profileID.flatMap { id in service.profiles.first { $0.id == id } }
        if profileID != nil, existing == nil { return }
        let editor = NativeProfileEditor(
            draft: existing ?? DockProfile(name: String(localized: "New Profile"), symbolName: "sparkles"),
            isNew: existing == nil)
        if await presenter.present(editor.sheet) { editor.save() }
    }

    private init(draft: DockProfile, isNew: Bool) {
        self.draft = draft
        self.isNew = isNew
        let delete = NativeActionButton(String(localized: "Delete Profile…")) {}
        delete.isHidden = isNew || ProfileService.shared.profiles.count < 2
        sheet = NativeFormSheetController(
            title: isNew ? String(localized: "New Profile") : String(localized: "Edit Profile"),
            confirmTitle: isNew ? String(localized: "Add Profile") : String(localized: "Save"),
            leadingButton: delete)
        delete.handler = { [weak self] in self?.confirmDelete() }
        sheet.onConfirm = { [weak self] in
            guard let self, !self.nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                NSSound.beep()
                return false
            }
            return true
        }
        nameField.stringValue = draft.name
        nameField.placeholderString = String(localized: "Name")
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        reloadSections()
    }

    func reloadSections() {
        // Rebuilding moves the fields to new rows, so finish a name or time being typed first.
        sheet.viewIfLoaded?.window?.makeFirstResponder(nil)
        let symbol = NSPopUpButton()
        // Profiles made before this list existed can use another symbol; keep it choosable.
        let names = Self.symbols.contains(draft.symbolName) ? Self.symbols : [draft.symbolName] + Self.symbols
        for name in names {
            symbol.addItem(withTitle: name.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ").capitalized)
            symbol.lastItem?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            symbol.lastItem?.representedObject = name
            if name == draft.symbolName { symbol.select(symbol.lastItem) }
        }
        let symbolRow = NativeFormRow(title: String(localized: "Symbol"), control: symbol)
        symbolRow.bind(symbol) { [weak self] in
            if let name = symbol.selectedItem?.representedObject as? String { self?.draft.symbolName = name }
        }
        let details = NativeSettingsSection(rows: [
            NativeFormRow(title: String(localized: "Name"), control: nameField), symbolRow
        ])
        sheet.form.setSections([details] + triggerSections() + [addTriggerSection()])
    }

    private func confirmDelete() {
        Task {
            guard
                await sheets.confirm(
                    String(localized: "Delete “\(draft.name)”?"),
                    informativeText: String(localized: "The profile's pinned apps, widgets, and triggers are deleted."),
                    confirmTitle: String(localized: "Delete"), destructive: true)
            else { return }
            ProfileService.shared.deleteProfile(id: draft.id)
            sheet.close(confirmed: false)
        }
    }

    /// Applies the draft through `ProfileService`, changing only what differs.
    private func save() {
        let service = ProfileService.shared
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if isNew {
            let profile = service.createProfile(name: name, symbolName: draft.symbolName, basedOn: service.activeProfile)
            for trigger in draft.triggers { service.addTrigger(trigger, to: profile.id) }
            service.setActiveProfile(id: profile.id)
            return
        }
        guard let current = service.profiles.first(where: { $0.id == draft.id }) else { return }
        if current.name != name { service.renameProfile(id: current.id, to: name) }
        if current.symbolName != draft.symbolName {
            service.updateProfileSymbol(id: current.id, symbolName: draft.symbolName)
        }
        let kept = Set(draft.triggers.map(\.id))
        for trigger in current.triggers where !kept.contains(trigger.id) {
            service.removeTrigger(trigger.id, from: current.id)
        }
        for trigger in draft.triggers {
            if let existing = current.triggers.first(where: { $0.id == trigger.id }) {
                if existing != trigger { service.updateTrigger(trigger, in: current.id) }
            } else {
                service.addTrigger(trigger, to: current.id)
            }
        }
    }
}
