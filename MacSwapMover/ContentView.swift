//
//  ContentView.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI
import Foundation
import Combine

struct ContentView: View {
    @StateObject private var swapManager = SwapManager()
    @State private var isMoving = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var isInitializing = true
    @State private var hoveredButton: String? = nil
    @State private var isLoading = false
    @State private var loadingMessage = "Processing..."
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showSettings = false
    
    // MARK: - Color Definitions
    private var backgroundColor = Color(.windowBackgroundColor)
    private var accentColor = Color.blue
    private var primaryTextColor = Color(.labelColor)
    private var secondaryTextColor = Color(.secondaryLabelColor)
    
    // MARK: - Color References
    
    // Colors
    private let cardBackgroundColor = AppColors.cardBackground
    private let textColor = AppColors.primaryText
    private let successColor = AppColors.success
    private let warningColor = AppColors.warning
    private let errorColor = AppColors.error
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(loadingMessage)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
            )
        }
        .transition(.opacity)
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color(.windowBackgroundColor).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // 头部区域
                header
                
                // 主要内容区域
                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: true) // 允许垂直方向自动调整大小
        .onAppear {
            isInitializing = true
            isLoading = true
            loadingMessage = "正在初始化..."
            
            // 不重复检查 SIP 状态，SwapManager 初始化时已经检查
            // 只检测交换文件位置和可用的外部驱动器
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await swapManager.detectSwapLocationAsync()
                    }
                    
                    group.addTask {
                        await swapManager.findAvailableExternalDrivesAsync()
                    }
                }
                
                await MainActor.run {
                    isInitializing = false
                    isLoading = false
                }
            }
            
            // 监听 SwapManager 的加载状态和错误
            swapManager.$isLoading.sink { loading in
                if !isInitializing {
                    isLoading = loading
                }
            }
            .store(in: &cancellables)
            
            swapManager.$lastError.sink { error in
                if let error = error {
                    errorMessage = error
                }
            }
            .store(in: &cancellables)
        }
        .alert("操作完成", isPresented: $showSuccessAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            let location = swapManager.currentSwapLocation == .internalDrive ? "内部驱动器" : "外部驱动器"
            Text("交换文件已成功移动到\(location)。")
        }
        .onChange(of: swapManager.lastError) { newError in
            if let error = newError {
                errorMessage = error
            }
        }
        .alert("操作失败", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // 应用标题和图标
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Swap Mover")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("优化您的系统性能，将交换文件移至外部驱动器")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // SIP状态图标
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(swapManager.isSIPDisabled ? "SIP已禁用" : "SIP已启用")
                            .font(.caption)
                            .foregroundColor(swapManager.isSIPDisabled ? .green : .red)
                        
                        Image(systemName: swapManager.isSIPDisabled ? "lock.open.fill" : "lock.fill")
                            .foregroundColor(swapManager.isSIPDisabled ? .green : .red)
                    }
                    
                    Button(action: {
                        swapManager.checkSIPStatus()
                    }) {
                        Text("检查SIP状态")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // 分隔线 - 使用渐变色实现更自然的过渡
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(.windowBackgroundColor).opacity(0.4), Color(.windowBackgroundColor).opacity(0.1)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 20)
        }
        .background(
            Color(.windowBackgroundColor)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 4)
        )
        .fixedSize(horizontal: false, vertical: true) // 确保头部高度适应内容
    }
    
    private var contentArea: some View {
        VStack(spacing: 24) {
            // 状态显示区域
            statusSection
            
            // 动作/操作区域
            actionSection
            
            // 命令日志区域 - 只有在有日志时才显示
            if !swapManager.commandLogs.isEmpty {
                CommandLogView(swapManager: swapManager)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut, value: !swapManager.commandLogs.isEmpty)
                    .fixedSize(horizontal: false, vertical: true) // 确保高度适应内容
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: true) // 允许垂直方向自动调整大小
    }
    
    private var statusSection: some View {
        VStack(spacing: 20) {
            // 当前交换文件状态
            VStack(alignment: .leading, spacing: 8) {
                Text("当前交换文件位置")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    statusCard(
                        title: "内部驱动器",
                        iconName: "internaldrive",
                        isActive: swapManager.currentSwapLocation == .internalDrive
                    )
                    
                    statusCard(
                        title: "外部驱动器",
                        iconName: "externaldrive",
                        isActive: swapManager.currentSwapLocation == .external
                    )
                }
            }
            .padding(16)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            if let error = swapManager.lastError {
                // 错误提示
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: {
                        swapManager.lastError = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut, value: swapManager.lastError != nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true) // 确保高度适应内容
    }
    
    private var actionSection: some View {
        VStack(spacing: 20) {
            // 选择外部驱动器
            if swapManager.availableExternalDrives.isEmpty {
                VStack(spacing: 12) {
                    Text("未检测到合适的外部驱动器")
                        .font(.headline)
                    
                    Text("请连接物理外部硬盘，如USB硬盘或Thunderbolt存储设备")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: {
                        swapManager.findAvailableExternalDrives()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新")
                        }
                        .frame(minWidth: 100)
                    }
                    .disabled(swapManager.isLoading)
                    .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("选择外部驱动器")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(swapManager.availableExternalDrives.count)个可用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Text("只显示物理外部硬盘，网络驱动器和虚拟磁盘已被过滤")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    ForEach(swapManager.availableExternalDrives) { drive in
                        Button(action: {
                            swapManager.selectedExternalDrive = drive
                        }) {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(drive.name)
                                        .font(.system(size: 14, weight: .medium))
                                    
                                    Text("\(drive.availableSpace) 可用 / \(drive.size) 总容量")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if drive.id == swapManager.selectedExternalDrive?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(drive.id == swapManager.selectedExternalDrive?.id ? Color.blue.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    HStack {
                        Button(action: {
                            swapManager.findAvailableExternalDrives()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新驱动器列表")
                            }
                        }
                        .disabled(swapManager.isLoading)
                        
                        Spacer()
                        
                        if swapManager.selectedExternalDrive != nil {
                            Button(action: {
                                swapManager.selectedExternalDrive = nil
                            }) {
                                Text("取消选择")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(12)
            }
            
            // 操作按钮
            VStack(spacing: 16) {
                // 内部移动到外部按钮
                Button(action: {
                    Task {
                        let result = await swapManager.moveSwapFile(to: .external)
                        switch result {
                        case .success:
                            swapManager.lastError = nil
                        case .failure(let error):
                            swapManager.lastError = error.localizedDescription
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("移动到外部驱动器")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                    .foregroundColor(.white)
                }
                .disabled(swapManager.isLoading || !swapManager.isSIPDisabled || swapManager.selectedExternalDrive == nil || swapManager.currentSwapLocation == .external)
                
                // 外部移动到内部按钮
                Button(action: {
                    Task {
                        let result = await swapManager.moveSwapFile(to: .internalDrive)
                        switch result {
                        case .success:
                            swapManager.lastError = nil
                        case .failure(let error):
                            swapManager.lastError = error.localizedDescription
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.left.circle.fill")
                        Text("移回内部驱动器")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green)
                    )
                    .foregroundColor(.white)
                }
                .disabled(swapManager.isLoading || !swapManager.isSIPDisabled || swapManager.currentSwapLocation == .internalDrive)
            }
            
            if swapManager.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(height: 60)
            }
        }
        .fixedSize(horizontal: false, vertical: true) // 确保高度适应内容
        .animation(.easeInOut, value: swapManager.isLoading)
        .animation(.easeInOut, value: swapManager.availableExternalDrives.isEmpty)
    }
    
    private func statusCard(title: String, iconName: String, isActive: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: iconName.appending(isActive ? ".fill" : ""))
                .font(.system(size: 28))
                .foregroundColor(isActive ? .green : .gray)
            
            Text(title)
                .font(.callout)
                .foregroundColor(isActive ? .primary : .secondary)
            
            Text(isActive ? "当前位置" : "")
                .font(.caption2)
                .foregroundColor(.green)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.green.opacity(0.1) : Color(.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Reusable Components
    
    private func statusCard(
        title: String,
        description: String,
        icon: String,
        status: Bool,
        enabledText: String,
        disabledText: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Refresh button
                Button(action: action) {
                    Label("Check", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            
            Divider()
            
            // Status
            HStack(spacing: 16) {
                // Status icon
                Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(status ? successColor : errorColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(status ? enabledText : disabledText)
                        .font(.headline)
                        .foregroundColor(textColor)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
            }
            
            // Info message for SIP
            if !status {
                infoMessage(
                    text: "To disable SIP, restart in Recovery Mode (⌘+R at startup) and run 'csrutil disable' in Terminal",
                    icon: "exclamationmark.triangle.fill",
                    color: warningColor
                )
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func locationCard(
        icon: String,
        title: String,
        location: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: "arrow.triangle.swap")
                    .font(.headline)
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Refresh button
                Button(action: action) {
                    Label("Check", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            
            Divider()
            
            // Location info
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(location)
                        .font(.headline)
                        .foregroundColor(textColor)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func driveCard(drive: ExternalDrive) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Drive icon and name
            HStack {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18))
                    .foregroundColor(accentColor)
                
                Text(drive.name)
                    .font(.headline)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if swapManager.selectedExternalDrive?.id == drive.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(successColor)
                }
            }
            
            Divider()
            
            // Drive info
            VStack(alignment: .leading, spacing: 8) {
                // Size
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                    
                    Text("Total: \(drive.size)")
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                }
                
                // Available space
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                    
                    Text("Available: \(drive.availableSpace)")
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                }
            }
        }
        .padding(16)
        .background(swapManager.selectedExternalDrive?.id == drive.id ? 
                   Color.blue.opacity(0.1) : Color(.quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(swapManager.selectedExternalDrive?.id == drive.id ? 
                       accentColor : Color.clear, lineWidth: 2)
        )
    }
    
    private var notificationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            
            Text(errorMessage ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    errorMessage = nil
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.red.opacity(0.8), Color.red.opacity(0.9)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func infoMessage(text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
    
    private func dividerWithIcon(systemName: String) -> some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separatorColor))
            
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundColor(accentColor)
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separatorColor))
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Actions
    
    private func moveSwap(to destination: DriveType) {
        guard swapManager.isSIPDisabled else {
            errorMessage = "System Integrity Protection must be disabled first."
            showErrorAlert = true
            return
        }
        
        if destination == .external && swapManager.selectedExternalDrive == nil {
            errorMessage = "Please select an external drive first."
            showErrorAlert = true
            return
        }
        
        isMoving = true
        
        Task {
            let result = await swapManager.moveSwapFile(to: destination)
            
            await MainActor.run {
                isMoving = false
                
                switch result {
                case .success:
                    showSuccessAlert = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func primaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(title)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.3), radius: 4, y: 2)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.borderless)
    }
    
    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(title)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
            )
            .foregroundColor(primaryTextColor)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Alert Handlers
extension ContentView {
    private var errorAlert: Alert {
        Alert(
            title: Text("错误"),
            message: Text(errorMessage ?? ""),
            dismissButton: .default(Text("确定"))
        )
    }
}

// MARK: - Supporting Views

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}
