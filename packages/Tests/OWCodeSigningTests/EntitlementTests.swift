import Foundation
@testable import OWCodeSigning
import XCTest

final class EntitlementTests: XCTestCase {
    // MARK: - Entitlement.from(_:) — the bridging gotcha tests

    func testFromBridgedBoolBecomesBoolNotInteger() {
        // CFBoolean and NSNumber both bridge to Swift Bool via `as?`, so a
        // naive `if let b = value as? Bool` would collapse integer
        // entitlements into the .bool case. The CFGetTypeID check prevents
        // that. This test pins the behavior.
        let trueValue = kCFBooleanTrue as Any
        let falseValue = kCFBooleanFalse as Any
        XCTAssertEqual(Entitlement.from(trueValue), .bool(true))
        XCTAssertEqual(Entitlement.from(falseValue), .bool(false))
    }

    func testFromBridgedIntegerStaysInteger() {
        let value: Any = NSNumber(value: 42)
        XCTAssertEqual(Entitlement.from(value), .integer(42))
    }

    func testFromString() {
        XCTAssertEqual(Entitlement.from("hello" as Any), .string("hello"))
    }

    func testFromData() {
        let payload = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(Entitlement.from(payload as Any), .data(payload))
    }

    func testFromArray() {
        let array: [Any] = ["a", "b", "c"]
        XCTAssertEqual(
            Entitlement.from(array as Any),
            .array([.string("a"), .string("b"), .string("c")])
        )
    }

    func testFromNestedDictionary() {
        let dict: [String: Any] = ["enabled": true, "name": "test"]
        guard case .dictionary(let result) = Entitlement.from(dict as Any) else {
            return XCTFail("Expected .dictionary")
        }
        XCTAssertEqual(result["enabled"], .bool(true))
        XCTAssertEqual(result["name"], .string("test"))
    }

    func testFromMixedNestedShape() {
        // Mirror what app-group entitlements look like: array of strings.
        let value: Any = ["XSYZ3E4B7D.com.knollsoft.Rectangle"]
        XCTAssertEqual(
            Entitlement.from(value),
            .array([.string("XSYZ3E4B7D.com.knollsoft.Rectangle")])
        )
    }

    func testFromUnsupportedTypeReturnsNil() {
        XCTAssertNil(Entitlement.from(Date() as Any))
    }

    // MARK: - Convenience accessors

    func testBoolValueOnBoolCase() {
        XCTAssertEqual(Entitlement.bool(true).boolValue, true)
        XCTAssertEqual(Entitlement.bool(false).boolValue, false)
    }

    func testBoolValueOnNonBoolCaseReturnsNil() {
        XCTAssertNil(Entitlement.string("x").boolValue)
        XCTAssertNil(Entitlement.integer(1).boolValue)
    }

    func testStringValueOnStringCase() {
        XCTAssertEqual(Entitlement.string("x").stringValue, "x")
    }

    func testStringValueOnNonStringCaseReturnsNil() {
        XCTAssertNil(Entitlement.bool(true).stringValue)
    }
}
