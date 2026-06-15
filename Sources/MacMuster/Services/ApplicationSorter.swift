import Foundation

// MARK: - Constants
// kSortBatchSize removed (Code Review Fix 3): unused constant

class ApplicationSorter {
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case installationDate = "Installation Date"
    }
    
    static func sort(_ applications: [AppModel.Application], by option: SortOption) -> [AppModel.Application] {
        switch option {
        case .name:
            // Use pre-computed lowercase names for efficient sorting
            return applications.sorted { $0.lowercaseName < $1.lowercaseName }
        case .installationDate:
            return applications.sorted { $0.installationDate > $1.installationDate }
        }
    }
}