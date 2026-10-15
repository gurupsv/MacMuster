import Foundation

/// Reads a file the user opened without trusting its size (SEC-7).
///
/// Reads at most `maxBytes + 1` bytes through a `FileHandle` and then checks the length, rather than
/// asking for the file's size first: a stat-then-read check measures a symlink, not its target, and
/// leaves a gap between the check and the read. Same pattern as `BundleInfoReader`. Returns nil for
/// an unreadable, empty or oversized file.
enum BoundedFileReader {
    nonisolated static func read(_ url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1),
              !data.isEmpty, data.count <= maxBytes else { return nil }
        return data
    }
}
