import XCTest
@testable import MacPulse

final class MaintenanceTests: XCTestCase {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-maintenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func file(_ home: URL, _ relative: String, data: Data = Data()) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testMissingRootsAreEmptyAndUnreadableRootIsReported() throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let scanner = CleanupScanner(homeDirectory: h.path)
        XCTAssertTrue(scanner.scan().allSatisfy { $0.items.isEmpty && $0.issues.isEmpty })
        let locked = try file(h, "Library/Caches/locked/keep", data: Data("keep".utf8)).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let result = try XCTUnwrap(scanner.scan().first { $0.category == .appCaches })
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.sizeLabel, "未能读取")
        XCTAssertTrue(result.issues.contains { $0.permissionDenied })
    }

    func testSymlinkedAncestorIsNeverScanned() throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let outside = try file(h, "outside/Caches/keep").deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: h.appendingPathComponent("Library"), withDestinationURL: outside)
        let result = try XCTUnwrap(CleanupScanner(homeDirectory: h.path).scan().first { $0.category == .appCaches })
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertFalse(result.issues.isEmpty)
    }

    func testSelectedFilesOnlyAndZeroByteFileCanBeRemoved() throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let selected = try file(h, ".Trash/empty")
        let retained = try file(h, ".Trash/retain")
        let scanner = CleanupScanner(homeDirectory: h.path)
        let report = scanner.clean(categories: [.trash], scan: scanner.scan(), selectedPaths: [selected.path])
        XCTAssertEqual(report.deletedCount, 1, "home=\(h.path), issues=\(report.issues)")
        XCTAssertEqual(report.freedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.path))
    }

    func testChangedAndMissingFilesHaveDistinctResults() throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let changed = try file(h, "Library/Logs/changed", data: Data("old".utf8))
        let missing = try file(h, "Library/Logs/missing")
        let scanner = CleanupScanner(homeDirectory: h.path)
        let scan = scanner.scan()
        try Data("new contents".utf8).write(to: changed, options: .atomic)
        try FileManager.default.removeItem(at: missing)
        let report = scanner.clean(categories: [.userLogs], scan: scan)
        XCTAssertEqual(report.deletedCount, 0)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.missingCount, 1)
        XCTAssertEqual(try String(contentsOf: changed), "new contents")
    }

    func testCleanupFailurePreservesRealReason() throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let candidate = try file(h, "Library/Logs/keep")
        let root = candidate.deletingLastPathComponent()
        let scanner = CleanupScanner(homeDirectory: h.path)
        let scan = scanner.scan()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        let report = scanner.clean(categories: [.userLogs], scan: scan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertTrue(report.issues.contains { $0.permissionDenied }, "\(report.issues)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path))
    }

    @MainActor
    func testConfirmationSnapshotRescanAndCancellation() async throws {
        let h = try home(); defer { try? FileManager.default.removeItem(at: h) }
        let deleted = try file(h, "Library/Logs/empty")
        let keep = try file(h, "Library/Logs/keep")
        let store = CleanupStore(scanner: CleanupScanner(homeDirectory: h.path))
        store.scan()
        try await waitUntil { !store.scanning }
        store.selected = []
        let item = try XCTUnwrap(store.results.first { $0.category == .userLogs }?.items.first { $0.path == deleted.path })
        store.setItemSelected(item, category: .userLogs, selected: true)
        XCTAssertEqual(store.selectedItems.count, 1)
        XCTAssertTrue(store.excludedPaths.contains(keep.path))
        XCTAssertEqual(store.selectedBytes, 0)
        XCTAssertTrue(store.canClean)
        store.prepareCleanup()
        store.cancelCleanup()
        XCTAssertTrue(FileManager.default.fileExists(atPath: deleted.path))
        store.prepareCleanup()
        store.selected = [] // 确认快照不能被后来的 UI 状态改变。
        store.confirmCleanup()
        try await waitUntil { !store.cleaning && !store.scanning }
        XCTAssertEqual(store.lastReport?.deletedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertEqual(store.results.first { $0.category == .userLogs }?.items.count, 1)
        store.scan()
        store.cancelScan()
        try await waitUntil { !store.scanning }
        XCTAssertTrue(store.scanStatus.contains("取消"))
    }

    func testGitHubBranchIsRetained() throws {
        let spec = try XCTUnwrap(SkillManagerStore.parseRepoSpec("https://github.com/owner/repo/tree/release/skills/demo"))
        XCTAssertEqual(spec.branch, "release")
        XCTAssertEqual(spec.subpath, "skills/demo")
        XCTAssertNil(SkillManagerStore.parseRepoSpec("owner/repo")?.branch)
        XCTAssertNil(SkillManagerStore.parseRepoSpec("owner/repo/tree/--upload-pack=bad/skill"))
    }

    @MainActor
    func testExitRequestIsVerifiedUsingDisposableProcess() async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["30"]
        try task.run()
        defer { if task.isRunning { task.terminate() } }
        let pid = task.processIdentifier
        let name = try XCTUnwrap(ProcessReader.name(of: pid))
        XCTAssertNotNil(ProcessKiller.requestTermination(pid: pid, expectedName: "wrong-identity"))
        XCTAssertTrue(task.isRunning)
        XCTAssertNotNil(ProcessKiller.requestTermination(pid: getpid(), expectedName: "self"))
        let actions = ProcessActionStore()
        let system = SystemMonitor()
        actions.terminate(TopProcess(pid: pid, name: name, cpuPercent: 0, memoryBytes: 0), system: system)
        try await waitUntil { actions.pendingPID == nil }
        XCTAssertTrue(actions.message?.contains("已退出") == true)
        XCTAssertFalse(task.isRunning)
    }

    func testLiveSystemAndCleanupReadOnly() throws {
        guard ProcessInfo.processInfo.environment["MACPULSE_LIVE_TEST"] == "1" else {
            throw XCTSkip("本机只读采样需显式启用 MACPULSE_LIVE_TEST=1")
        }
        var cpu = CPUReader()
        _ = cpu.read()
        let memory = MemoryReader().read()
        let space = DiskSpaceReader().read()
        let processes = ProcessReader.topProcesses(limit: 6, sortBy: .memory)
        let battery = BatteryReader().read()
        let sensors = SensorsReader().read()
        XCTAssertGreaterThan(memory.total, 0)
        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertGreaterThan(space.total, space.free)
        XCTAssertFalse(processes.isEmpty)
        let mismatch = processes.filter {
            guard let current = ProcessReader.name(of: $0.pid) else { return false } // 短命进程可能已经自然退出。
            return current != $0.name
        }
        XCTAssertTrue(mismatch.isEmpty, "进程列表名称与退出校验不一致：\(mismatch.map(\.name))")
        let started = Date()
        let scan = CleanupScanner().scan()
        XCTAssertEqual(scan.count, CleanupCategory.allCases.count)
        print("LIVE SYSTEM memory=\(memory.used)/\(memory.total), diskFree=\(space.free), processes=\(processes.count), battery=\(battery.present), cpuTemp=\(sensors.cpuTemp != nil), fans=\(sensors.fans.count)")
        for result in scan {
            print("LIVE CLEANUP \(result.category.rawValue) items=\(result.items.count) bytes=\(result.totalBytes) errors=\(result.issues.count) permissions=\(result.issues.filter(\.permissionDenied).count)")
        }
        print("LIVE CLEANUP seconds=\(Date().timeIntervalSince(started)) [read only; no files deleted]")
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "后台操作未在超时前完成")
    }
}
