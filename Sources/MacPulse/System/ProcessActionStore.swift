import Foundation
import Combine

@MainActor
final class ProcessActionStore: ObservableObject {
    @Published private(set) var pendingPID: Int32?
    @Published private(set) var message: String?

    func terminate(_ process: TopProcess, system: SystemMonitor) {
        guard pendingPID == nil else { return }
        pendingPID = process.pid
        message = "正在请求「\(process.name)」退出…"
        if let error = ProcessKiller.requestTermination(pid: process.pid, expectedName: process.name) {
            pendingPID = nil
            message = error
            system.refresh()
            return
        }
        Task {
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(500))
                // ps 在后台运行，不能让轮询阻塞主线程。
                let name = await Task.detached(priority: .utility) { ProcessReader.name(of: process.pid) }.value
                if name != process.name {
                    message = "「\(process.name)」已退出，内存数据正在刷新"
                    pendingPID = nil
                    system.refresh()
                    return
                }
            }
            message = "退出请求已送达，但「\(process.name)」仍在运行；请检查保存提示或在活动监视器查看"
            pendingPID = nil
            system.refresh()
        }
    }
}
