import Cocoa
import FlutterMacOS

/// הצד הנייטיב של חלונות Dart (RegularWindowController) במנוע הראשי: היפוך ריבוי התצוגות,
/// הסתרה עד הפריים הראשון וערוץ `otzaria/view_window`. קואורדינטות: נקודות, פינה עליונה גלובלית.
final class OtzariaViewWindows {
  static let shared = OtzariaViewWindows()

  static let channelName = "otzaria/view_window"
  static let revealTimeout: TimeInterval = 20
  static let windowMethods: Set<String> = [
    "frame", "setFrame", "isVisible", "orderFront", "makeKey", "startDragging", "visibleFrame",
    "makeFrameless", "reveal", "cloak", "placement",
  ]

  private(set) var status: MultiViewEnabler.Status = .noImplicitView
  private(set) var isReopenHandledByDart = false
  private weak var mainEngine: FlutterEngine?
  private var channel: FlutterMethodChannel?
  private var observers: [NSObjectProtocol] = []
  private let knownWindows = NSHashTable<NSWindow>.weakObjects()

  private init() {}

  /// נקרא פעם אחת, אחרי שה-controller הראשי נרשם כתצוגה המרומזת ואחרי רישום התוספים.
  func attach(mainController: FlutterViewController) {
    guard channel == nil else { return }
    let engine = mainController.engine
    mainEngine = engine
    status = MultiViewEnabler.enable(on: engine)
    if !status.isReady {
      NSLog("Otzaria multiview is not available: \(status.reason)")
    }

    let channel = FlutterMethodChannel(
      name: OtzariaViewWindows.channelName, binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handle(call, result: result)
    }
    self.channel = channel

    if status.isReady {
      observeNewViewWindows()
    }
  }

  static func handle(of window: NSWindow) -> Int {
    return Int(bitPattern: Unmanaged.passUnretained(window).toOpaque())
  }

  // MARK: הסתרה עד הפריים הראשון

  // המסגרת מציגה חלון חדש ב-makeKeyAndOrderFront לפני הפריים הראשון. שינוי הגודל קודם
  // להצגה ולכן תופס אותו לפני שנראה; didBecomeKey הוא רשת ביטחון. לא נוגעים ב-delegate.
  private func observeNewViewWindows() {
    let center = NotificationCenter.default
    for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
          guard let window = note.object as? NSWindow else { return }
          self?.cloakIfNew(window)
        })
    }
  }

  func isDartViewWindow(_ window: NSWindow) -> Bool {
    guard let engine = mainEngine, !(window is OtzariaWindow),
      window.styleMask.contains(.miniaturizable),
      let controller = window.contentViewController as? FlutterViewController,
      controller.engine === engine,
      controller.viewIdentifier != MultiViewEnabler.implicitViewId
    else { return false }
    return true
  }

  @discardableResult
  private func cloakIfNew(_ window: NSWindow) -> Bool {
    guard !knownWindows.contains(window), isDartViewWindow(window) else { return false }
    knownWindows.add(window)
    // שקוף ולא מוסתר: חלון שאינו על המסך אינו מקבל פריימים.
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    DispatchQueue.main.asyncAfter(deadline: .now() + OtzariaViewWindows.revealTimeout) {
      [weak self, weak window] in
      guard let self = self, let window = window else { return }
      self.reveal(window, activate: false)
    }
    return true
  }

  @discardableResult
  private func reveal(_ window: NSWindow, activate: Bool) -> Bool {
    guard isDartViewWindow(window) else { return false }
    knownWindows.add(window)
    window.ignoresMouseEvents = false
    window.alphaValue = 1
    if activate {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  // MARK: Dock

  /// מבקש מ-Dart לשחזר חלון שנסגר; false אם Dart לא הודיע שהוא מטפל בזה.
  func requestReopen(fallback: @escaping () -> Void) -> Bool {
    guard isReopenHandledByDart, let channel = channel else { return false }
    channel.invokeMethod("reopenRequested", arguments: nil) { result in
      if (result as? Bool) != true {
        fallback()
      }
    }
    return true
  }

  // MARK: הערוץ

  private func resolveWindow(from arguments: Any?) -> NSWindow? {
    guard let args = arguments as? [String: Any],
      let handle = (args["handle"] as? NSNumber)?.intValue
    else { return nil }
    return NSApp.windows.first { OtzariaViewWindows.handle(of: $0) == handle }
  }

  private static func unknownWindow(_ call: FlutterMethodCall) -> FlutterError {
    return FlutterError(
      code: "unknown_window", message: "\(call.method): no NSWindow for this handle",
      details: nil)
  }

  private var primaryScreenHeight: CGFloat {
    return NSScreen.screens.first?.frame.height ?? 0
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "multiViewReady":
      result(status.isReady)
      return
    case "multiViewStatus":
      result(status.reason)
      return
    case "keyWindow":
      result(NSApp.keyWindow.map { OtzariaViewWindows.handle(of: $0) })
      return
    case "enableReopenHandling":
      isReopenHandledByDart = true
      result(nil)
      return
    default:
      guard OtzariaViewWindows.windowMethods.contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
    }

    guard let window = resolveWindow(from: call.arguments) else {
      result(OtzariaViewWindows.unknownWindow(call))
      return
    }
    switch call.method {
    case "frame":
      result(
        ViewWindowGeometry.dictionary(
          ViewWindowGeometry.topLeft(
            fromCocoa: window.frame, primaryScreenHeight: primaryScreenHeight)))

    case "placement":
      var placement: [String: Any] = ViewWindowGeometry.dictionary(
        ViewWindowGeometry.topLeft(
          fromCocoa: window.frame, primaryScreenHeight: primaryScreenHeight))
      placement["maximized"] = window.isZoomed
      result(placement)

    case "setFrame":
      guard let rect = ViewWindowGeometry.rect(from: args) else {
        result(FlutterError(code: "bad_args", message: "setFrame needs x/y/width/height", details: nil))
        return
      }
      window.setFrame(
        ViewWindowGeometry.cocoa(fromTopLeft: rect, primaryScreenHeight: primaryScreenHeight),
        display: true, animate: args["animate"] as? Bool ?? false)
      result(nil)

    case "isVisible":
      result(window.isVisible)

    case "orderFront":
      window.orderFront(nil)
      result(nil)

    case "makeKey":
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)

    case "startDragging":
      result(nil)
      // כמו window_manager: אחרי התשובה, כי performDrag מריץ לולאת מעקב עד שחרור העכבר.
      DispatchQueue.main.async {
        guard let event = NSApp.currentEvent else { return }
        let wasMovable = window.isMovable
        window.isMovable = true
        window.performDrag(with: event)
        window.isMovable = wasMovable
      }

    case "visibleFrame":
      guard let screen = window.screen ?? NSScreen.main else {
        result(nil)
        return
      }
      var frame: [String: Double] = ViewWindowGeometry.dictionary(
        ViewWindowGeometry.topLeft(
          fromCocoa: screen.visibleFrame, primaryScreenHeight: primaryScreenHeight))
      frame["scale"] = Double(screen.backingScaleFactor)
      result(frame)

    case "makeFrameless":
      makeFrameless(window)
      result(nil)

    case "reveal":
      result(reveal(window, activate: args["activate"] as? Bool ?? true))

    case "cloak":
      result(cloakIfNew(window))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// כמו `TitleBarStyle.hidden` + `windowButtonVisibility: false` בחלון הראשי. הנעילה
  /// מראש: AppKit מוסר אזורי גרירה לשרת החלונות, וגרירת כרטיסיה הייתה מזיזה את החלון.
  private func makeFrameless(_ window: NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = true
    }
    window.isMovable = false
  }
}
