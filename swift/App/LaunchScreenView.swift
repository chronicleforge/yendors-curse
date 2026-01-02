//
//  LaunchScreenView.swift
//  nethack
//
//  Launch screen that displays while dylib is loading.
//  Uses UnifiedLoadingView for consistent dungeon theme.
//

import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        UnifiedLoadingView(state: .launching)
    }
}

#Preview {
    LaunchScreenView()
        .preferredColorScheme(.dark)
}
