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
    case internalDrive
    case external
}

/// Errors that can occur during swap operations
enum SwapOperationError: Error {
    case sipEnabled
    case insufficientPermissions
    case commandExecutionFailed(String)
    case externalDriveNotFound
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
        case .externalDriveNotFound:
            return "没有选择或没有可用的外部驱动器。"
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
    @Published var currentSwapLocation: DriveType = .internalDrive
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var availableExternalDrives: [ExternalDrive] = []
    @Published var selectedExternalDrive: ExternalDrive?
    @Published var commandLogs: [CommandLog] = [] // 存储命令日志
    
    // MARK: - Private Properties
    
    private let swapFilePath = "/private/var/vm/swapfile"
    private let timeoutShort: UInt64 = 3_000_000_000 // 3 seconds
    private let timeoutMedium: UInt64 = 5_000_000_000 // 5 seconds
    private let timeoutLong: UInt64 = 15_000_000_000 // 15 seconds
    private let isDebugMode = true // 开启调试模式
    
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
        // 自动在应用启动时检查 SIP 状态
        Task {
            await checkSIPStatusAsync()
        }
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
    
    /// Find available external drives
    func findAvailableExternalDrives() {
        Task {
            await findAvailableExternalDrivesAsync()
        }
    }
    
    /// Detect current swap file location
    func detectSwapLocation() {
        Task {
            await detectSwapLocationAsync()
        }
    }
    
    /// Move swap file to specified destination with admin privileges
    /// - Parameter destination: Where to move the swap file
    /// - Returns: Result indicating success or failure with error
    func moveSwapFile(to destination: DriveType) async -> Result<Void, SwapOperationError> {
        logInfo("开始移动交换文件操作，目标位置: \(destination == .internalDrive ? "内部驱动器" : "外部驱动器")")
        
        guard isSIPDisabled else {
            logError("SIP未禁用，无法继续")
            return .failure(.sipEnabled)
        }
        
        if destination == .external && selectedExternalDrive == nil {
            logError("未选择外部驱动器")
            return .failure(.externalDriveNotFound)
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
        
        // 3. 移动或创建交换文件
        do {
            if destination == .internalDrive {
                logInfo("准备将交换文件移回内部驱动器...")
                try await moveToInternalDriveWithAdmin()
                logInfo("交换文件已成功移回内部驱动器")
            } else {
                guard let externalDrive = selectedExternalDrive else {
                    logError("未找到选定的外部驱动器")
                    await MainActor.run { isLoading = false }
                    return .failure(.externalDriveNotFound)
                }
                
                logInfo("准备将交换文件移动到外部驱动器: \(externalDrive.name)...")
                try await moveToExternalDriveWithAdmin(externalDrive)
                logInfo("交换文件已成功移动到外部驱动器: \(externalDrive.name)")
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
        
        // 5. 更新当前位置状态
        logInfo("操作完成，更新UI状态...")
        await MainActor.run {
            currentSwapLocation = destination
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
                await self.findAvailableExternalDrivesAsync()
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
            
            print("SIP 检查输出: \(output)")
            
            await MainActor.run {
                isSIPDisabled = output.lowercased().contains("disabled")
                isLoading = false
                print("SIP 状态更新为: \(isSIPDisabled ? "已禁用" : "已启用")")
            }
        } catch {
            await MainActor.run {
                lastError = "检查 SIP 状态失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func findAvailableExternalDrivesAsync() async {
        await MainActor.run {
            isLoading = true
            availableExternalDrives = []
        }
        
        do {
            let fileManager = FileManager.default
            let volumesURL = URL(fileURLWithPath: "/Volumes")
            
            var drives: [ExternalDrive] = []
            
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
                    // 只添加如果它不是启动卷并且是物理硬盘
                    let isBootVolume = await checkIsBootVolumeAsync(path: volume.path)
                    let isPhysicalDrive = await isPhysicalExternalDriveAsync(path: volume.path)
                    
                    if !isBootVolume && isPhysicalDrive {
                        drives.append(drive)
                    }
                }
            }
            
            await MainActor.run {
                availableExternalDrives = drives
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = "查找外部驱动器失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func extractDriveInfo(from volume: URL) async -> ExternalDrive? {
        do {
            let resourceValues = try volume.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            guard let name = resourceValues.volumeName,
                  let totalCapacity = resourceValues.volumeTotalCapacity,
                  let availableCapacity = resourceValues.volumeAvailableCapacity else {
                return nil
            }
            
            // Format sizes in GB
            let totalGB = String(format: "%.1f GB", Double(totalCapacity) / 1_000_000_000)
            let availableGB = String(format: "%.1f GB", Double(availableCapacity) / 1_000_000_000)
            
            return ExternalDrive(
                name: name,
                path: volume.path,
                size: totalGB,
                availableSpace: availableGB
            )
        } catch {
            return nil
        }
    }
    
    private func checkIsBootVolumeAsync(path: String) async -> Bool {
        do {
            let output = try await executeCommandWithPlist("/usr/sbin/diskutil", arguments: ["info", "-plist", path], timeout: timeoutShort)
            
            if let volumeInfo = output["VolumeInfo"] as? [String: Any],
               let bootable = volumeInfo["BootFromThisVolume"] as? Bool {
                return bootable
            }
            return false
        } catch {
            return false
        }
    }
    
    /// 检查是否为物理外部硬盘而不是网络驱动器或虚拟卷
    private func isPhysicalExternalDriveAsync(path: String) async -> Bool {
        do {
            logInfo("检查驱动器类型: \(path)")
            // 使用diskutil获取驱动器详细信息
            let output = try await executeCommandWithPlist("/usr/sbin/diskutil", arguments: ["info", "-plist", path], timeout: timeoutShort)
            
            // 检查设备类型
            if let deviceType = output["DeviceNode"] as? String {
                // 物理设备通常具有/dev/disk开头的设备节点
                let isPhysical = deviceType.hasPrefix("/dev/disk")
                
                // 进一步检查是否为外部物理设备
                if isPhysical, let deviceProtocol = output["Protocol"] as? String {
                    // 常见的外部物理设备协议
                    let externalProtocols = ["USB", "Thunderbolt", "SATA", "SAS", "FireWire", "External"]
                    let isExternal = externalProtocols.contains { deviceProtocol.contains($0) }
                    
                    if !isExternal {
                        // 检查是否标记为外部
                        if let isExternalMedia = output["RemovableMedia"] as? Bool, isExternalMedia {
                            return true
                        }
                        
                        if let isExternal = output["External"] as? Bool, isExternal {
                            return true
                        }
                    } else {
                        return true
                    }
                }
                
                // 排除常见的非物理驱动器类型
                if let volumeType = output["FilesystemType"] as? String {
                    let nonPhysicalTypes = ["autofs", "nfs", "cifs", "smbfs", "afpfs", "ftp", "apfs", "vmware", "synthetics"]
                    if nonPhysicalTypes.contains(where: { volumeType.lowercased().contains($0.lowercased()) }) {
                        logInfo("排除非物理驱动器: \(path) (类型: \(volumeType))")
                        return false
                    }
                }
                
                return isPhysical
            }
            
            return false
        } catch {
            logError("检查驱动器类型失败: \(path), 错误: \(error.localizedDescription)")
            return false
        }
    }
    
    func detectSwapLocationAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let output = try await executeCommandWithOutput("/usr/bin/ls", arguments: ["-la", swapFilePath], timeout: timeoutShort)
            
            await MainActor.run {
                // Look for symbolic links that point to external drives
                if output.contains("->") && output.contains("/Volumes/") {
                    currentSwapLocation = .external
                } else {
                    currentSwapLocation = .internalDrive
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = "检测交换文件位置失败: \(error.localizedDescription)"
                isLoading = false
            }
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
    
    // MARK: - Private Methods - Swap File Operations
    
    /// 使用管理员权限将交换文件移回内部驱动器
    private func moveToInternalDriveWithAdmin() async throws {
        if currentSwapLocation == .external {
            // 1. 检查当前的符号链接
            logInfo("检查当前交换文件符号链接...")
            let swapLinkInfo = try await executeCommandWithOutput("/usr/bin/ls", arguments: ["-la", swapFilePath], timeout: timeoutShort)
            
            // 2. 删除符号链接
            logInfo("删除当前的符号链接...")
            try await executeCommandWithAdmin("/bin/rm", arguments: [swapFilePath])
            
            // 3. 重新创建默认交换文件
            logInfo("在内部驱动器上重新创建交换文件...")
            try await executeCommandWithAdmin("/usr/sbin/dynamic_pager", arguments: ["-F", swapFilePath])
            logInfo("内部驱动器交换文件创建完成")
        } else {
            logInfo("交换文件已在内部驱动器上，无需移动")
        }
    }
    
    /// 使用管理员权限将交换文件移动到外部驱动器
    private func moveToExternalDriveWithAdmin(_ drive: ExternalDrive) async throws {
        let targetDirectory = "\(drive.path)/private/var/vm"
        let targetSwapFile = "\(targetDirectory)/swapfile"
        
        // 1. 在外部驱动器上创建目录结构
        logInfo("在外部驱动器上创建目录结构: \(targetDirectory)")
        try await executeCommandWithAdmin("/bin/mkdir", arguments: ["-p", targetDirectory])
        
        // 2. 检查外部驱动器上是否已有交换文件
        logInfo("检查外部驱动器上是否已有交换文件...")
        let externalSwapExists = (try? await executeCommandWithOutput("/usr/bin/test", arguments: ["-f", targetSwapFile], timeout: timeoutShort)) != nil
        
        if externalSwapExists {
            // 如果已存在，先删除
            logInfo("外部驱动器上已有交换文件，正在删除...")
            try await executeCommandWithAdmin("/bin/rm", arguments: [targetSwapFile])
        }
        
        // 3. 复制现有交换文件到外部驱动器
        logInfo("复制交换文件到外部驱动器: \(targetSwapFile)")
        try await executeCommandWithAdmin("/bin/cp", arguments: [swapFilePath, targetSwapFile])
        
        // 4. 设置适当的权限
        logInfo("设置交换文件权限...")
        try await executeCommandWithAdmin("/bin/chmod", arguments: ["644", targetSwapFile])
        
        // 5. 删除原始交换文件
        logInfo("删除内部驱动器上的原始交换文件...")
        try await executeCommandWithAdmin("/bin/rm", arguments: [swapFilePath])
        
        // 6. 创建符号链接
        logInfo("创建符号链接，将原路径指向外部交换文件...")
        try await executeCommandWithAdmin("/bin/ln", arguments: ["-s", targetSwapFile, swapFilePath])
        logInfo("符号链接创建完成")
    }
} 