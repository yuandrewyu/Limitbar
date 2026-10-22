import Foundation
import LimitbarCore

// Invoked by Claude Code's statusLine command. Store only quota fields, never the raw input.
do {
    var input = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 64 * 1024), !chunk.isEmpty {
        input.append(chunk)
        guard input.count <= 1024 * 1024 else {
            throw CocoaError(.fileReadTooLarge)
        }
    }
    let snapshot = try UsageDecoders.claudeStatusLine(input)
    try FileManager.default.createDirectory(at: LimitbarPaths.directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: LimitbarPaths.claudeSnapshot, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                        ofItemAtPath: LimitbarPaths.claudeSnapshot.path)
    let values = snapshot.windows.compactMap { window -> String? in
        guard let percent = window.usedPercent else { return nil }
        return "\(window.name): \(Int(min(percent, 100).rounded()))% used"
    }
    print(values.isEmpty ? "Claude · usage unavailable" : "Claude · " + values.joined(separator: " · "))
} catch {
    // Keep terminal output short and avoid logging the input, which may include private paths.
    print("Limitbar · usage unavailable")
    exit(1)
}
