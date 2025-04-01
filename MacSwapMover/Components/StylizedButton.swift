//
//  StylizedButton.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

struct StylizedButton: View {
    var text: String
    var icon: String
    var backgroundColor: Color
    var isEnabled: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isEnabled ? backgroundColor : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(color: isEnabled ? backgroundColor.opacity(0.3) : Color.clear, radius: 5, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}

#Preview {
    VStack(spacing: 20) {
        StylizedButton(
            text: "Move to Internal Drive",
            icon: "arrow.left.arrow.right",
            backgroundColor: .blue,
            isEnabled: true,
            action: {}
        )
        
        StylizedButton(
            text: "Move to External Drive",
            icon: "externaldrive",
            backgroundColor: .green,
            isEnabled: false,
            action: {}
        )
    }
    .padding()
} 