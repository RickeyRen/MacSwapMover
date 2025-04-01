//
//  StatusIndicator.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

struct StatusIndicator: View {
    var isEnabled: Bool
    var enabledText: String
    var disabledText: String
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isEnabled ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            Text(isEnabled ? enabledText : disabledText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? .primary : .secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusIndicator(isEnabled: true, enabledText: "SIP Disabled", disabledText: "SIP Enabled")
        StatusIndicator(isEnabled: false, enabledText: "SIP Disabled", disabledText: "SIP Enabled")
    }
    .padding()
} 