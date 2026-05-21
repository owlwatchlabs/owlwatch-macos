import Foundation
@testable import OWBinary
import XCTest

final class OWBinaryTests: XCTestCase {
    // MARK: - Smoke tests against real system binaries

    func testParseBinLsReturnsAtLeastOneSlice() throws {
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertFalse(binary.slices.isEmpty, "/bin/ls should produce at least one Mach-O slice")
        XCTAssertTrue(binary.slices.allSatisfy { $0.fileType == .executable },
                      "Every /bin/ls slice should report fileType == .executable")
    }

    func testParseBinLsLinksLibSystem() throws {
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"))
        let dylibs = binary.linkedDylibs
        XCTAssertTrue(
            dylibs.contains { $0.name.contains("libSystem.B.dylib") },
            "/bin/ls should link libSystem.B.dylib (it links it on every macOS version this project supports)"
        )
    }

    func testParseDyldIsTheDynamicLinker() throws {
        // /usr/lib/dyld is the dynamic linker; it's one of the few system
        // Mach-O files that still exist as a real on-disk file rather than
        // living entirely inside the dyld shared cache (libSystem and most
        // other libs are no longer addressable by path on modern macOS).
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/usr/lib/dyld"))
        XCTAssertFalse(binary.slices.isEmpty, "/usr/lib/dyld should produce at least one Mach-O slice")
        XCTAssertTrue(
            binary.slices.allSatisfy { $0.fileType == .dynamicLinker },
            "/usr/lib/dyld should report fileType == .dynamicLinker (MH_DYLINKER)"
        )
    }

    func testParseSelfBinaryExposesLinkedDylibs() throws {
        // The current test binary is itself a Mach-O. Parse it and make sure
        // the linked-dylib list is non-empty (Swift binaries always link at
        // least Swift runtime + libSystem).
        let selfPath = Bundle(for: OWBinaryTests.self).executablePath
        guard let selfPath else {
            XCTFail("Could not determine the test bundle's executable path")
            return
        }
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: selfPath))
        XCTAssertFalse(binary.linkedDylibs.isEmpty, "Self binary must link at least one dylib")
    }

    // MARK: - Error path

    func testParseNonexistentFileThrowsUnreadable() {
        let path = "/tmp/owlwatch-no-such-file-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: path)
        XCTAssertThrowsError(try OWBinary.parse(at: url)) { error in
            guard case OWBinaryError.unreadable = error else {
                return XCTFail("Expected .unreadable, got \(error)")
            }
        }
    }

    func testParseTextFileThrowsUnrecognizedMagic() throws {
        // Write a definitely-not-Mach-O file and confirm we reject it.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owlwatch-not-macho-\(UUID().uuidString).txt")
        let payload = "this is not a Mach-O\n".data(using: .utf8)!
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertThrowsError(try OWBinary.parse(at: tmp)) { error in
            guard case OWBinaryError.unrecognizedMagic = error else {
                return XCTFail("Expected .unrecognizedMagic, got \(error)")
            }
        }
    }

    // MARK: - Symbol table (M2.2)

    func testParseWithoutIncludeSymbolsLeavesSymbolsNil() throws {
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertTrue(binary.slices.allSatisfy { $0.symbols == nil },
                      "Default parse() should leave Slice.symbols == nil")
    }

    func testParseWithIncludeSymbolsPopulatesEachSlice() throws {
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"), includeSymbols: true)
        for slice in binary.slices {
            XCTAssertNotNil(slice.symbols, "includeSymbols=true must populate Slice.symbols")
            XCTAssertFalse(slice.symbols?.isEmpty ?? true,
                           "Expected /bin/ls slice to have at least one symbol")
        }
    }

    func testBinLsImportsLibcSymbols() throws {
        // /bin/ls links libSystem; libSystem provides _malloc, _free, _printf etc.
        // Those must appear in /bin/ls's symbol table as undefined externals.
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"), includeSymbols: true)
        let allSymbolNames: Set<String> = Set(
            binary.slices.flatMap { $0.symbols ?? [] }.map(\.name)
        )
        let hasLibcImport = allSymbolNames.contains("_printf") || allSymbolNames.contains("_malloc")
        XCTAssertTrue(
            hasLibcImport,
            "Expected /bin/ls to import _printf or _malloc from libSystem; sample: \(allSymbolNames.prefix(10))"
        )
    }

    func testBinLsHasUndefinedExternalSymbols() throws {
        let binary = try OWBinary.parse(at: URL(fileURLWithPath: "/bin/ls"), includeSymbols: true)
        for slice in binary.slices {
            let symbols = try XCTUnwrap(slice.symbols)
            let imports = symbols.filter { $0.isExternal && $0.kind == .undefined }
            XCTAssertGreaterThan(
                imports.count, 0,
                "Expected /bin/ls to have at least one external undefined symbol (an import)"
            )
        }
    }

    func testSymbolNmCodeIsUppercaseForExternal() {
        let external = Symbol(
            name: "_main", kind: .defined, value: 0x100000000,
            isExternal: true, isPrivateExternal: false,
            sectionIndex: 1, descriptionBits: 0
        )
        XCTAssertEqual(external.nmCode, "S")

        let local = Symbol(
            name: "_local", kind: .defined, value: 0,
            isExternal: false, isPrivateExternal: false,
            sectionIndex: 1, descriptionBits: 0
        )
        XCTAssertEqual(local.nmCode, "s")

        let undefinedExternal = Symbol(
            name: "_printf", kind: .undefined, value: 0,
            isExternal: true, isPrivateExternal: false,
            sectionIndex: 0, descriptionBits: 0
        )
        XCTAssertEqual(undefinedExternal.nmCode, "U")
    }

    // MARK: - Architecture mapping

    func testArchitectureNameIsCorrectForKnownTypes() {
        XCTAssertEqual(Architecture(rawCPUType: 7).name, "i386")
        XCTAssertEqual(Architecture(rawCPUType: 0x01000007).name, "x86_64")
        XCTAssertEqual(Architecture(rawCPUType: 12).name, "arm")
        XCTAssertEqual(Architecture(rawCPUType: 0x0100000C).name, "arm64")
        XCTAssertEqual(Architecture(rawCPUType: 0x0200000C).name, "arm64_32")
        if case .unknown(let cpuType) = Architecture(rawCPUType: 999) {
            XCTAssertEqual(cpuType, 999)
        } else {
            XCTFail("Expected .unknown for CPU type 999")
        }
    }
}
