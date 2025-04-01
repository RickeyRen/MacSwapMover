import SwiftUI

struct CommandLogView: View {
    @ObservedObject var swapManager: SwapManager
    @State private var showFullLog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
            HStack {
                Text("操作日志")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 清除日志按钮
                Button(action: {
                    swapManager.clearLogs()
                }) {
                    Label("清除", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                // 展开/折叠日志按钮
                Button(action: {
                    withAnimation {
                        showFullLog.toggle()
                    }
                }) {
                    Label(showFullLog ? "收起" : "展开", systemImage: showFullLog ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // 日志列表 - 将复杂表达式拆分为子视图
            logListView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // 提取日志列表为单独的视图
    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                logContentView
            }
            .onChange(of: swapManager.commandLogs.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .frame(height: showFullLog ? 300 : 150)
            .background(Color(NSColor.textBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // 提取日志内容视图
    private var logContentView: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(swapManager.commandLogs.indices, id: \.self) { index in
                let log = swapManager.commandLogs[index]
                logRow(log: log)
                    .id(index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // 滚动到底部的函数
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if !swapManager.commandLogs.isEmpty {
            withAnimation {
                proxy.scrollTo(swapManager.commandLogs.count - 1, anchor: .bottom)
            }
        }
    }
    
    // 单行日志展示
    private func logRow(log: CommandLog) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // 图标
            Image(systemName: log.type.iconName)
                .foregroundColor(log.type.iconColor)
                .font(.system(size: 12))
                .frame(width: 16, height: 16)
            
            // 时间戳
            Text(log.formattedTimestamp)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            // 日志消息
            Text(log.message)
                .font(.system(size: 12))
                .foregroundColor(log.type == .error ? .red : .primary)
                .lineLimit(log.type == .output ? 5 : 2)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(log.type == .output ? Color.gray.opacity(0.05) : Color.clear)
        .cornerRadius(4)
    }
}

// 预览
struct CommandLogView_Previews: PreviewProvider {
    static var previews: some View {
        // 创建示例数据
        let swapManager = SwapManager()
        swapManager.commandLogs = [
            CommandLog(type: .info, message: "开始检查SIP状态", timestamp: Date()),
            CommandLog(type: .command, message: "/usr/bin/csrutil status", timestamp: Date()),
            CommandLog(type: .output, message: "System Integrity Protection status: disabled.", timestamp: Date()),
            CommandLog(type: .warning, message: "SIP已禁用，继续操作", timestamp: Date()),
            CommandLog(type: .error, message: "复制文件失败: 权限不足", timestamp: Date())
        ]
        
        return CommandLogView(swapManager: swapManager)
            .frame(width: 600)
            .padding()
            .background(Color.gray.opacity(0.1))
    }
} 