import Cocoa
import FlutterMacOS
import XCTest

// MultiViewSupport.swift מקומפל גם לכאן, ולכן אין צורך ב-@testable import של האפליקציה.

class MultiViewEnablerTests: XCTestCase {

  // מלכודת לעדכון SDK: בלי המשתנה הזה ריבוי החלונות במק נופל ל"לא מוכן".
  func testFlutterEngineStillHasMultiViewEnabledBoolIvar() {
    let encoding = MultiViewEnabler.ivarTypeEncoding()
    XCTAssertNotNil(
      encoding, "FlutterEngine no longer has \(MultiViewEnabler.ivarName); update MultiViewSupport.swift")
    XCTAssertTrue(encoding == "c" || encoding == "B", "unexpected type encoding \(encoding ?? "nil")")
    XCTAssertTrue(FlutterEngine.accessInstanceVariablesDirectly)
  }

  func testEngineWithoutImplicitViewIsNotFlipped() {
    let engine = FlutterEngine(name: "multiview_test", project: nil, allowHeadlessExecution: true)
    XCTAssertEqual(MultiViewEnabler.enable(on: engine), .noImplicitView)
    XCTAssertFalse(MultiViewEnabler.isEnabled(engine))
  }

  func testDisabledMergedThreadIsNotReady() {
    let engine = FlutterEngine(name: "multiview_test", project: nil, allowHeadlessExecution: true)
    let status = MultiViewEnabler.enable(
      on: engine, infoDictionary: ["FLTEnableMergedPlatformUIThread": false])
    XCTAssertEqual(status, .mergedThreadDisabled)
    XCTAssertFalse(MultiViewEnabler.isEnabled(engine))
    XCTAssertTrue(MultiViewEnabler.isMergedPlatformUIThread(nil))
    XCTAssertTrue(
      MultiViewEnabler.isMergedPlatformUIThread(["FLTEnableMergedPlatformUIThread": true]))
  }

  func testRunnerFlipGivesNewViewControllersIdsAfterTheImplicitView() throws {
    let main = try XCTUnwrap(mainFlutterViewController(), "the main FlutterViewController")
    let engine = main.engine
    XCTAssertTrue(MultiViewEnabler.isEnabled(engine), "the runner did not flip the ivar")
    try waitUntilRunning(engine)

    var newIdentifier: FlutterViewIdentifier = -1
    autoreleasepool {
      let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
      newIdentifier = controller.viewIdentifier
      XCTAssertTrue(engine.viewController === main)
    }
    XCTAssertGreaterThanOrEqual(newIdentifier, 1)
    XCTAssertEqual(main.viewIdentifier, MultiViewEnabler.implicitViewId)
    XCTAssertTrue(engine.viewController === main, "the implicit view must stay attached")
  }

  private func mainFlutterViewController() -> FlutterViewController? {
    return NSApp.windows
      .compactMap { $0.contentViewController as? FlutterViewController }
      .first { $0.viewIdentifier == MultiViewEnabler.implicitViewId }
  }

  // מנוע שלא רץ לא מחזיר תשובה ל-RemoveView, והסרת התצוגה הייתה ממתינה לנצח.
  private func waitUntilRunning(_ engine: FlutterEngine) throws {
    let selector = NSSelectorFromString("running")
    try XCTSkipUnless(engine.responds(to: selector), "FlutterEngine.running was renamed")
    let deadline = Date().addingTimeInterval(60)
    while !((engine.value(forKey: "running") as? NSNumber)?.boolValue ?? false) {
      if Date() > deadline {
        throw XCTSkip("the main engine did not start within 60 seconds")
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
  }
}

class ViewWindowGeometryTests: XCTestCase {
  private let primaryHeight: CGFloat = 1000

  func testCocoaFrameBecomesTopLeftOfPrimaryScreen() {
    let cocoa = NSRect(x: 100, y: 200, width: 300, height: 400)
    let topLeft = ViewWindowGeometry.topLeft(fromCocoa: cocoa, primaryScreenHeight: primaryHeight)
    XCTAssertEqual(topLeft, NSRect(x: 100, y: 400, width: 300, height: 400))
  }

  func testScreenAbovePrimaryHasNegativeTop() {
    let cocoa = NSRect(x: -50, y: 1000, width: 800, height: 500)
    let topLeft = ViewWindowGeometry.topLeft(fromCocoa: cocoa, primaryScreenHeight: primaryHeight)
    XCTAssertEqual(topLeft, NSRect(x: -50, y: -500, width: 800, height: 500))
  }

  func testRoundTrip() {
    let topLeft = NSRect(x: 12.5, y: 34, width: 640, height: 480)
    let cocoa = ViewWindowGeometry.cocoa(fromTopLeft: topLeft, primaryScreenHeight: primaryHeight)
    XCTAssertEqual(cocoa, NSRect(x: 12.5, y: 486, width: 640, height: 480))
    XCTAssertEqual(
      ViewWindowGeometry.topLeft(fromCocoa: cocoa, primaryScreenHeight: primaryHeight), topLeft)
  }

  func testRectFromArguments() {
    XCTAssertEqual(
      ViewWindowGeometry.rect(from: ["x": 1, "y": 2, "width": 3, "height": 4]),
      NSRect(x: 1, y: 2, width: 3, height: 4))
    XCTAssertNil(ViewWindowGeometry.rect(from: ["x": 1, "y": 2, "width": 3]))
    XCTAssertNil(ViewWindowGeometry.rect(from: ["x": 1, "y": 2, "width": 0, "height": 4]))
  }

  func testDictionaryUsesChannelKeys() {
    XCTAssertEqual(
      ViewWindowGeometry.dictionary(NSRect(x: 1, y: 2, width: 3, height: 4)),
      ["x": 1, "y": 2, "width": 3, "height": 4])
  }
}
