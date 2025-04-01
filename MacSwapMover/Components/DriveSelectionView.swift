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
            Text("Select External Drive")
                .font(.headline)
                .foregroundColor(.primary)
            
            if swapManager.availableExternalDrives.isEmpty {
                Text("No external drives detected")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(swapManager.availableExternalDrives) { drive in
                            DriveItemView(
                                drive: drive,
                                isSelected: swapManager.selectedExternalDrive?.id == drive.id,
                                onSelect: {
                                    swapManager.selectedExternalDrive = drive
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            Button(action: {
                swapManager.findAvailableExternalDrives()
            }) {
                Label("Refresh Drives", systemImage: "arrow.clockwise")
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
    let drive: ExternalDrive
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("Size: \(drive.size)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("Available: \(drive.availableSpace)")
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
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
}

#Preview {
    let swapManager = SwapManager()
    
    // Add mock data for preview
    swapManager.availableExternalDrives = [
        ExternalDrive(name: "External SSD", path: "/Volumes/External", size: "500 GB", availableSpace: "300 GB"),
        ExternalDrive(name: "Backup Drive", path: "/Volumes/Backup", size: "2 TB", availableSpace: "1.5 TB")
    ]
    
    return DriveSelectionView(swapManager: swapManager)
        .frame(width: 400)
        .padding()
} 