//
//  MacSwapMoverApp.swift
//  MacSwapMover
//
//  Created by RENJIAWEI on 2025/4/2.
//

import SwiftUI

@main
struct MacSwapMoverApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 680, minHeight: 620, maxHeight: .infinity)
                // 使用固定最小尺寸，但允许自动调整大小
                .background(SizeReporterView())
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
}

struct SizeReporterView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SizeReporterNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 内容更新时调整窗口大小
        guard let window = nsView.window else { return }
        DispatchQueue.main.async {
            window.autorecalculatesKeyViewLoop = true
            
            // 让窗口重新计算其内容大小
            let contentSize = window.contentView?.fittingSize ?? NSSize(width: 720, height: 720)
            let newSize = NSSize(
                width: max(contentSize.width, 720),
                height: max(contentSize.height, 620)
            )
            
            // 不再强制限制最大高度，而是让窗口自由调整
            window.setContentSize(newSize)
        }
    }
    
    class SizeReporterNSView: NSView {
        override func layout() {
            super.layout()
            // 每次布局更新时通知窗口可能需要调整大小
            guard let window = self.window else { return }
            
            NotificationCenter.default.post(
                name: NSView.frameDidChangeNotification,
                object: window.contentView
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppearance()
    }
    
    func setupAppearance() {
        // 配置基本窗口尺寸和外观
        if let window = NSApplication.shared.windows.first {
            // 设置窗口最小尺寸，保证UI不会被压缩得太小
            window.minSize = NSSize(width: 720, height: 620)
            
            // 配置窗口样式
            window.isOpaque = false
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
            window.hasShadow = true
            
            // 启用尺寸自动调整（关键设置）
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: 720, height: 620)
            
            // 启用自由调整大小以适应用户操作和内容
            let initialHeight: CGFloat = 750 // 设置初始高度
            window.setContentSize(NSSize(width: 720, height: initialHeight))
            
            // 重要：移除固定宽高比限制，允许自由调整
            window.contentAspectRatio = NSSize(width: 0, height: 0)
            
            // 设置窗口显示在屏幕中央
            window.center()
            
            // 为内容视图添加自动布局约束
            if let contentView = window.contentView {
                contentView.translatesAutoresizingMaskIntoConstraints = false
            }
            
            // 延迟一小段时间后再次调整大小，确保所有内容都已加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let contentSize = window.contentView?.fittingSize {
                    let newSize = NSSize(
                        width: contentSize.width,
                        height: max(contentSize.height, 620)
                    )
                    window.setContentSize(newSize)
                }
            }
        }
    }
}
