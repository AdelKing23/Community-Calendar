import XCTest
@testable import Pohutukawa_Coast_Calendar

/// t224: the welcome shows once per account and fails open.
final class WelcomeGateTests: XCTestCase {
    func testExistingAccountWithNoServerRowSeesWelcome() {
        XCTAssertTrue(WelcomeGate.shouldShow(signedIn: true, server: .notDismissed, dismissedOnThisDevice: false, signedOutDismissed: true))
    }

    func testServerErrorFailsOpen() {
        // Build 9 bug: an expired restored token gave 401 and the welcome was silently skipped.
        XCTAssertTrue(WelcomeGate.shouldShow(signedIn: true, server: .failed, dismissedOnThisDevice: false, signedOutDismissed: false))
    }

    func testServerErrorAfterDismissOnThisDeviceStaysHidden() {
        XCTAssertFalse(WelcomeGate.shouldShow(signedIn: true, server: .failed, dismissedOnThisDevice: true, signedOutDismissed: false))
    }

    func testServerRowHidesWelcome() {
        XCTAssertFalse(WelcomeGate.shouldShow(signedIn: true, server: .dismissed, dismissedOnThisDevice: false, signedOutDismissed: false))
    }

    func testSignedOutUsesDeviceFlag() {
        XCTAssertTrue(WelcomeGate.shouldShow(signedIn: false, server: .failed, dismissedOnThisDevice: false, signedOutDismissed: false))
        XCTAssertFalse(WelcomeGate.shouldShow(signedIn: false, server: .failed, dismissedOnThisDevice: false, signedOutDismissed: true))
    }

    func testAccountListIsPerAccount() {
        let a = UUID(), b = UUID()
        let raw = WelcomeGate.adding(a, to: "")
        XCTAssertTrue(WelcomeGate.accounts(from: raw).contains(a.uuidString.lowercased()))
        XCTAssertFalse(WelcomeGate.accounts(from: raw).contains(b.uuidString.lowercased()))
        XCTAssertEqual(WelcomeGate.accounts(from: WelcomeGate.adding(a, to: raw)).count, 1)
    }
}
