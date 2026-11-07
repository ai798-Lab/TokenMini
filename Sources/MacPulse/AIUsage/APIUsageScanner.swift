import Foundation

/// Local project/agent metering bridge. Only normalized token fields enter the ledger.
/// Each producer appends JSONL records with a stable request id; imports share the same dedup key.
final class APIUsageScanner {
    private var fingerprints: [String: String] = [:]
    static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/TokenMini/api-usage/deepseek")
    }

    func scan(home: URL) throws -> Int {
        let root = Self.directory(home: home)
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        var errors = 0
        for file in files where file.pathExtension == "jsonl" {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let fingerprint = "\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            guard fingerprints[file.path] != fingerprint else { continue }
            var rows: [UsageRecord] = []
            var complete = true
            do {
                try UsageLogReader.forEachLine(at: file) { line in
                    do { rows += try UsageImport.parse(line, format: "jsonl", tool: .deepseekAPI) }
                    catch { complete = false; errors += 1 }
                }
                if !rows.isEmpty { _ = try UsageImport.save(rows, home: home) }
                if complete { fingerprints[file.path] = fingerprint }
            } catch { errors += 1 }
        }
        return errors
    }
}
