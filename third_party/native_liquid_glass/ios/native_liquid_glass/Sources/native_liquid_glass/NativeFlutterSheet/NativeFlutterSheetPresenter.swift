import Accessibility
import Flutter
import UIKit

/// B1 `native_flutter_sheet`:用 `UISheetPresentationController` 承载**主引擎**渲染的 Flutter 内容。
///
/// iOS 上一个 FlutterEngine 同时只能挂一个 FlutterViewController(无多视图)。
/// 为了让 sheet 内容与主界面共享同一个 isolate(Riverpod 状态、返回值),
/// 呈现期间把引擎从主控制器切到 sheet 里的内容控制器,关闭后再切回:
///
/// present  → 主视图盖快照 → 主控制器 surface 下线 → 内容控制器接管引擎(alpha 0)→ 弹 sheet
/// reveal   → Dart 已把内容放进 root overlay 并出帧 → 内容淡入
/// 关闭      → 内容控制器 surface 下线 → 引擎切回主控制器 → 回 Dart `dismissed`
/// restored → Dart 已拆 overlay 并出帧 → 撤快照
final class NativeFlutterSheetPresenter: NSObject {
  static let channelName = "native_liquid_glass/native_flutter_sheet"

  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar
  private var session: Session?

  private struct Session {
    let engine: FlutterEngine
    let mainController: FlutterViewController
    let snapshot: UIView?
    let host: UIViewController
    let content: FlutterViewController
    var dismissed = false
  }

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "present": self.present(call.arguments as? [String: Any] ?? [:], result: result)
      case "reveal": self.reveal(result: result)
      case "dismiss": self.dismiss(result: result)
      case "restored": self.restored(result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func present(_ args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      return result(FlutterError(code: "unsupported", message: "Sheet detents need iOS 15", details: nil))
    }
    guard session == nil else {
      return result(FlutterError(code: "already_presented", message: nil, details: nil))
    }
    guard
      let main = registrar.viewController as? FlutterViewController,
      main.isViewLoaded,
      Self.canSwapSurface(main)
    else {
      return result(FlutterError(code: "unsupported", message: "No attached FlutterViewController", details: nil))
    }
    let engine = main.engine
    var presenter: UIViewController = main
    while let presented = presenter.presentedViewController { presenter = presented }

    // 引擎切走后主视图不再出帧,先盖一张快照,关闭后 Dart 出完帧再撤。
    let snapshot = main.view.snapshotView(afterScreenUpdates: false)
    if let snapshot {
      snapshot.frame = main.view.bounds
      snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      main.view.addSubview(snapshot)
    }
    // content init 会同步换绑 engine.viewController,C++ 语义桥当场销毁;
    // 先断旧视图的 AX 元素链并把 Dart 语义状态翻回未启用,否则:
    // 悬垂元素被 AX 客户端遍历到 → SIGSEGV;Dart 停在「已启用但无桥」→
    // 新视图永久失明。细节见 rearmSemantics()。
    detachAccessibilityElements(main.view)
    setDartSemanticsEnabled(engine, enabled: false)
    Self.setSurface(main, appeared: false)
    let content = NativeFlutterSheetContentController(engine: engine, nibName: nil, bundle: nil)
    content.isViewOpaque = false

    let host = NativeFlutterSheetHostController(content: content) { [weak self] in
      self?.finish()
    }
    host.isModalInPresentation = !((args["dismissible"] as? Bool) ?? true)
    if let sheet = host.sheetPresentationController {
      switch args["detents"] as? String {
      case "medium": sheet.detents = [.medium()]
      case "large": sheet.detents = [.large()]
      default: sheet.detents = [.medium(), .large()]
      }
      sheet.prefersGrabberVisible = (args["grabber"] as? Bool) ?? true
    }
    session = Session(engine: engine, mainController: main, snapshot: snapshot, host: host, content: content)
    presenter.present(host, animated: true)
    result(nil)
  }

  private func reveal(result: FlutterResult) {
    if let content = session?.content {
      UIView.animate(withDuration: 0.15) { content.view.alpha = 1 }
    }
    // sheet 内容已就位:重建语义树,并让 AX 客户端重走一遍新层级。
    if let engine = session?.engine {
      rearmSemantics(engine)
    }
    UIAccessibility.post(notification: .layoutChanged, argument: nil)
    result(nil)
  }

  private func dismiss(result: FlutterResult) {
    session?.host.dismiss(animated: true)
    result(nil)
  }

  /// sheet 已真正消失(下滑关闭或 Dart 请求关闭):把引擎还给主控制器。
  private func finish() {
    guard var current = session, !current.dismissed else { return }
    current.dismissed = true
    session = current

    // 同 present:换绑销毁语义桥之前,先断两张视图的 AX 元素链,
    // 并把 Dart 语义状态翻回未启用(见 rearmSemantics())。
    if current.content.isViewLoaded {
      detachAccessibilityElements(current.content.view)
    }
    detachAccessibilityElements(current.mainController.view)
    setDartSemanticsEnabled(current.engine, enabled: false)

    Self.setSurface(current.content, appeared: false)
    current.engine.viewController = current.mainController
    // 重新下发主视图尺寸(引擎里还是 sheet 的尺寸),再建 surface。
    current.mainController.view.setNeedsLayout()
    current.mainController.view.layoutIfNeeded()
    Self.setSurface(current.mainController, appeared: true)
    current.content.willMove(toParent: nil)
    current.content.view.removeFromSuperview()
    current.content.removeFromParent()

    channel.invokeMethod("dismissed", arguments: nil)
    // Dart 侧若没回 restored(热重启等),也别让快照永久盖住主界面。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      if self?.session?.dismissed == true { self?.clearSession() }
    }
  }

  private func restored(result: FlutterResult) {
    let engine = session?.engine
    if session?.dismissed == true { clearSession() }
    // Dart 已拆掉 sheet overlay、主控制器接完帧:重建主视图的语义树。
    if let engine {
      rearmSemantics(engine)
    }
    UIAccessibility.post(notification: .layoutChanged, argument: nil)
    result(nil)
  }

  private func clearSession() {
    session?.snapshot?.removeFromSuperview()
    session = nil
  }

  // MARK: - Accessibility 换绑重挂
  //
  // 引擎换绑 viewController 时 `PlatformViewIOS::SetOwnerViewController` 无条件
  // 销毁 C++ 语义桥;而 Dart 侧「语义已启用」状态并不随之回退,后续所有
  // 语义更新因无桥而被丢弃 —— 新视图对 AX 客户端永久失明(snapshot-ui 零
  // ref / VoiceOver 读不到),且旧视图 accessibilityElements 仍被 UIKit 强持有,
  // 元素内 C++ 节点已悬垂,再遍历即 SIGSEGV。
  // 对策:换绑前断元素链 + 把 Dart 状态翻回未启用;换绑落定后按引擎自己的
  // 启用判据(模拟器恒开、设备看辅助功能是否在跑)重新启用,触发
  // false→true 过渡 → 桥在新 owner 上重建 → 整棵语义树重发。

  /// 断掉 UIKit 对旧语义元素的强引用,必须在桥销毁(换绑)之前调。
  private func detachAccessibilityElements(_ view: UIView) {
    view.accessibilityElements = nil
  }

  /// 走 `-[FlutterEngine enableSemantics:withFlags:]`(引擎内部方法,非 Apple
  /// 私有 API;与 surfaceUpdated: 同一先例):把 Dart 侧 semanticsEnabled 置为
  /// enabled 并同步系统无障碍开关位。引擎改名时静默跳过,退化为修前行为。
  private func setDartSemanticsEnabled(_ engine: FlutterEngine, enabled: Bool) {
    let selector = NSSelectorFromString("enableSemantics:withFlags:")
    guard engine.responds(to: selector),
          let implementation = engine.method(for: selector) else { return }
    typealias EnableSemantics = @convention(c) (AnyObject, Selector, ObjCBool, Int64) -> Void
    let function = unsafeBitCast(implementation, to: EnableSemantics.self)
    function(engine, selector, ObjCBool(enabled), Self.currentAccessibilityFeatureFlags())
  }

  /// 换绑落定后重新启用语义(判据与引擎 `onAccessibilityStatusChanged:` 一致)。
  private func rearmSemantics(_ engine: FlutterEngine) {
    #if targetEnvironment(simulator)
    let shouldEnable = true
    #else
    let shouldEnable = UIAccessibility.isVoiceOverRunning
      || UIAccessibility.isSwitchControlRunning
      || UIAccessibility.isSpeakScreenEnabled
    #endif
    guard shouldEnable else { return }
    setDartSemanticsEnabled(engine, enabled: true)
  }

  /// 位定义对齐引擎 `FlutterAccessibilityFeatures.flags`(window.dart 同序)。
  private static func currentAccessibilityFeatureFlags() -> Int64 {
    var flags: Int64 = 0
    if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning {
      flags |= 1 << 0  // accessibleNavigation
    }
    if UIAccessibility.isInvertColorsEnabled { flags |= 1 << 1 }
    if UIAccessibility.isBoldTextEnabled { flags |= 1 << 3 }
    if UIAccessibility.isReduceMotionEnabled { flags |= 1 << 4 }
    if UIAccessibility.isDarkerSystemColorsEnabled { flags |= 1 << 5 }
    if UIAccessibility.isOnOffSwitchLabelsEnabled { flags |= 1 << 6 }
    if #available(iOS 18.0, *) {
      if !AccessibilitySettings.animatedImagesEnabled { flags |= 1 << 8 }
      if AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator { flags |= 1 << 10 }
    }
    if !UIAccessibility.isVideoAutoplayEnabled { flags |= 1 << 9 }
    return flags
  }

  /// `surfaceUpdated:` 是 FlutterViewController 内部方法(不是 Apple 私有 API);
  /// 引擎改名时 present 前就判不支持,Dart 回退 showCupertinoSheet。
  private static let surfaceUpdatedSelector = NSSelectorFromString("surfaceUpdated:")

  private static func canSwapSurface(_ controller: FlutterViewController) -> Bool {
    controller.responds(to: surfaceUpdatedSelector)
  }

  private static func setSurface(_ controller: FlutterViewController, appeared: Bool) {
    typealias SurfaceUpdated = @convention(c) (AnyObject, Selector, Bool) -> Void
    let implementation = controller.method(for: surfaceUpdatedSelector)
    unsafeBitCast(implementation, to: SurfaceUpdated.self)(controller, surfaceUpdatedSelector, appeared)
  }
}

/// 内容控制器:只为 deinit 计数(内存观测:关闭后必须归零)。
final class NativeFlutterSheetContentController: FlutterViewController {
  static private(set) var live = 0

  override init(engine: FlutterEngine, nibName: String?, bundle nibBundle: Bundle?) {
    super.init(engine: engine, nibName: nibName, bundle: nibBundle)
    Self.live += 1
  }

  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    Self.live -= 1
    NSLog("[B1] content deinit, live contents=%d", Self.live)
  }
}

final class NativeFlutterSheetHostController: UIViewController {
  static private(set) var live = 0

  private let content: FlutterViewController
  private let onDismissed: () -> Void

  init(content: FlutterViewController, onDismissed: @escaping () -> Void) {
    self.content = content
    self.onDismissed = onDismissed
    super.init(nibName: nil, bundle: nil)
    Self.live += 1
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // 内容控制器不接收外观回调:否则它会给 Dart 发 inactive/paused 生命周期。
  override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26.0, *) {
      view.backgroundColor = nil  // 系统 Liquid Glass 背景(S3 不加自定义背景)
    } else {
      view.backgroundColor = .systemBackground  // iOS 15–25 系统 sheet 旧样式
    }
    addChild(content)
    content.view.frame = view.bounds
    content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    content.view.backgroundColor = .clear
    content.view.alpha = 0
    view.addSubview(content.view)
    content.didMove(toParent: self)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || presentingViewController == nil {
      onDismissed()
    }
  }

  deinit {
    Self.live -= 1
    NSLog("[B1] host deinit, live hosts=%d", Self.live)
  }
}
