//
//  ViewExtensions.swift
//  PlayCover
//

import SwiftUI

extension View {
    func toastOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        safeAreaBar(edge: .bottom, content: content)
    }

    func toastBackground() -> some View {
        padding()
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .containerRelative)
            .padding(ToastView.toastGlassPadding)
            .padding(.top)
    }
}
