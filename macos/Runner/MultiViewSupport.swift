import Cocoa
import FlutterMacOS
import ObjectiveC

/// מדליק ריבוי תצוגות במנוע שכבר יש לו תצוגה מרומזת (0), כך שחלונות Dart יקבלו מזהה ≥1.
/// הקובץ מקומפל גם ל-RunnerTests, ולכן אין בו מצב.
enum MultiViewEnabler {
  // TODO: קישור ל-issue ב-flutter/flutter ("macOS: enableMultiView asserts when an implicit
  // view exists"). להסיר את ההיפוך כשהמנוע יאפשר חלונות לצד התצוגה המרומזת.
  static let ivarName = "_multiViewEnabled"
  static let key = "multiViewEnabled"
  static let implicitViewId: FlutterViewIdentifier = 0

  enum Status: Equatable {
    case ready
    case ivarMissing
    case unexpectedIvarType(String)
    case noImplicitView
    case mergedThreadDisabled
    case flipNotApplied

    var isReady: Bool { self == .ready }

    var reason: String {
      switch self {
      case .ready: return "ready"
      case .ivarMissing: return "ivar \(MultiViewEnabler.ivarName) not found"
      case .unexpectedIvarType(let encoding): return "ivar has type '\(encoding)', expected BOOL"
      case .noImplicitView: return "engine has no implicit view"
      case .mergedThreadDisabled: return "FLTEnableMergedPlatformUIThread is false"
      case .flipNotApplied: return "ivar did not change"
      }
    }
  }

  static func ivarTypeEncoding() -> String? {
    guard let ivar = class_getInstanceVariable(FlutterEngine.self, ivarName) else { return nil }
    guard let encoding = ivar_getTypeEncoding(ivar) else { return "" }
    return String(cString: encoding)
  }

  /// חלונות Dart קוראים ל-AppKit ב-FFI סינכרוני, ולכן חייבים את התהליכון הממוזג.
  static func isMergedPlatformUIThread(_ info: [String: Any]?) -> Bool {
    guard let value = info?["FLTEnableMergedPlatformUIThread"] as? NSNumber else { return true }
    return value.boolValue
  }

  /// כל בדיקה כאן מונעת NSUndefinedKeyException, שאי אפשר לתפוס ב-Swift.
  static func enable(
    on engine: FlutterEngine, infoDictionary: [String: Any]? = Bundle.main.infoDictionary
  ) -> Status {
    guard isMergedPlatformUIThread(infoDictionary) else { return .mergedThreadDisabled }
    guard FlutterEngine.accessInstanceVariablesDirectly,
      let encoding = ivarTypeEncoding()
    else { return .ivarMissing }
    // BOOL הוא "c" ב-x86_64 ו-"B" ב-arm64.
    guard encoding == "c" || encoding == "B" else { return .unexpectedIvarType(encoding) }
    guard let implicit = engine.viewController, implicit.viewIdentifier == implicitViewId else {
      return .noImplicitView
    }
    engine.setValue(true, forKey: key)
    return isEnabled(engine) ? .ready : .flipNotApplied
  }

  static func isEnabled(_ engine: FlutterEngine) -> Bool {
    guard FlutterEngine.accessInstanceVariablesDirectly, ivarTypeEncoding() != nil else {
      return false
    }
    return (engine.value(forKey: key) as? NSNumber)?.boolValue ?? false
  }
}

/// המרת מסגרות בין Cocoa (ראשית בפינה התחתונה של המסך הראשי) לפינה עליונה גלובלית,
/// באותה מוסכמה של `getBounds` ב-window_manager, כדי שהחלון הראשי וחלונות Dart יחלקו מרחב.
enum ViewWindowGeometry {
  static func topLeft(fromCocoa rect: NSRect, primaryScreenHeight: CGFloat) -> NSRect {
    return NSRect(
      x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height,
      width: rect.width, height: rect.height)
  }

  static func cocoa(fromTopLeft rect: NSRect, primaryScreenHeight: CGFloat) -> NSRect {
    return NSRect(
      x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height,
      width: rect.width, height: rect.height)
  }

  static func dictionary(_ rect: NSRect) -> [String: Double] {
    return [
      "x": Double(rect.minX), "y": Double(rect.minY),
      "width": Double(rect.width), "height": Double(rect.height),
    ]
  }

  static func rect(from arguments: [String: Any]) -> NSRect? {
    guard let x = arguments["x"] as? NSNumber, let y = arguments["y"] as? NSNumber,
      let width = arguments["width"] as? NSNumber, let height = arguments["height"] as? NSNumber,
      width.doubleValue > 0, height.doubleValue > 0
    else { return nil }
    return NSRect(
      x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue)
  }
}
