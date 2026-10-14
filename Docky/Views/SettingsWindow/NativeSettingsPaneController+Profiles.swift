import AppKit
import Combine
import UniformTypeIdentifiers

extension NativeSettingsPaneController {
    func profileRows() {
        let service = ProfileService.shared
        add(
            NativeActionButton(String(localized: "New Profile")) { [weak self] in
                guard let name = self?.prompt(String(localized: "Profile Name")), !name.isEmpty else { return }
                let profile = service.createProfile(name: name, basedOn: service.activeProfile)
                service.setActiveProfile(id: profile.id)
            })
        for profile in service.profiles {
            add(
                nativeStack(
                    [
                        NativeActionButton(profile.name, symbol: profile.symbolName) {
                            service.setActiveProfile(id: profile.id)
                        },
                        NativeActionButton(String(localized: "Rename")) { [weak self] in
                            if let name = self?.prompt(String(localized: "Profile Name"), value: profile.name) {
                                service.renameProfile(id: profile.id, to: name)
                            }
                        },
                        NativeActionButton(String(localized: "Symbol")) { [weak self] in
                            if let symbol = self?.chooseProfileSymbol(current: profile.symbolName) {
                                service.updateProfileSymbol(id: profile.id, symbolName: symbol)
                            }
                        },
                        NativeActionButton(String(localized: "Delete")) { [weak self] in
                            self?.confirmDelete(String(localized: "Delete Profile?")) {
                                service.deleteProfile(id: profile.id)
                            }
                        }
                    ], orientation: .horizontal))
            for trigger in profile.triggers {
                add(
                    nativeStack(
                        [
                            nativeLabel(triggerTitle(trigger), size: 12),
                            NativeActionButton(String(localized: "Edit")) { [weak self] in
                                self?.editTrigger(trigger, profileID: profile.id)
                            },
                            NativeActionButton(String(localized: "Remove")) {
                                service.removeTrigger(trigger.id, from: profile.id)
                            }
                        ], orientation: .horizontal))
            }
            add(
                NativeActionButton(String(localized: "Add Trigger")) { [weak self] in
                    self?.addTrigger(profileID: profile.id)
                })
        }
    }
    func chooseProfileSymbol(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Profile Symbol")
        let picker = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 280, height: 28))
        let options: [String] = [
            "house.fill",
            "briefcase.fill",
            "person.fill",
            "gamecontroller.fill",
            "moon.stars.fill",
            "sparkles",
            "paintbrush.fill",
            "music.note",
            "film.fill",
            "book.fill",
            "airplane",
            "car.fill",
            "leaf.fill",
            "flame.fill",
            "bolt.fill",
            "heart.fill"
        ]
        for symbol in options {
            picker.addItem(withTitle: symbol.replacingOccurrences(of: ".", with: " ").capitalized)
            picker.lastItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            picker.lastItem?.representedObject = symbol
            if symbol == current { picker.select(picker.lastItem) }
        }
        alert.accessoryView = picker
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return picker.selectedItem?.representedObject as? String
    }
    func triggerTitle(_ trigger: ProfileTrigger) -> String {
        switch trigger {
        case .timeOfDay(let rule):
            let start = String(format: "%d:%02d", rule.startMinuteOfDay / 60, rule.startMinuteOfDay % 60)
            let end = String(format: "%d:%02d", rule.endMinuteOfDay / 60, rule.endMinuteOfDay % 60)
            return "Time: \(start)–\(end)"
        case .frontmostApp(let rule): return "Frontmost App: \(rule.bundleIdentifier)"
        case .space(let rule): return "Space App: \(rule.bundleIdentifier)"
        }
    }
    func addTrigger(profileID: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Trigger Type")
        let picker = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 300, height: 26))
        picker.addItems(withTitles: [
            String(localized: "Time of Day"), String(localized: "Frontmost App"), String(localized: "Space")
        ])
        alert.accessoryView = picker
        alert.addButton(withTitle: String(localized: "Add"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trigger: ProfileTrigger =
            picker.indexOfSelectedItem == 0
            ? .timeOfDay(TimeOfDayTrigger())
            : picker.indexOfSelectedItem == 1
                ? .frontmostApp(FrontmostAppTrigger(bundleIdentifier: "")) : .space(SpaceTrigger(bundleIdentifier: ""))
        editTrigger(trigger, profileID: profileID, isNew: true)
    }
    func editTrigger(_ trigger: ProfileTrigger, profileID: String, isNew: Bool = false) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Profile Trigger")
        let (editor, read) = triggerEditor(trigger)
        editor.frame.size = CGSize(width: 440, height: max(30, editor.fittingSize.height))
        alert.accessoryView = editor
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let updated = read()
        if isNew {
            ProfileService.shared.addTrigger(updated, to: profileID)
        } else {
            ProfileService.shared.updateTrigger(updated, in: profileID)
        }
    }
    func triggerEditor(_ trigger: ProfileTrigger) -> (NSView, () -> ProfileTrigger) {
        switch trigger {
        case .timeOfDay(let rule): return timeTriggerEditor(rule)
        case .frontmostApp, .space: return appTriggerEditor(trigger)
        }
    }
    func timeTriggerEditor(_ rule: TimeOfDayTrigger) -> (NSView, () -> ProfileTrigger) {
        let start = NSDatePicker()
        let end = NSDatePicker()
        for picker in [start, end] {
            picker.datePickerElements = [.hourMinute]
            picker.datePickerStyle = .textFieldAndStepper
        }
        let day = Calendar.current.startOfDay(for: Date())
        start.dateValue =
            Calendar.current.date(
                bySettingHour: rule.startMinuteOfDay / 60, minute: rule.startMinuteOfDay % 60, second: 0, of: day)
            ?? day
        end.dateValue =
            Calendar.current.date(
                bySettingHour: rule.endMinuteOfDay / 60, minute: rule.endMinuteOfDay % 60, second: 0, of: day) ?? day
        let days = (1...7).map { weekday -> NSButton in
            let button = NSButton(
                checkboxWithTitle: Calendar.current.shortWeekdaySymbols[weekday - 1], target: nil, action: nil)
            button.state = rule.weekdays.contains(weekday) ? .on : .off
            return button
        }
        let editor = nativeStack([
            nativeStack([start, end], orientation: .horizontal), nativeStack(days, orientation: .horizontal)
        ])
        let read: () -> ProfileTrigger = {
            var value = rule
            value.startMinuteOfDay =
                Calendar.current.component(.hour, from: start.dateValue) * 60
                + Calendar.current.component(.minute, from: start.dateValue)
            value.endMinuteOfDay =
                Calendar.current.component(.hour, from: end.dateValue) * 60
                + Calendar.current.component(.minute, from: end.dateValue)
            value.weekdays = Set(days.enumerated().compactMap { $0.element.state == .on ? $0.offset + 1 : nil })
            return .timeOfDay(value)
        }
        return (editor, read)
    }
    func appTriggerEditor(_ trigger: ProfileTrigger) -> (NSView, () -> ProfileTrigger) {
        let bundleID: String
        switch trigger {
        case .frontmostApp(let rule): bundleID = rule.bundleIdentifier
        case .space(let rule): bundleID = rule.bundleIdentifier
        default: bundleID = ""
        }
        let picker = NSPopUpButton()
        var apps = LaunchpadOverlayService.shared.entries.flatMap { entry -> [AppTile] in
            switch entry {
            case .app(let app): return [app]
            case .folder(let folder): return folder.apps
            }
        }
        apps += NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let identifier = app.bundleIdentifier else { return nil }
            return AppTile(bundleIdentifier: identifier, displayName: app.localizedName ?? identifier)
        }
        var seen = Set<String>()
        apps = apps.filter { seen.insert($0.bundleIdentifier).inserted }
        if !bundleID.isEmpty && !apps.contains(where: { $0.bundleIdentifier == bundleID }) {
            apps.append(AppTile(bundleIdentifier: bundleID, displayName: bundleID))
        }
        picker.addItem(withTitle: String(localized: "Choose App"))
        for app in apps.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
            picker.addItem(withTitle: app.displayName)
            picker.lastItem?.representedObject = app.bundleIdentifier
            let icon = IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier).copy() as? NSImage
            icon?.size = CGSize(width: 16, height: 16)
            picker.lastItem?.image = icon
            if app.bundleIdentifier == bundleID { picker.select(picker.lastItem) }
        }
        let editor = picker
        let read: () -> ProfileTrigger = {
            self.updatedAppTrigger(trigger, identifier: picker.selectedItem?.representedObject as? String ?? "")
        }
        return (editor, read)
    }
    func updatedAppTrigger(_ trigger: ProfileTrigger, identifier: String) -> ProfileTrigger {
        switch trigger {
        case .frontmostApp(var value):
            value.bundleIdentifier = identifier
            return .frontmostApp(value)
        case .space(var value):
            value.bundleIdentifier = identifier
            return .space(value)
        default: return trigger
        }
    }

}
