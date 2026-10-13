import Flutter
import XCTest

@testable import sound_recognition

/// The method channel's answers that need no microphone.
class RunnerTests: XCTestCase {

  private func call(_ method: String) -> Any? {
    let plugin = SoundRecognitionPlugin()
    var answer: Any?
    let answered = expectation(description: "\(method) answers")
    plugin.handle(FlutterMethodCall(methodName: method, arguments: nil)) { result in
      answer = result
      answered.fulfill()
    }
    waitForExpectations(timeout: 1)
    return answer
  }

  func testIsSupportedMatchesTheOSVersion() {
    let expected: Bool
    if #available(iOS 15.0, *) { expected = true } else { expected = false }
    XCTAssertEqual(call("isSupported") as? Bool, expected)
  }

  func testKnownLabelsIsAList() {
    XCTAssertNotNil(call("knownLabels") as? [String])
  }

  func testAnUnknownMethodIsNotImplemented() {
    XCTAssertTrue(call("getPlatformVersion") as AnyObject === FlutterMethodNotImplemented)
  }
}
