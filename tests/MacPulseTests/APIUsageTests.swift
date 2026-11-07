import XCTest
@testable import MacPulse

final class APIUsageTests: XCTestCase {
    func testAutomaticIngestionDeduplicatesAndPersistsAfterRotation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = APIUsageScanner.directory(home: home)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("requests.jsonl")
        let date = ISO8601DateFormatter().string(from: Date())
        let row = "{\"timestamp\":\"\(date)\",\"model\":\"deepseek-flash\",\"id\":\"request-1\",\"input\":60,\"cacheRead\":40,\"output\":20}\n"
        try Data((row + row).utf8).write(to: path)
        let scanner = APIUsageScanner()
        XCTAssertEqual(try scanner.scan(home: home), 0)
        XCTAssertEqual(try UsageImport.load(home: home).count, 1)
        XCTAssertEqual(try UsageImport.load(home: home).first?.tool, .deepseekAPI)
        try FileManager.default.removeItem(at: path)
        XCTAssertEqual(try APIUsageScanner().scan(home: home), 0)
        XCTAssertEqual(try UsageImport.load(home: home).count, 1)
    }
    func testIncompleteAppendDoesNotRemovePreviouslyIngestedUsage() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = APIUsageScanner.directory(home: home)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: Date())
        let row = "{\"timestamp\":\"\(date)\",\"model\":\"deepseek-flash\",\"id\":\"request-1\",\"input\":1,\"output\":1}\n{"
        try Data(row.utf8).write(to: root.appendingPathComponent("requests.jsonl"))
        XCTAssertEqual(try APIUsageScanner().scan(home: home), 1)
        XCTAssertEqual(try UsageImport.load(home: home).count, 1)
    }
}
