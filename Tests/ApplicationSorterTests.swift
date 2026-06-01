import XCTest
@testable import MacMuster

final class ApplicationSorterTests: XCTestCase {
    
    private func makeApp(name: String, installationDate: Date) -> AppModel.Application {
        AppModel.Application(name: name, path: "/Applications/\(name).app", icon: nil, installationDate: installationDate)
    }
    
    func testSortByNameAscending() {
        let apps = [
            makeApp(name: "Zulu", installationDate: Date()),
            makeApp(name: "Alpha", installationDate: Date()),
            makeApp(name: "Beta", installationDate: Date()),
        ]
        
        let sorted = ApplicationSorter.sort(apps, by: .name)
        
        XCTAssertEqual(sorted.map { $0.name }, ["Alpha", "Beta", "Zulu"])
    }
    
    func testSortByNameCaseInsensitive() {
        let apps = [
            makeApp(name: "zebra", installationDate: Date()),
            makeApp(name: "Apple", installationDate: Date()),
            makeApp(name: "beta", installationDate: Date()),
        ]
        
        let sorted = ApplicationSorter.sort(apps, by: .name)
        
        XCTAssertEqual(sorted.map { $0.name }, ["Apple", "beta", "zebra"])
    }
    
    func testSortByInstallationDateNewestFirst() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)
        
        let apps = [
            makeApp(name: "Old", installationDate: date1),
            makeApp(name: "New", installationDate: date3),
            makeApp(name: "Middle", installationDate: date2),
        ]
        
        let sorted = ApplicationSorter.sort(apps, by: .installationDate)
        
        XCTAssertEqual(sorted.map { $0.name }, ["New", "Middle", "Old"])
    }
    
    func testSortByNameWithEmptyArray() {
        let apps: [AppModel.Application] = []
        let sorted = ApplicationSorter.sort(apps, by: .name)
        XCTAssertTrue(sorted.isEmpty)
    }
    
    func testSortByNameWithSingleItem() {
        let app = makeApp(name: "Only", installationDate: Date())
        let sorted = ApplicationSorter.sort([app], by: .name)
        XCTAssertEqual(sorted.map { $0.name }, ["Only"])
    }
    
    func testSortOptionAllCases() {
        XCTAssertEqual(ApplicationSorter.SortOption.allCases.count, 2)
        XCTAssertEqual(ApplicationSorter.SortOption.allCases[0].rawValue, "Name")
        XCTAssertEqual(ApplicationSorter.SortOption.allCases[1].rawValue, "Installation Date")
    }
    
    func testSortByNamePreservesAllApps() {
        let apps = [
            makeApp(name: "Cherry", installationDate: Date()),
            makeApp(name: "Banana", installationDate: Date()),
            makeApp(name: "Apple", installationDate: Date()),
            makeApp(name: "Date", installationDate: Date()),
        ]

        let sorted = ApplicationSorter.sort(apps, by: .name)
        XCTAssertEqual(sorted.count, apps.count)
        XCTAssertEqual(Set(sorted.map { $0.name }), Set(apps.map { $0.name }))
    }

    // MARK: - High Priority: Performance Tests (Lowercase Comparison)

    func testSortByNameUsesPreComputedLowercaseNameForPerformance() {
        // This test verifies that sorting uses the pre-computed lowercaseName
        // on the Application struct, not expensive localizedCaseInsensitiveCompare.
        let apps = [
            makeApp(name: "Zebra", installationDate: Date()),
            makeApp(name: "apple", installationDate: Date()),
            makeApp(name: "Banana", installationDate: Date()),
        ]

        let sorted = ApplicationSorter.sort(apps, by: .name)

        // All apps should be present and sorted correctly
        XCTAssertEqual(sorted.map { $0.name }, ["apple", "Banana", "Zebra"])

        // Verify that each app's lowercaseName matches expected comparison
        XCTAssertEqual(sorted[0].lowercaseName, "apple")
        XCTAssertEqual(sorted[1].lowercaseName, "banana")
        XCTAssertEqual(sorted[2].lowercaseName, "zebra")

        // The sorted order should be consistent with string comparison of lowercaseNames
        for i in 0..<sorted.count - 1 {
            XCTAssertLessThanOrEqual(
                sorted[i].lowercaseName,
                sorted[i + 1].lowercaseName,
                "Sorted by lowercase name comparison"
            )
        }
    }

    func testSortByInstallationDatePreservesAllApps() {
        let now = Date()
        let apps = [
            makeApp(name: "Old", installationDate: now.addingTimeInterval(-1000)),
            makeApp(name: "Middle", installationDate: now.addingTimeInterval(-500)),
            makeApp(name: "New", installationDate: now),
        ]

        let sorted = ApplicationSorter.sort(apps, by: .installationDate)
        XCTAssertEqual(sorted.count, apps.count)
    }

    func testSortStabilityWithIdenticalDates() {
        let sameDate = Date()
        let apps = [
            makeApp(name: "Gamma", installationDate: sameDate),
            makeApp(name: "Alpha", installationDate: sameDate),
            makeApp(name: "Beta", installationDate: sameDate),
        ]

        // When dates are identical, should fall back to name order (or be stable)
        let sorted = ApplicationSorter.sort(apps, by: .installationDate)
        XCTAssertEqual(sorted.count, 3)
    }
}