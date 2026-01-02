//
//  CompactStatColumn.swift
//  nethack
//
//  Compact stat display for hero card (icon + value)
//

import SwiftUI

struct CompactStatColumn: View {
    let icon: String
    let iconColor: Color
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
