import AppKit

extension NativeProfileEditor {
    func triggerSections() -> [NativeSettingsSection] {
        draft.triggers.map { trigger in
            let remove = NativeActionButton(String(localized: "Remove Trigger")) { [weak self] in
                self?.draft.triggers.removeAll { $0.id == trigger.id }
                self?.reloadSections()
            }
            switch trigger {
            case .timeOfDay(let rule):
                return NativeSettingsSection(
                    String(localized: "Time of Day"), rows: timeRows(rule), actions: [remove])
            case .frontmostApp(let rule):
                return NativeSettingsSection(
                    String(localized: "Frontmost App"),
                    footer: String(localized: "Switches to this profile while the app is frontmost."),
                    rows: [appRow(trigger, bundleIdentifier: rule.bundleIdentifier)], actions: [remove])
            case .space(let rule):
                return NativeSettingsSection(
                    String(localized: "Space"),
                    footer: String(localized: "Switches to this profile on a Space that shows one of the app's windows."),
                    rows: [appRow(trigger, bundleIdentifier: rule.bundleIdentifier)], actions: [remove])
            }
        }
    }

    func addTriggerSection() -> NativeSettingsSection {
        let add = NSPopUpButton(frame: .zero, pullsDown: true)
        add.addItem(withTitle: String(localized: "Add Trigger"))
        let kinds: [(String, () -> ProfileTrigger)] = [
            (String(localized: "Time of Day"), { .timeOfDay(TimeOfDayTrigger()) }),
            (String(localized: "Frontmost App"), { .frontmostApp(FrontmostAppTrigger(bundleIdentifier: "")) }),
            (String(localized: "Space"), { .space(SpaceTrigger(bundleIdentifier: "")) })
        ]
        add.addItems(withTitles: kinds.map(\.0))
        let section = NativeSettingsSection(
            footer: draft.triggers.isEmpty
                ? String(localized: "Without triggers, this profile is used only when you choose it.") : nil,
            actions: [add])
        section.bind(add) { [weak self, weak add] in
            guard let self, let add, add.indexOfSelectedItem > 0 else { return }
            self.draft.triggers.append(kinds[add.indexOfSelectedItem - 1].1())
            self.reloadSections()
        }
        return section
    }

    private func update(_ trigger: ProfileTrigger) {
        guard let index = draft.triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        draft.triggers[index] = trigger
    }

    private func timeRows(_ rule: TimeOfDayTrigger) -> [NativeFormRowView] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        func picker(_ minute: Int) -> NSDatePicker {
            let picker = NSDatePicker()
            picker.datePickerElements = [.hourMinute]
            picker.datePickerStyle = .textFieldAndStepper
            picker.dateValue = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
            return picker
        }
        func minute(_ picker: NSDatePicker) -> Int {
            calendar.component(.hour, from: picker.dateValue) * 60 + calendar.component(.minute, from: picker.dateValue)
        }
        let start = picker(rule.startMinuteOfDay)
        let end = picker(rule.endMinuteOfDay)
        // Weekdays in the order the user's calendar starts its week; `weekdays` stores 1 as Sunday.
        let weekdays = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let days = NSSegmentedControl(
            labels: weekdays.map { calendar.veryShortWeekdaySymbols[$0 - 1] }, trackingMode: .selectAny, target: nil,
            action: nil)
        for (segment, weekday) in weekdays.enumerated() {
            days.setSelected(rule.weekdays.contains(weekday), forSegment: segment)
            days.setToolTip(calendar.weekdaySymbols[weekday - 1], forSegment: segment)
        }
        let read: @MainActor () -> Void = { [weak self] in
            var value = rule
            value.startMinuteOfDay = minute(start)
            value.endMinuteOfDay = minute(end)
            value.weekdays = Set(weekdays.enumerated().compactMap { days.isSelected(forSegment: $0.offset) ? $0.element : nil })
            self?.update(.timeOfDay(value))
        }
        let rows = [
            NativeFormRow(title: String(localized: "From"), control: start),
            NativeFormRow(title: String(localized: "To"), control: end),
            NativeFormRow(title: String(localized: "Days"), control: days)
        ]
        rows[0].bind(start, action: read)
        rows[1].bind(end, action: read)
        rows[2].bind(days, action: read)
        return rows
    }

    private func appRow(_ trigger: ProfileTrigger, bundleIdentifier: String) -> NativeFormRow {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: String(localized: "Choose App"))
        for app in Self.appChoices(including: bundleIdentifier) {
            popup.addItem(withTitle: app.displayName)
            popup.lastItem?.representedObject = app.bundleIdentifier
            let icon = IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier).copy() as? NSImage
            icon?.size = CGSize(width: 16, height: 16)
            popup.lastItem?.image = icon
            if app.bundleIdentifier == bundleIdentifier { popup.select(popup.lastItem) }
        }
        let row = NativeFormRow(title: String(localized: "App"), control: popup)
        row.bind(popup) { [weak self] in
            let identifier = popup.selectedItem?.representedObject as? String ?? ""
            switch trigger {
            case .frontmostApp(var value):
                value.bundleIdentifier = identifier
                self?.update(.frontmostApp(value))
            case .space(var value):
                value.bundleIdentifier = identifier
                self?.update(.space(value))
            case .timeOfDay:
                break
            }
        }
        return row
    }

    /// Apps in Launchpad and running apps, by name, plus `identifier` when it's neither.
    private static func appChoices(including identifier: String) -> [AppTile] {
        var apps = LaunchpadOverlayService.shared.entries.flatMap { entry -> [AppTile] in
            switch entry {
            case .app(let app): [app]
            case .folder(let folder): folder.apps
            }
        }
        apps += NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier else { return nil }
            return AppTile(bundleIdentifier: bundleIdentifier, displayName: app.localizedName ?? bundleIdentifier)
        }
        var seen = Set<String>()
        apps = apps.filter { seen.insert($0.bundleIdentifier).inserted }
        if !identifier.isEmpty, !seen.contains(identifier) {
            apps.append(AppTile(bundleIdentifier: identifier, displayName: identifier))
        }
        return apps.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
