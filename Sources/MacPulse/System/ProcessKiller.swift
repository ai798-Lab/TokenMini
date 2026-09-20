import Foundation
import AppKit
import Darwin

/// 普通应用走系统的正常退出请求；后台进程发送 SIGTERM。请求送达不等于已经退出。
enum ProcessKiller {
    static func isProtected(pid: Int32, name: String) -> Bool {
        pid <= 1 || pid == getpid() ||
        ["kernel_task", "launchd", "WindowServer", "loginwindow", "SystemUIServer", "Dock", "Finder"].contains(name)
    }

    @MainActor
    static func requestTermination(pid: Int32, expectedName: String) -> String? {
        guard !isProtected(pid: pid, name: expectedName) else { return "系统关键进程或 TokenMini 自身不能在这里结束" }
        guard !expectedName.isEmpty, ProcessReader.name(of: pid) == expectedName else {
            return "进程已退出或身份发生变化，请刷新列表"
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            return app.terminate() ? nil : "应用拒绝了退出请求，请切换到应用检查保存对话框"
        }
        guard kill(pid, SIGTERM) == 0 else {
            return errno == EPERM ? "没有权限结束此进程" : "退出请求失败：\(String(cString: strerror(errno)))"
        }
        return nil
    }
}
