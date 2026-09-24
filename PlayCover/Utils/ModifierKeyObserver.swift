//
//  ModifierKeyObserver.swift
//  PlayCover
//
//  Created by Venti on 14/02/2024.
//

import Foundation

class ModifierKeyObserver: ObservableObject {
    static let shared = ModifierKeyObserver()

    @Published var isOptionKeyPressed = false

    private var eventMonitor: Any?

    init() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .flagsChanged {
                self.isOptionKeyPressed = event.modifierFlags.contains(.option)
            }
            return event
        }
    }

    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
