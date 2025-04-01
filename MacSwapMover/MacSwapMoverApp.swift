//
//  MacSwapMoverApp.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

@main
struct MacSwapMoverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 720, height: 720)
                .onAppear {
                    setupAppearance()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacSwap Mover") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "MacSwap Mover",
                            NSApplication.AboutPanelOptionKey.applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "A beautiful utility to move your macOS swap file between internal and external drives.",
                                attributes: [
                                    .foregroundColor: NSColor.textColor,
                                    .font: NSFont.systemFont(ofSize: 12)
                                ]
                            )
                        ]
                    )
                }
            }
            
            CommandGroup(replacing: .help) {
                Button("MacSwap Mover Help") {
                    if let url = URL(string: "https://github.com/renjiawei/MacSwapMover") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
    
    private func setupAppearance() {
        // Setup window appearance
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Set window title style
        let windows = NSApplication.shared.windows
        for window in windows {
            // 设置标题栏透明
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor.windowBackgroundColor
            window.styleMask.insert(.fullSizeContentView)
            
            // 设置窗口大小精确匹配内容
            window.setContentSize(NSSize(width: 720, height: 720))
            
            // 移除边距，使内容填充窗口
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                // 设置内容视图填充整个窗口区域
                contentView.frame = NSRect(x: 0, y: 0, width: 720, height: 720)
            }
            
            // 移除标题栏分隔线
            if #available(macOS 11.0, *) {
                window.titlebarSeparatorStyle = .none
            }
        }
    }
}
