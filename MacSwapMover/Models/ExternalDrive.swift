//
//  ExternalDrive.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import Foundation

struct ExternalDrive: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: String
    let availableSpace: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 