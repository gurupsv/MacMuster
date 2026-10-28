import CoreTransferable
import Foundation

/// What a grid cell puts on the drag pasteboard.
///
/// The path string is what the grid's own `.dropDestination(for: String.self)` reads for reorder and
/// folder merges, so it must stay. The file URL is what lets the Dock (and Finder) accept the same
/// drag and pin the app. Folder tiles carry a UUID rather than a path, so they offer the string only;
/// a file URL for them would point at nothing.
struct AppDragItem: Transferable {
    let path: String
    let isFolder: Bool

    /// True when `path` can be handed to the Dock: a real `.app` bundle, not a folder tile.
    nonisolated var offersFileURL: Bool {
        !isFolder && path.hasSuffix(".app")
    }

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (item: AppDragItem) in item.path })
        ProxyRepresentation(exporting: { (item: AppDragItem) in item.fileURL })
            .exportingCondition { $0.offersFileURL }
    }
}
