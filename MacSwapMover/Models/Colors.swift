//
//  Colors.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

enum AppColors {
    // Main colors - 更鲜明的蓝色和紫色渐变
    static let accentPrimary = Color(red: 0.2, green: 0.5, blue: 0.9)
    static let accentSecondary = Color(red: 0.5, green: 0.3, blue: 0.9)
    
    // Semantic colors - 更鲜明的语义色彩
    static let success = Color(red: 0.2, green: 0.8, blue: 0.2)
    static let warning = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let error = Color(red: 0.95, green: 0.2, blue: 0.2)
    static let info = Color(red: 0.2, green: 0.6, blue: 1.0)
    
    // Background colors
    static let background = Color(.windowBackgroundColor)
    static let cardBackground = Color(.controlBackgroundColor)
    static let elevatedBackground = Color(.controlBackgroundColor).opacity(0.8)
    
    // Text colors
    static let primaryText = Color(.labelColor)
    static let secondaryText = Color(.secondaryLabelColor)
    static let tertiaryText = Color(.tertiaryLabelColor)
    
    // Gradients
    static let accentGradient = LinearGradient(
        gradient: Gradient(colors: [accentPrimary, accentSecondary]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let secondaryGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.7, green: 0.2, blue: 0.7), Color(red: 0.9, green: 0.2, blue: 0.5)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// Note: Color extension for hex init has been moved to Extensions.swift
// to avoid duplicate declaration with the one in ContentView.swift 