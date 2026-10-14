//
//  SmartOrganizeProgressService.swift
//  Docky
//

import Combine
import Foundation

@MainActor
final class SmartOrganizeProgressService: ObservableObject {
    static let shared = SmartOrganizeProgressService()

    @Published private(set) var isPresented = false
    @Published private(set) var message = "Analyzing your workspace"

    private let messages = [
        "Analyzing your workspace",
        "Rubberizing your layout",
        "Grouping your launch crew",
        "Sorting the shiny things",
        "Polishing your dock flow",
    ]

    private var activeToken: UUID?
    private var rotationTask: Task<Void, Never>?

    private init() {}

    func begin() -> UUID {
        let token = UUID()
        activeToken = token
        message = messages[0]
        isPresented = true
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            guard let self else { return }
            var index = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard self.activeToken == token else { return }
                self.message = self.messages[index % self.messages.count]
                index += 1
            }
        }
        return token
    }

    func end(_ token: UUID) {
        guard activeToken == token else {
            return
        }

        activeToken = nil
        rotationTask?.cancel()
        rotationTask = nil
        isPresented = false
    }
}
