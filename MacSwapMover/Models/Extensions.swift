//
//  Extensions.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

// Color extensions
extension Color {
    init(hex: String, opacity: Double = 1.0) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// View extensions
extension View {
    func onBackgroundChange(_ perform: @escaping () -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            perform()
        }
    }
} 