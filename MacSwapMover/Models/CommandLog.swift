import Foundation
import SwiftUI

// 命令日志的类型
enum CommandLogType: String {
    case info
    case warning
    case error
    case command
    case output
    
    // 返回图标名称
    var iconName: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        case .command:
            return "terminal"
        case .output:
            return "text.append"
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
struct CommandLog: Identifiable, Equatable {
    let id = UUID()
    let type: CommandLogType
    let message: String
    let timestamp: Date
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    // 添加 Equatable 协议实现
    static func == (lhs: CommandLog, rhs: CommandLog) -> Bool {
        return lhs.id == rhs.id && 
               lhs.type == rhs.type && 
               lhs.message == rhs.message && 
               lhs.timestamp == rhs.timestamp
    }
} 