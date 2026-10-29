import XCTest
@testable import AirCard_iOS

@MainActor
final class WebClipReportRefreshTests: XCTestCase {
    func testNewCompletionReplacesPersistedAndPresentedReportEvenForSameVerdict() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "webclip.directoryReport")
        defer { defaults.set(old, forKey: "webclip.directoryReport") }
        defaults.set("old-v2-report", forKey: "webclip.directoryReport")
        let model = WebClipViewModel()
        XCTAssertEqual(model.directoryReport, "old-v2-report")
        let start = Date(timeIntervalSince1970: 1_000)
        model.completeDirectoryReport("payload-relocation-unconfirmed", startedAt: start, completedAt: start.addingTimeInterval(10))
        let first = try XCTUnwrap(model.directoryReportPresentation)
        model.completeDirectoryReport("payload-relocation-unconfirmed", startedAt: start.addingTimeInterval(30), completedAt: start.addingTimeInterval(40))
        let second = try XCTUnwrap(model.directoryReportPresentation)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.report, second.report)
        XCTAssertEqual(model.directoryReport, second.report)
        XCTAssertEqual(defaults.string(forKey: "webclip.directoryReport"), second.report)
        XCTAssertFalse(second.report.contains("old-v2-report"))
        XCTAssertEqual(WebClipViewModel().directoryReport, second.report)
    }
}
