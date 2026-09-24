//
//  Sparkle.swift
//  PlayCover
//
//  Created by Andrew Glaze on 7/17/22.
//

import AppKit
import SwiftUI

// This fork distributes updates through GitHub Releases until it has a signed update feed.
final class UpdaterViewModel: ObservableObject {
    func checkForUpdates() {
        if let url = URL(string: "https://github.com/WainingCeoi/PlayCover/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button(NSLocalizedString("menubar.checkForUpdates", comment: ""),
               systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
               action: updaterViewModel.checkForUpdates)
    }
}
