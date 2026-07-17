import Foundation
import Darwin

/// 结束进程。用 SIGTERM(等价于 Cmd-Q 的礼貌退出,给 app 保存机会),
/// 不用 SIGKILL,避免丢失未保存内容。UI 侧应先弹确认。
enum ProcessKiller {
    /// 返回 true = 信号已送达。失败(进程已退出/权限不足杀系统进程)返回 false。
    @discardableResult
    static func terminate(pid: Int32, expectedName: String) -> Bool {
        guard pid > 0, !expectedName.isEmpty,
              ProcessReader.name(of: pid) == expectedName else { return false }
        return kill(pid, SIGTERM) == 0
    }
}
