//
//  SwapManager.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import Foundation

// MARK: - Models & Enums

/// Represents the type of drive where swap file is located
enum DriveType {
    case systemDrive
    case otherDrive
}

/// Drive information structure
struct DriveInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: String
    let availableSpace: String
    let isSystemDrive: Bool
    
    // Current swap location indicator
    var containsSwapFile: Bool = false
}

/// Errors that can occur during swap operations
enum SwapOperationError: Error {
    case sipEnabled
    case insufficientPermissions
    case commandExecutionFailed(String)
    case driveNotFound
    case noSwapFile
    case unknownError
    
    var localizedDescription: String {
        switch self {
        case .sipEnabled:
            return "系统完整性保护（SIP）已启用。请先禁用它才能继续。"
        case .insufficientPermissions:
            return "没有足够的权限修改系统文件。"
        case .commandExecutionFailed(let message):
            return "命令执行失败：\(message)"
        case .driveNotFound:
            return "未找到选择的驱动器。"
        case .noSwapFile:
            return "在预期位置找不到交换文件。"
        case .unknownError:
            return "发生未知错误。"
        }
    }
}

/// Manages all operations related to the swap file
class SwapManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isSIPDisabled = false
    @Published var currentSwapDrive: DriveInfo?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var availableDrives: [DriveInfo] = []
    @Published var selectedDrive: DriveInfo?
    @Published var commandLogs: [CommandLog] = [] // 存储命令日志
    
    // MARK: - Private Properties
    
    private let swapFilePath = "/private/var/vm/swapfile"
    private let systemSwapPath = "/var/vm/swapfile"
    private let timeoutShort: UInt64 = 3_000_000_000 // 3 seconds
    private let timeoutMedium: UInt64 = 5_000_000_000 // 5 seconds
    private let timeoutLong: UInt64 = 15_000_000_000 // 15 seconds
    private let isDebugMode = true // 开启调试模式
    private var rootVolumeURL: URL? // 系统根卷的URL
    
    // MARK: - 日志功能
    
    private func logInfo(_ message: String) {
        if isDebugMode {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = dateFormatter.string(from: Date())
            print("[\(timestamp)] ℹ️ INFO: \(message)")
            
            DispatchQueue.main.async {
                self.commandLogs.append(CommandLog(type: .info, message: message, timestamp: Date()))
            }
        }
    }
    
    private func logWarning(_ message: String) {
        if isDebugMode {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = dateFormatter.string(from: Date())
            print("[\(timestamp)] ⚠️ WARNING: \(message)")
            
            DispatchQueue.main.async {
                self.commandLogs.append(CommandLog(type: .warning, message: message, timestamp: Date()))
            }
        }
    }
    
    private func logError(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] ❌ ERROR: \(message)")
        
        DispatchQueue.main.async {
            self.commandLogs.append(CommandLog(type: .error, message: message, timestamp: Date()))
        }
    }
    
    private func logCommand(_ command: String, arguments: [String]) {
        if isDebugMode {
            let fullCommand = ([command] + arguments).joined(separator: " ")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = dateFormatter.string(from: Date())
            print("[\(timestamp)] 🔄 COMMAND: \(fullCommand)")
            
            DispatchQueue.main.async {
                self.commandLogs.append(CommandLog(type: .command, message: fullCommand, timestamp: Date()))
            }
        }
    }
    
    private func logCommandOutput(_ output: String) {
        if isDebugMode {
            let lines = output.split(separator: "\n")
            for line in lines {
                print("  └─ \(line)")
            }
            
            if !output.isEmpty {
                DispatchQueue.main.async {
                    self.commandLogs.append(CommandLog(type: .output, message: output, timestamp: Date()))
                }
            }
        }
    }
    
    // 清除日志
    func clearLogs() {
        DispatchQueue.main.async {
            self.commandLogs.removeAll()
        }
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            // 初始化根卷URL
            rootVolumeURL = getSystemRootURL()
            
            // 自动在应用启动时检查 SIP 状态
            await checkSIPStatusAsync()
        }
    }
    
    // 获取系统根卷URL
    private func getSystemRootURL() -> URL? {
        // macOS通常使用"/"作为根卷路径
        return URL(fileURLWithPath: "/")
    }
    
    // MARK: - Public Methods
    
    /// Initialize the manager and gather system information
    func initialize() {
        Task {
            await checkAndInitializeAsync()
        }
    }
    
    /// Check SIP Status
    func checkSIPStatus() {
        Task {
            await checkSIPStatusAsync()
        }
    }
    
    /// Find available drives
    func findAvailableDrives() {
        Task {
            await findAvailableDrivesAsync()
        }
    }
    
    /// Detect current swap file location
    func detectSwapLocation() {
        Task {
            await detectSwapLocationAsync()
        }
    }
    
    /// Move swap file to specified destination drive
    /// - Parameter destinationDrive: Drive to move the swap file to
    /// - Returns: Result indicating success or failure with error
    func moveSwapFile(to destinationDrive: DriveInfo) async -> Result<Void, SwapOperationError> {
        logInfo("开始移动交换文件操作，目标位置: \(destinationDrive.name)")
        
        guard isSIPDisabled else {
            logError("SIP未禁用，无法继续")
            return .failure(.sipEnabled)
        }
        
        // 确保目标驱动器有效
        if availableDrives.first(where: { $0.id == destinationDrive.id }) == nil {
            logError("未找到选定的驱动器: \(destinationDrive.name)")
            return .failure(.driveNotFound)
        }
        
        // 更新UI状态
        await MainActor.run {
            isLoading = true
        }
        
        // 1. 首先尝试获取管理员权限
        do {
            logInfo("正在检查管理员权限...")
            let hasAdminPrivileges = try await checkAdminPrivileges()
            if !hasAdminPrivileges {
                // 如果没有管理员权限，尝试获取
                logInfo("需要获取管理员权限，正在请求...")
                let gotPrivileges = try await requestAdminPrivileges()
                if !gotPrivileges {
                    logError("获取管理员权限失败")
                    await MainActor.run { isLoading = false }
                    return .failure(.insufficientPermissions)
                }
                logInfo("成功获取管理员权限")
            } else {
                logInfo("已有管理员权限")
            }
        } catch {
            logError("权限检查过程中出错: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("获取管理员权限失败: \(error.localizedDescription)"))
        }
        
        // 2. 停用交换文件
        do {
            logInfo("正在检查交换文件状态...")
            // 先检查当前的交换文件状态
            let swapStatus = try await executeCommandWithOutput("/usr/sbin/sysctl", arguments: ["vm.swap_enabled"], timeout: timeoutShort)
            let isSwapEnabled = swapStatus.contains("vm.swap_enabled: 1")
            
            if isSwapEnabled {
                logInfo("交换文件当前已启用，正在停用...")
                // 使用sudo获取权限停用交换文件
                try await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=0"])
                logInfo("交换文件已成功停用")
            } else {
                logInfo("交换文件当前已停用，继续操作")
            }
        } catch {
            logError("停用交换文件失败: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("停用交换文件失败: \(error.localizedDescription)"))
        }
        
        // 3. 移动交换文件
        do {
            if let currentSwap = currentSwapDrive {
                // 如果目标驱动器就是当前驱动器，则不需要移动
                if currentSwap.id == destinationDrive.id {
                    logInfo("交换文件已经在目标驱动器上: \(destinationDrive.name)")
                } else {
                    logInfo("准备将交换文件从 \(currentSwap.name) 移动到 \(destinationDrive.name)...")
                    try await moveSwapFileBetweenDrivesWithAdmin(from: currentSwap, to: destinationDrive)
                    logInfo("交换文件已成功移动到: \(destinationDrive.name)")
                }
            } else {
                // 如果无法检测当前交换文件位置，则创建一个新的在目标驱动器上
                logInfo("无法检测当前交换文件位置，在目标驱动器上创建新文件: \(destinationDrive.name)...")
                try await createSwapFileOnDriveWithAdmin(destinationDrive)
                logInfo("交换文件已成功创建在: \(destinationDrive.name)")
            }
        } catch {
            // 出错时尝试重新启用交换文件
            logError("移动交换文件时出错: \(error.localizedDescription)")
            logInfo("正在尝试恢复交换文件启用状态...")
            try? await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=1"])
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("移动交换文件失败: \(error.localizedDescription)"))
        }
        
        // 4. 重新启用交换文件
        do {
            logInfo("正在重新启用交换文件...")
            try await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=1"])
            logInfo("交换文件已成功重新启用")
        } catch {
            logError("重新启用交换文件失败: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("重新启用交换文件失败: \(error.localizedDescription)"))
        }
        
        // 5. 更新当前位置状态和刷新驱动器列表
        logInfo("操作完成，更新UI状态...")
        await detectSwapLocationAsync()
        await findAvailableDrivesAsync()
        
        await MainActor.run {
            isLoading = false
        }
        logInfo("交换文件移动操作全部完成")
        return .success(())
    }
    
    // MARK: - Private Methods - Core Logic
    
    private func checkAndInitializeAsync() async {
        // First check permissions
        let hasPermission = await checkFilePermissions()
        
        if !hasPermission {
            await MainActor.run {
                lastError = "应用程序缺少足够的权限来访问系统文件。请从应用程序文件夹运行并授予必要的权限。"
                isLoading = false
            }
            return
        }
        
        // Check SIP status immediately, it's most important
        await checkSIPStatusAsync()
        
        // Then execute other operations in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.detectSwapLocationAsync()
            }
            
            group.addTask {
                await self.findAvailableDrivesAsync()
            }
        }
    }
    
    // MARK: - Private Methods - System Checks
    
    private func checkFilePermissions() async -> Bool {
        let swapDirectoryPath = URL(fileURLWithPath: "/private/var/vm")
        let fileManager = FileManager.default
        
        // Check if directory exists and is accessible
        if !fileManager.fileExists(atPath: swapDirectoryPath.path) {
            return false
        }
        
        // Try to list directory contents to check permissions
        do {
            let _ = try fileManager.contentsOfDirectory(at: swapDirectoryPath, includingPropertiesForKeys: nil)
            return true
        } catch {
            return false
        }
    }
    
    func checkSIPStatusAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let output = try await executeCommandWithOutput("/usr/bin/csrutil", arguments: ["status"], timeout: timeoutMedium)
            
            logInfo("SIP 检查输出: \(output)")
            
            await MainActor.run {
                isSIPDisabled = output.lowercased().contains("disabled")
                isLoading = false
                logInfo("SIP 状态更新为: \(isSIPDisabled ? "已禁用" : "已启用")")
            }
        } catch {
            await MainActor.run {
                lastError = "检查 SIP 状态失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func findAvailableDrivesAsync() async {
        await MainActor.run {
            isLoading = true
            availableDrives = []
        }
        
        do {
            let fileManager = FileManager.default
            let volumesURL = URL(fileURLWithPath: "/Volumes")
            
            var drives: [DriveInfo] = []
            
            // 添加系统驱动器
            if let systemDrive = await extractSystemDriveInfo() {
                drives.append(systemDrive)
            }
            
            // Try to list volume directories, return early if failed
            let volumes: [URL]
            do {
                volumes = try fileManager.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil)
            } catch {
                await MainActor.run { 
                    isLoading = false
                    lastError = "无法访问 /Volumes 目录: \(error.localizedDescription)"
                }
                return
            }
            
            for volume in volumes {
                if let drive = await extractDriveInfo(from: volume) {
                    // 检查是否是系统驱动器，避免重复
                    if !drives.contains(where: { $0.path == drive.path }) {
                        drives.append(drive)
                    }
                }
            }
            
            // 标记当前交换文件所在的驱动器
            await markCurrentSwapDrive(in: &drives)
            
            await MainActor.run {
                availableDrives = drives
                
                // 设置当前交换文件所在驱动器
                currentSwapDrive = drives.first(where: { $0.containsSwapFile })
                
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = "查找可用驱动器失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    /// 提取系统驱动器信息
    private func extractSystemDriveInfo() async -> DriveInfo? {
        guard let rootURL = rootVolumeURL else { return nil }
        
        do {
            let resourceValues = try rootURL.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            guard let totalCapacity = resourceValues.volumeTotalCapacity,
                  let availableCapacity = resourceValues.volumeAvailableCapacity else {
                return nil
            }
            
            // 格式化大小为GB
            let totalGB = String(format: "%.1f GB", Double(totalCapacity) / 1_000_000_000)
            let availableGB = String(format: "%.1f GB", Double(availableCapacity) / 1_000_000_000)
            
            // 使用主机名作为驱动器名称，或使用默认名称
            var systemName = "System Drive"
            if let hostName = try? executeCommandWithOutput("/bin/hostname", arguments: [], timeout: timeoutShort).trimmingCharacters(in: .whitespacesAndNewlines) {
                systemName = "\(hostName) (System)"
            }
            
            return DriveInfo(
                name: systemName,
                path: rootURL.path,
                size: totalGB,
                availableSpace: availableGB,
                isSystemDrive: true
            )
        } catch {
            logError("提取系统驱动器信息失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 从卷URL提取驱动器信息
    private func extractDriveInfo(from volume: URL) async -> DriveInfo? {
        do {
            let resourceValues = try volume.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            guard let name = resourceValues.volumeName,
                  let totalCapacity = resourceValues.volumeTotalCapacity,
                  let availableCapacity = resourceValues.volumeAvailableCapacity else {
                return nil
            }
            
            // 格式化大小为GB
            let totalGB = String(format: "%.1f GB", Double(totalCapacity) / 1_000_000_000)
            let availableGB = String(format: "%.1f GB", Double(availableCapacity) / 1_000_000_000)
            
            // 确定是否为系统驱动器
            let isSystemDrive = volume.path == rootVolumeURL?.path || 
                               name.contains("Macintosh HD") ||
                               volume.path.hasPrefix("/System")
            
            return DriveInfo(
                name: name,
                path: volume.path,
                size: totalGB,
                availableSpace: availableGB,
                isSystemDrive: isSystemDrive
            )
        } catch {
            return nil
        }
    }
    
    /// 标记当前交换文件所在的驱动器
    private func markCurrentSwapDrive(in drives: inout [DriveInfo]) async {
        do {
            let output = try await executeCommandWithOutput("/usr/bin/ls", arguments: ["-la", swapFilePath], timeout: timeoutShort)
            logInfo("交换文件链接检查结果: \(output)")
            
            // 如果包含 -> 符号，说明是符号链接
            if output.contains("->") {
                if let targetPath = output.components(separatedBy: "->").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // 获取目标路径所在的驱动器
                    let targetURL = URL(fileURLWithPath: targetPath)
                    let targetDrivePath = targetURL.pathComponents.prefix(2).joined(separator: "/")
                    
                    logInfo("交换文件指向: \(targetPath)")
                    logInfo("交换文件所在驱动器路径: \(targetDrivePath)")
                    
                    // 更新驱动器列表，标记含有交换文件的驱动器
                    for i in 0..<drives.count {
                        if targetPath.hasPrefix(drives[i].path) {
                            drives[i].containsSwapFile = true
                            logInfo("标记驱动器 \(drives[i].name) 为当前交换文件位置")
                        } else {
                            drives[i].containsSwapFile = false
                        }
                    }
                }
            } else {
                // 如果不是符号链接，说明在系统驱动器上
                for i in 0..<drives.count {
                    if drives[i].isSystemDrive {
                        drives[i].containsSwapFile = true
                        logInfo("标记系统驱动器 \(drives[i].name) 为当前交换文件位置")
                    } else {
                        drives[i].containsSwapFile = false
                    }
                }
            }
        } catch {
            logError("检查交换文件位置失败: \(error.localizedDescription)")
            
            // 如果无法确定，默认标记系统驱动器
            for i in 0..<drives.count {
                drives[i].containsSwapFile = drives[i].isSystemDrive
            }
        }
    }
    
    func detectSwapLocationAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let output = try await executeCommandWithOutput("/usr/bin/ls", arguments: ["-la", swapFilePath], timeout: timeoutShort)
            
            // 如果是符号链接且指向外部驱动器
            if output.contains("->") && output.contains("/Volumes/") {
                if let targetPath = output.components(separatedBy: "->").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let targetURL = URL(fileURLWithPath: targetPath)
                    let targetDrivePath = targetURL.pathComponents.prefix(2).joined(separator: "/")
                    
                    // 找到对应的驱动器
                    var foundDrive: DriveInfo? = nil
                    for drive in availableDrives {
                        if targetPath.hasPrefix(drive.path) {
                            foundDrive = drive
                            break
                        }
                    }
                    
                    await MainActor.run {
                        currentSwapDrive = foundDrive
                        isLoading = false
                    }
                }
            } else {
                // 交换文件在系统驱动器上
                let systemDrive = availableDrives.first(where: { $0.isSystemDrive })
                
                await MainActor.run {
                    currentSwapDrive = systemDrive
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                lastError = "检测交换文件位置失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    // MARK: - Private Methods - Swap File Operations
    
    /// 在驱动器之间移动交换文件（使用管理员权限）
    private func moveSwapFileBetweenDrivesWithAdmin(from sourceDrive: DriveInfo, to destinationDrive: DriveInfo) async throws {
        // 构建目标路径
        let targetDirectory = "\(destinationDrive.path)/private/var/vm"
        let targetSwapFile = "\(targetDirectory)/swapfile"
        
        // 1. 在目标驱动器上创建目录结构
        logInfo("在目标驱动器上创建目录结构: \(targetDirectory)")
        try await executeCommandWithAdmin("/bin/mkdir", arguments: ["-p", targetDirectory])
        
        // 2. 检查目标驱动器上是否已有交换文件
        logInfo("检查目标驱动器上是否已有交换文件...")
        let externalSwapExists = (try? await executeCommandWithOutput("/usr/bin/test", arguments: ["-f", targetSwapFile], timeout: timeoutShort)) != nil
        
        if externalSwapExists {
            // 如果已存在，先删除
            logInfo("目标驱动器上已有交换文件，正在删除...")
            try await executeCommandWithAdmin("/bin/rm", arguments: [targetSwapFile])
        }
        
        // 3. 复制现有交换文件到目标驱动器
        logInfo("复制交换文件到目标驱动器: \(targetSwapFile)")
        try await executeCommandWithAdmin("/bin/cp", arguments: [swapFilePath, targetSwapFile])
        
        // 4. 设置适当的权限
        logInfo("设置交换文件权限...")
        try await executeCommandWithAdmin("/bin/chmod", arguments: ["644", targetSwapFile])
        
        // 5. 删除原始交换文件
        logInfo("删除原驱动器上的交换文件...")
        try await executeCommandWithAdmin("/bin/rm", arguments: [swapFilePath])
        
        // 6. 创建符号链接
        logInfo("创建符号链接，将原路径指向新的交换文件...")
        try await executeCommandWithAdmin("/bin/ln", arguments: ["-s", targetSwapFile, swapFilePath])
        logInfo("符号链接创建完成")
    }
    
    /// 在指定驱动器上创建新的交换文件（使用管理员权限）
    private func createSwapFileOnDriveWithAdmin(_ drive: DriveInfo) async throws {
        if drive.isSystemDrive {
            // 如果是系统驱动器，使用dynamic_pager创建标准交换文件
            logInfo("在系统驱动器上创建交换文件...")
            try await executeCommandWithAdmin("/usr/sbin/dynamic_pager", arguments: ["-F", swapFilePath])
            logInfo("系统驱动器交换文件创建完成")
        } else {
            // 为外部驱动器创建目录结构和交换文件
            let targetDirectory = "\(drive.path)/private/var/vm"
            let targetSwapFile = "\(targetDirectory)/swapfile"
            
            // 1. 创建目录结构
            logInfo("在驱动器上创建目录结构: \(targetDirectory)")
            try await executeCommandWithAdmin("/bin/mkdir", arguments: ["-p", targetDirectory])
            
            // 2. 创建空交换文件 (1GB大小)
            logInfo("创建1GB大小的交换文件...")
            try await executeCommandWithAdmin("/usr/bin/dd", arguments: ["if=/dev/zero", "of=\(targetSwapFile)", "bs=1m", "count=1024"])
            
            // 3. 设置适当的权限
            logInfo("设置交换文件权限...")
            try await executeCommandWithAdmin("/bin/chmod", arguments: ["644", targetSwapFile])
            
            // 4. 创建符号链接
            logInfo("创建符号链接，将系统路径指向新的交换文件...")
            try await executeCommandWithAdmin("/bin/ln", arguments: ["-s", targetSwapFile, swapFilePath])
            logInfo("符号链接创建完成")
        }
    }
    
    // MARK: - Private Methods - Command Execution
    
    private func executeCommand(_ command: String, arguments: [String]) async throws {
        logCommand(command, arguments: arguments)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Add timeout handling
        do {
            try await withTaskTimeoutHandling(process: process, timeout: timeoutLong)
            logInfo("命令执行成功: \(command)")
        } catch {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "未知错误"
            logError("命令执行失败: \(command)\n错误信息: \(errorOutput)")
            throw SwapOperationError.commandExecutionFailed(errorOutput)
        }
    }
    
    private func executeCommandWithOutput(_ command: String, arguments: [String], timeout: UInt64) async throws -> String {
        logCommand(command, arguments: arguments)
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        
        do {
            try await withTaskTimeoutHandling(process: process, timeout: timeout)
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            logInfo("命令执行成功: \(command)")
            logCommandOutput(output)
            
            return output
        } catch {
            logError("命令执行失败: \(command)\n错误信息: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func executeCommandWithPlist(_ command: String, arguments: [String], timeout: UInt64) async throws -> [String: Any] {
        logCommand(command, arguments: arguments)
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        
        do {
            try await withTaskTimeoutHandling(process: process, timeout: timeout)
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            do {
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    logInfo("命令执行成功并解析了Plist: \(command)")
                    return plist
                }
                logWarning("命令执行成功但Plist解析失败: \(command)")
                return [:]
            } catch {
                logError("Plist解析失败: \(error.localizedDescription)")
                return [:]
            }
        } catch {
            logError("命令执行失败: \(command)\n错误信息: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func withTaskTimeoutHandling(process: Process, timeout: UInt64) async throws {
        let executeTask = Task {
            do {
                try process.run()
                process.waitUntilExit()
                return true
            } catch {
                logError("进程启动失败: \(error.localizedDescription)")
                return false
            }
        }
        
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout)
                if process.isRunning {
                    logWarning("命令执行超时，正在终止进程")
                    process.terminate()
                    return false
                }
                return true
            } catch {
                logError("超时处理失败: \(error.localizedDescription)")
                return false
            }
        }
        
        let success = try await timeoutTask.value
        let executionSucceeded = try await executeTask.value
        
        if !success || !executionSucceeded {
            logError("命令执行失败: 超时或执行错误")
            throw SwapOperationError.commandExecutionFailed("命令超时或执行失败")
        }
    }
    
    // MARK: - Private Methods - Admin Privileges
    
    /// 检查当前是否有管理员权限
    private func checkAdminPrivileges() async throws -> Bool {
        logInfo("检查是否有管理员权限...")
        do {
            // 尝试访问一个需要管理员权限的命令
            let output = try await executeCommandWithOutput("/usr/bin/sudo", arguments: ["-n", "true"], timeout: timeoutShort)
            logInfo("管理员权限检查成功")
            return true
        } catch {
            logInfo("当前没有管理员权限")
            return false
        }
    }
    
    /// 请求管理员权限
    private func requestAdminPrivileges() async throws -> Bool {
        logInfo("正在请求管理员权限...")
        do {
            // 使用AppleScript显示管理员权限请求对话框
            let script = """
            do shell script "echo 'Admin privileges granted'" with administrator privileges
            """
            
            logInfo("显示管理员权限请求对话框")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            try process.run()
            process.waitUntilExit()
            
            let success = process.terminationStatus == 0
            if success {
                logInfo("用户授予了管理员权限")
            } else {
                logError("用户拒绝了管理员权限请求")
            }
            return success
        } catch {
            logError("请求管理员权限过程中出错: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 使用管理员权限执行命令
    private func executeCommandWithAdmin(_ command: String, arguments: [String]) async throws {
        logCommand(command, arguments: arguments)
        logInfo("以管理员权限执行命令")
        
        let fullCommand = ([command] + arguments).joined(separator: " ")
        let sudoCommand = "do shell script \"\(fullCommand)\" with administrator privileges"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", sudoCommand]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "未知错误"
                logError("管理员权限命令执行失败: \(command)\n错误信息: \(errorOutput)")
                throw SwapOperationError.commandExecutionFailed(errorOutput)
            } else {
                logInfo("管理员权限命令执行成功: \(command)")
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                    logCommandOutput(output)
                }
            }
        } catch {
            logError("管理员权限命令执行过程中出错: \(error.localizedDescription)")
            throw error
        }
    }
} 