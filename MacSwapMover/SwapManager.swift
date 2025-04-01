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
    
    // MARK: - Private Properties
    
    private let swapFilePath = "/private/var/vm/swapfile"
    private let timeoutShort: UInt64 = 3_000_000_000 // 3 seconds
    private let timeoutMedium: UInt64 = 5_000_000_000 // 5 seconds
    private let timeoutLong: UInt64 = 15_000_000_000 // 15 seconds
    
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
        guard isSIPDisabled else {
            return .failure(.sipEnabled)
        }
        
        if destination == .external && selectedExternalDrive == nil {
            return .failure(.externalDriveNotFound)
        }
        
        // 更新UI状态
        await MainActor.run {
            isLoading = true
        }
        
        // 1. 首先尝试获取管理员权限
        do {
            let hasAdminPrivileges = try await checkAdminPrivileges()
            if !hasAdminPrivileges {
                // 如果没有管理员权限，尝试获取
                let gotPrivileges = try await requestAdminPrivileges()
                if !gotPrivileges {
                    await MainActor.run { isLoading = false }
                    return .failure(.insufficientPermissions)
                }
            }
        } catch {
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("获取管理员权限失败: \(error.localizedDescription)"))
        }
        
        // 2. 停用交换文件
        do {
            print("正在停用交换文件...")
            // 先检查当前的交换文件状态
            let swapStatus = try await executeCommandWithOutput("/usr/sbin/sysctl", arguments: ["vm.swap_enabled"], timeout: timeoutShort)
            let isSwapEnabled = swapStatus.contains("vm.swap_enabled: 1")
            
            if isSwapEnabled {
                // 使用sudo获取权限停用交换文件
                try await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=0"])
            }
        } catch {
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("停用交换文件失败: \(error.localizedDescription)"))
        }
        
        // 3. 移动或创建交换文件
        do {
            if destination == .internalDrive {
                print("正在移动交换文件到内部驱动器...")
                try await moveToInternalDriveWithAdmin()
            } else {
                guard let externalDrive = selectedExternalDrive else {
                    await MainActor.run { isLoading = false }
                    return .failure(.externalDriveNotFound)
                }
                
                print("正在移动交换文件到外部驱动器: \(externalDrive.name)...")
                try await moveToExternalDriveWithAdmin(externalDrive)
            }
        } catch {
            // 出错时尝试重新启用交换文件
            print("移动交换文件失败，正在恢复交换文件...")
            try? await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=1"])
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("移动交换文件失败: \(error.localizedDescription)"))
        }
        
        // 4. 重新启用交换文件
        do {
            print("正在重新启用交换文件...")
            try await executeCommandWithAdmin("/usr/sbin/sysctl", arguments: ["-w", "vm.swap_enabled=1"])
        } catch {
            await MainActor.run { isLoading = false }
            return .failure(.commandExecutionFailed("重新启用交换文件失败: \(error.localizedDescription)"))
        }
        
        // 5. 更新当前位置状态
        await MainActor.run {
            currentSwapLocation = destination
            isLoading = false
        }
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
                    // Only add if it's not the boot volume
                    let isBootVolume = await checkIsBootVolumeAsync(path: volume.path)
                    if !isBootVolume {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Add timeout handling
        try await withTaskTimeoutHandling(process: process, timeout: timeoutLong)
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SwapOperationError.commandExecutionFailed(errorOutput)
        }
    }
    
    private func executeCommandWithOutput(_ command: String, arguments: [String], timeout: UInt64) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        
        try await withTaskTimeoutHandling(process: process, timeout: timeout)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func executeCommandWithPlist(_ command: String, arguments: [String], timeout: UInt64) async throws -> [String: Any] {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        
        try await withTaskTimeoutHandling(process: process, timeout: timeout)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        
        do {
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist
            }
            return [:]
        } catch {
            return [:]
        }
    }
    
    private func withTaskTimeoutHandling(process: Process, timeout: UInt64) async throws {
        let executeTask = Task {
            do {
                try process.run()
                process.waitUntilExit()
                return true
            } catch {
                return false
            }
        }
        
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout)
                if process.isRunning {
                    process.terminate()
                    return false
                }
                return true
            } catch {
                return false
            }
        }
        
        let success = try await timeoutTask.value
        let executionSucceeded = try await executeTask.value
        
        if !success || !executionSucceeded {
            throw SwapOperationError.commandExecutionFailed("Command timed out or failed to execute")
        }
    }
    
    // MARK: - Private Methods - Admin Privileges
    
    /// 检查当前是否有管理员权限
    private func checkAdminPrivileges() async throws -> Bool {
        do {
            // 尝试访问一个需要管理员权限的命令
            let output = try await executeCommandWithOutput("/usr/bin/sudo", arguments: ["-n", "true"], timeout: timeoutShort)
            return true
        } catch {
            // 如果命令失败，说明没有管理员权限
            return false
        }
    }
    
    /// 请求管理员权限
    private func requestAdminPrivileges() async throws -> Bool {
        do {
            // 使用AppleScript显示管理员权限请求对话框
            let script = """
            do shell script "echo 'Admin privileges granted'" with administrator privileges
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            try process.run()
            process.waitUntilExit()
            
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// 使用管理员权限执行命令
    private func executeCommandWithAdmin(_ command: String, arguments: [String]) async throws {
        let fullCommand = ([command] + arguments).joined(separator: " ")
        let sudoCommand = "do shell script \"\(fullCommand)\" with administrator privileges"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", sudoCommand]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "未知错误"
            throw SwapOperationError.commandExecutionFailed(errorOutput)
        }
    }
    
    // MARK: - Private Methods - Swap File Operations
    
    /// 使用管理员权限将交换文件移回内部驱动器
    private func moveToInternalDriveWithAdmin() async throws {
        if currentSwapLocation == .external {
            // 1. 检查当前的符号链接
            let swapLinkInfo = try await executeCommandWithOutput("/usr/bin/ls", arguments: ["-la", swapFilePath], timeout: timeoutShort)
            
            // 2. 删除符号链接
            try await executeCommandWithAdmin("/bin/rm", arguments: [swapFilePath])
            
            // 3. 重新创建默认交换文件
            try await executeCommandWithAdmin("/usr/sbin/dynamic_pager", arguments: ["-F", swapFilePath])
        }
    }
    
    /// 使用管理员权限将交换文件移动到外部驱动器
    private func moveToExternalDriveWithAdmin(_ drive: ExternalDrive) async throws {
        let targetDirectory = "\(drive.path)/private/var/vm"
        let targetSwapFile = "\(targetDirectory)/swapfile"
        
        // 1. 在外部驱动器上创建目录结构
        try await executeCommandWithAdmin("/bin/mkdir", arguments: ["-p", targetDirectory])
        
        // 2. 检查外部驱动器上是否已有交换文件
        let externalSwapExists = (try? await executeCommandWithOutput("/usr/bin/test", arguments: ["-f", targetSwapFile], timeout: timeoutShort)) != nil
        
        if externalSwapExists {
            // 如果已存在，先删除
            try await executeCommandWithAdmin("/bin/rm", arguments: [targetSwapFile])
        }
        
        // 3. 复制现有交换文件到外部驱动器
        try await executeCommandWithAdmin("/bin/cp", arguments: [swapFilePath, targetSwapFile])
        
        // 4. 设置适当的权限
        try await executeCommandWithAdmin("/bin/chmod", arguments: ["644", targetSwapFile])
        
        // 5. 删除原始交换文件
        try await executeCommandWithAdmin("/bin/rm", arguments: [swapFilePath])
        
        // 6. 创建符号链接
        try await executeCommandWithAdmin("/bin/ln", arguments: ["-s", targetSwapFile, swapFilePath])
    }
} 