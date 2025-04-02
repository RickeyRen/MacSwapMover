//
//  DriveSelectionView.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

struct DriveSelectionView: View {
    @ObservedObject var swapManager: SwapManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择驱动器")
                .font(.headline)
                .foregroundColor(.primary)
            
            if swapManager.availableDrives.isEmpty {
                Text("未检测到可用驱动器")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(swapManager.availableDrives) { drive in
                            DriveItemView(
                                drive: drive,
                                isSelected: swapManager.selectedDrive?.id == drive.id,
                                onSelect: {
                                    swapManager.selectedDrive = drive
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            Button(action: {
                swapManager.findAvailableDrives()
            }) {
                Label("刷新驱动器列表", systemImage: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .buttonStyle(.link)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct DriveItemView: View {
    let drive: DriveInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: drive.isSystemDrive ? "desktopcomputer" : "externaldrive.fill")
                    .font(.system(size: 24))
                    .foregroundColor(drive.containsSwapFile ? .green : .blue)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(drive.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if drive.containsSwapFile {
                            Text("当前位置")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                                .foregroundColor(.green)
                        }
                    }
                    
                    HStack {
                        Text("\(drive.availableSpace) 可用")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("/ \(drive.size) 总容量")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 18))
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    drive.containsSwapFile ? Color.green.opacity(0.5) :
                    isSelected ? Color.blue : Color.gray.opacity(0.3),
                    lineWidth: isSelected || drive.containsSwapFile ? 2 : 1
                )
        )
    }
}

#Preview {
    let swapManager = SwapManager()
    
    // Add mock data for preview
    swapManager.availableDrives = [
        DriveInfo(name: "External SSD", path: "/Volumes/External", size: "500 GB", availableSpace: "300 GB", isSystemDrive: false),
        DriveInfo(name: "Backup Drive", path: "/Volumes/Backup", size: "2 TB", availableSpace: "1.5 TB", isSystemDrive: false)
    ]
    
    DriveSelectionView(swapManager: swapManager)
        .frame(width: 400)
        .padding()
} 