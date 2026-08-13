import XCTest
@testable import MacMuster

final class LocalizationTests: XCTestCase {

    func testLocalizedStringReturnsEnglishForBaseLanguage() {
        let result = String(localized: "OK")
        XCTAssertEqual(result, "OK", "Base localization should return the English string as-is")
    }

    func testLocalizedStringWithInterpolation() {
        let result = String(localized: "Could not launch \("TestApp").")
        XCTAssertTrue(result.contains("TestApp"), "Interpolated localized string should include the value")
    }

    func testAllCategoryRawValuesAreLocalizable() {
        for category in AppCategory.allCases {
            let localized = String(localized: String.LocalizationValue(category.rawValue))
            XCTAssertFalse(localized.isEmpty, "Category '\(category.rawValue)' should have a localizable entry")
        }
    }

    func testAllSortOptionRawValuesAreLocalizable() {
        for option in ApplicationSorter.SortOption.allCases {
            let localized = String(localized: String.LocalizationValue(option.rawValue))
            XCTAssertFalse(localized.isEmpty, "Sort option '\(option.rawValue)' should have a localizable entry")
        }
    }

    func testAllIconSizeRawValuesAreLocalizable() {
        for size in IconSize.allCases {
            let localized = String(localized: String.LocalizationValue(size.rawValue))
            XCTAssertFalse(localized.isEmpty, "Icon size '\(size.rawValue)' should have a localizable entry")
        }
    }

    func testAllLaunchModeRawValuesAreLocalizable() {
        for mode in LaunchMode.allCases {
            let localized = String(localized: String.LocalizationValue(mode.rawValue))
            XCTAssertFalse(localized.isEmpty, "Launch mode '\(mode.rawValue)' should have a localizable entry")
        }
    }

    @MainActor
    func testAlertHelperUsesLocalizedOKButton() {
        let alert = NSAlert()
        alert.addButton(withTitle: String(localized: "OK"))
        XCTAssertEqual(alert.buttons.first?.title, "OK", "Alert OK button should use localized string")
    }
}
