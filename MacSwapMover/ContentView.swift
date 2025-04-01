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
            // Background color
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header area
                headerView
                
                // Main content
                VStack(spacing: 24) {
                    // Error notification
                    if let error = errorMessage {
                        notificationBanner
                            .padding(.bottom, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.3), value: errorMessage)
                    }
                    
                    // Status section
                    statusSection
                    
                    // Divider with icon
                    dividerWithIcon(systemName: "arrow.down")
                    
                    // Action section
                    actionSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                
                Spacer()
                
                // Footer
                footerView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Loading overlay
            if isLoading {
                loadingOverlay
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
            }
        }
        .frame(width: 720, height: 720)
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
    
    // MARK: - UI Components
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // 标题栏
            ZStack(alignment: .bottom) {
                AppColors.accentGradient
                    .frame(height: 110)
                    .overlay(
                        Circle()
                            .fill(.white.opacity(0.05))
                            .frame(width: 200)
                            .offset(x: 50, y: -80)
                    )
                
                VStack(spacing: 0) {
                    // App icon and title
                    HStack(spacing: 16) {
                        // App icon
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(.white)
                        }
                        
                        // App title
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacSwap Mover")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Optimize your system with external swap")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            
            // 添加一个占位区域，创造标题栏和内容之间的分隔
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            AppColors.accentSecondary.opacity(0.3),
                            backgroundColor
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 20) // 增加占位高度
        }
        .frame(height: 130) // 调整总高度以包含占位区域
    }
    
    private var statusSection: some View {
        VStack(spacing: 20) {
            swapFileLocationCard
            swapFileStatusCard
        }
    }
    
    private var swapFileLocationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: swapManager.currentSwapLocation == .internalDrive ? "internaldrive" : "externaldrive")
                        .font(.system(size: 18))
                        .foregroundColor(accentColor)
                    
                    Text("交换文件位置")
                        .font(.headline)
                        .foregroundColor(primaryTextColor)
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前位置:")
                            .font(.subheadline)
                            .foregroundColor(secondaryTextColor)
                        
                        Text(swapManager.currentSwapLocation == .internalDrive ? 
                             "/var/vm/swapfile" : 
                             (swapManager.selectedExternalDrive?.path ?? "") + "/private/var/vm/swapfile")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        swapManager.detectSwapLocation()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    private var swapFileStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 18))
                        .foregroundColor(accentColor)
                    
                    Text("系统状态")
                        .font(.headline)
                        .foregroundColor(primaryTextColor)
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        statusRow(label: "SIP 状态:", value: swapManager.isSIPDisabled ? "已禁用 (必需)" : "已启用 (无法进行操作)")
                        statusRow(label: "当前位置:", value: swapManager.currentSwapLocation == .internalDrive ? "内部驱动器" : "外部驱动器")
                        statusRow(label: "可用驱动器:", value: "\(swapManager.availableExternalDrives.count) 个")
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .stroke(
                                Color.gray.opacity(0.3),
                                lineWidth: 8
                            )
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: swapManager.isSIPDisabled ? 1.0 : 0.0)
                            .stroke(
                                swapManager.isSIPDisabled ? Color.green : Color.red,
                                style: StrokeStyle(
                                    lineWidth: 8,
                                    lineCap: .round
                                )
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                        
                        Image(systemName: swapManager.isSIPDisabled ? "checkmark" : "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(swapManager.isSIPDisabled ? Color.green : Color.red)
                    }
                }
                
                // SIP 状态说明
                if !swapManager.isSIPDisabled {
                    Divider()
                        .padding(.top, 4)
                    
                    infoMessage(
                        text: "要禁用 SIP，请重启进入恢复模式（开机时按住 ⌘+R），然后在终端中运行 'csrutil disable'",
                        icon: "exclamationmark.triangle.fill",
                        color: warningColor
                    )
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private func statusRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(primaryTextColor)
                .fontWeight(.medium)
        }
    }
    
    private var actionSection: some View {
        VStack(spacing: 20) {
            if swapManager.currentSwapLocation == .internalDrive {
                // Button to move swap to external drive
                primaryButton(
                    title: "移动交换文件到外部驱动器",
                    systemImage: "arrow.right.doc.on.clipboard",
                    action: { 
                        // Only show drive selection if there are available drives
                        if swapManager.availableExternalDrives.isEmpty {
                            errorMessage = "未检测到外部驱动器。请连接外部驱动器并重试。"
                        } else if !swapManager.isSIPDisabled {
                            errorMessage = "必须先禁用系统完整性保护（SIP）。"
                        } else {
                            // Show drive selection or perform move
                            isLoading = true
                            loadingMessage = "正在移动交换文件..."
                            
                            // Select the first drive if none selected
                            if swapManager.selectedExternalDrive == nil && !swapManager.availableExternalDrives.isEmpty {
                                swapManager.selectedExternalDrive = swapManager.availableExternalDrives.first
                            }
                            
                            Task {
                                let result = await swapManager.moveSwapFile(to: .external)
                                
                                await MainActor.run {
                                    isLoading = false
                                    
                                    switch result {
                                    case .success:
                                        showSuccessAlert = true
                                    case .failure(let error):
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                )
            } else {
                // Button to move swap back to internal drive
                primaryButton(
                    title: "移动交换文件回内部驱动器",
                    systemImage: "arrow.left.doc.on.clipboard",
                    action: { 
                        if !swapManager.isSIPDisabled {
                            errorMessage = "必须先禁用系统完整性保护（SIP）。"
                        } else {
                            isLoading = true
                            loadingMessage = "正在移动交换文件..."
                            
                            Task {
                                let result = await swapManager.moveSwapFile(to: .internalDrive)
                                
                                await MainActor.run {
                                    isLoading = false
                                    
                                    switch result {
                                    case .success:
                                        showSuccessAlert = true
                                    case .failure(let error):
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                )
            }
            
            secondaryButton(
                title: "检查系统状态",
                systemImage: "magnifyingglass",
                action: { 
                    isLoading = true
                    loadingMessage = "正在检查系统状态..."
                    
                    Task {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                await swapManager.checkSIPStatusAsync()
                            }
                            
                            group.addTask {
                                await swapManager.detectSwapLocationAsync()
                            }
                            
                            group.addTask {
                                await swapManager.findAvailableExternalDrivesAsync()
                            }
                        }
                        
                        await MainActor.run {
                            isLoading = false
                            
                            if let error = swapManager.lastError {
                                errorMessage = error
                            }
                        }
                    }
                }
            )
        }
    }
    
    private var footerView: some View {
        HStack {
            // Credits
            Text("© 2025 RENJIAWEI")
                .font(.caption)
                .foregroundColor(secondaryTextColor)
            
            Spacer()
            
            // Additional info button
            Button(action: {
                // TODO: Show info panel
            }) {
                Label("Help", systemImage: "questionmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(backgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 3, y: -2)
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
