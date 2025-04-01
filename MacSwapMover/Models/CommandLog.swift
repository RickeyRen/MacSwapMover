import Foundation
import SwiftUI

// 命令日志的类型
enum CommandLogType {
    case info
    case warning
    case error
    case command
    case output
    
    // 返回图标名称
    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .command:
            return "terminal.fill"
        case .output:
            return "text.alignleft"
        }
    }
    
    // 返回图标颜色
    var iconColor: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .command:
            return .purple
        case .output:
            return .gray
        }
    }
}

// 命令日志结构
struct CommandLog: Identifiable {
    let id = UUID()
    let type: CommandLogType
    let message: String
    let timestamp: Date
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
} 