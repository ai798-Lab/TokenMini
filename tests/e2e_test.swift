import Foundation

// 兼容旧入口:假 home、真实扫描/删除、符号链接目标保护均由生产代码回归用例覆盖。
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let task = Process()
task.currentDirectoryURL = repo
task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
task.arguments = ["swift", "test", "--filter",
                  "CoreRegressionTests/testCleanupDeletesCandidateSymlinkWithoutTouchingTarget"]
task.standardOutput = FileHandle.standardOutput
task.standardError = FileHandle.standardError
do { try task.run(); task.waitUntilExit(); exit(task.terminationStatus) }
catch { fputs("无法启动生产清理端到端测试: \(error)\n", stderr); exit(1) }
