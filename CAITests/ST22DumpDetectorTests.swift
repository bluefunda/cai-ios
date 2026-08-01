import XCTest
@testable import CAI

// MARK: - ST22 Dump Detector Tests (bluefunda/cai-ios#182)

final class ST22DumpDetectorTests: XCTestCase {
    func test_recognizesTypicalShortDumpText() {
        let dump = """
        Runtime Errors         MESSAGE_TYPE_X
        Except.                CX_SY_ZERODIVIDE
        Date and Time          07/31/2026 10:15:32

        Short text
            The ABAP/4 program raised an exception.

        What happened?
            Error analysis
            Termination occurred in the ABAP program "SAPLZFI_UTIL" ...

        System environment
            SAP Release ...
        """
        XCTAssertTrue(ST22DumpDetector.looksLikeDump(dump))
    }

    func test_ignoresOrdinaryChatMessage() {
        let message = "Hey, can you help me understand what the FB60 transaction does in FI?"
        XCTAssertFalse(ST22DumpDetector.looksLikeDump(message))
    }

    func test_ignoresShortTextEvenWithOneMarker() {
        let message = "short text here"
        XCTAssertFalse(ST22DumpDetector.looksLikeDump(message))
    }

    func test_ignoresSingleMarkerInLongerText() {
        let message = String(repeating: "This message mentions except. only once and is otherwise unrelated filler text. ", count: 3)
        XCTAssertFalse(ST22DumpDetector.looksLikeDump(message))
    }
}
