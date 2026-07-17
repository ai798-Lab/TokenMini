import Foundation

// 兼容旧入口,但不再复制生产守卫逻辑:直接运行 @testable import MacPulse 的真实回归用例。
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let task = Process()
task.currentDirectoryURL = repo
task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
task.arguments = ["swift", "test", "--filter", "CoreRegressionTests/testCleanup"]
task.standardOutput = FileHandle.standardOutput
task.standardError = FileHandle.standardError
do { try task.run(); task.waitUntilExit(); exit(task.terminationStatus) }
catch { fputs("无法启动生产清理测试: \(error)\n", stderr); exit(1) }
