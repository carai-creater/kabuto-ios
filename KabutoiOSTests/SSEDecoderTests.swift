import XCTest
@testable import KabutoiOS

/// Pins the AI SDK v6 UI message stream shape we care about in iOS.
/// Unknown events are ignored silently.
final class SSEDecoderTests: XCTestCase {

    func testTextDeltaProducesEvent() throws {
        let line = #" {"type":"text-delta","id":"a","delta":"hello"}"#
        let event = SSEDecoder.decode(dataLine: line)
        XCTAssertEqual(event, .textDelta(id: "a", delta: "hello"))
    }

    func testTextDeltaAlternateKeyIsSupported() throws {
        // Some paths emit `text` instead of `delta`.
        let line = #"{"type":"text-delta","id":"x","text":"hi"}"#
        let event = SSEDecoder.decode(dataLine: line)
        XCTAssertEqual(event, .textDelta(id: "x", delta: "hi"))
    }

    func testTextStartAndEndDecode() {
        XCTAssertEqual(
            SSEDecoder.decode(dataLine: #"{"type":"text-start","id":"a"}"#),
            .textStart(id: "a")
        )
        XCTAssertEqual(
            SSEDecoder.decode(dataLine: #"{"type":"text-end","id":"a"}"#),
            .textEnd(id: "a")
        )
    }

    func testFinishEvent() {
        XCTAssertEqual(
            SSEDecoder.decode(dataLine: #"{"type":"finish"}"#),
            .finish
        )
    }

    func testDoneSentinelMapsToFinish() {
        XCTAssertEqual(SSEDecoder.decode(dataLine: " [DONE]"), .finish)
    }

    func testUnknownEventsAreIgnored() {
        XCTAssertNil(SSEDecoder.decode(dataLine: #"{"type":"start-step"}"#))
        XCTAssertNil(SSEDecoder.decode(dataLine: #"{"type":"tool-input-available","toolName":"x"}"#))
        XCTAssertNil(SSEDecoder.decode(dataLine: #"{"type":"reasoning-delta","delta":"..."}"#))
    }

    func testErrorEventSurfaces() {
        let event = SSEDecoder.decode(dataLine: #"{"type":"error","errorText":"model blew up"}"#)
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "model blew up")
        } else {
            XCTFail("expected .error event")
        }
    }

    func testMalformedJSONIsSkipped() {
        XCTAssertNil(SSEDecoder.decode(dataLine: "not-json"))
        XCTAssertNil(SSEDecoder.decode(dataLine: "{}"))
    }
}
