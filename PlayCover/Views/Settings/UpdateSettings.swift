//
//  UpdateSettings.swift
//  PlayCover
//
//  Created by Andrew Glaze on 7/23/22.
//

import SwiftUI

struct UpdateSettings: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Form {
            Text("Updates for this fork are available on GitHub Releases. Download and install new versions manually.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("preferences.button.checkForUpdates") {
                updaterViewModel.checkForUpdates()
            }
        }
        .padding(20)
        .frame(width: 600, height: 120, alignment: .center)
    }
}
