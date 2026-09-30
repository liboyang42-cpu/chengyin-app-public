import ARKit
import AVFoundation
import Flutter
import UIKit

/// P4 图像追踪 Spike：ARKit 图像追踪的最小原生页。
///
/// 只上报业务无关事件（image_detected / tracking_stable / tracking_lost /
/// camera_unavailable / unsupported_device）；不判定「完成/发奖」。
final class ArImageTrackingBridge: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.chengyin.app/ar_image"
  static let eventChannelName = "com.chengyin.app/ar_image_events"

  private let channel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var sessionController: ArImageSessionViewController?

  override init() {
    fatalError("use init(messenger:)")
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()
    eventChannel.setStreamHandler(self)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "released", message: "bridge released", details: nil))
        return
      }
      switch call.method {
      case "isSupported":
        result(Self.hardwareSupported)
      case "start":
        self.start(call.arguments, result: result)
      case "stop":
        self.stop(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// iOS 11+ 才有 ARKit，而本仓基线 13.0，OS 版本维度恒可用；
  /// 真正的门是硬件（A9 及更早不支持）与模拟器（无相机）。
  static var hardwareSupported: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    return ARImageTrackingConfiguration.isSupported && AVCaptureDevice.default(for: .video) != nil
    #endif
  }

  private func start(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
      let widthCm = args["physicalWidthCm"] as? Double
    else {
      result(FlutterError(code: "invalid_arguments", message: "physicalWidthCm is required", details: nil))
      return
    }
    guard Self.hardwareSupported else {
      emit("unsupported_device")
      result(true)
      return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentSession(physicalWidthCm: widthCm, result: result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.presentSession(physicalWidthCm: widthCm, result: result)
          } else {
            self.emit("camera_unavailable")
            result(true)
          }
        }
      }
    default:
      emit("camera_unavailable")
      result(true)
    }
  }

  private func presentSession(physicalWidthCm: Double, result: @escaping FlutterResult) {
    guard sessionController == nil else {
      result(FlutterError(code: "already_started", message: "AR session is already running", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      emit("camera_unavailable")
      result(true)
      return
    }
    let controller = ArImageSessionViewController(
      physicalWidthCm: CGFloat(physicalWidthCm),
      onEvent: { [weak self] name in self?.emit(name) }
    ) { [weak self] in
      self?.sessionController = nil
    }
    sessionController = controller
    controller.modalPresentationStyle = .fullScreen
    presenter.present(controller, animated: true) { result(true) }
  }

  private func stop(result: @escaping FlutterResult) {
    guard let controller = sessionController else {
      result(true)
      return
    }
    controller.dismiss(animated: true) { result(true) }
  }

  private func emit(_ event: String) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?([
        "event": event,
        "timestampMs": Int64(Date().timeIntervalSince1970 * 1000),
      ])
    }
  }

  private static func topViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows.first { $0.isKeyWindow }?
      .rootViewController
  }

  // FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

/// 全屏 ARSCNView，识别一张本地锚图（Assets 里的 ArAnchorPoster）。
private final class ArImageSessionViewController: UIViewController, ARSessionDelegate {
  private let arView = ARSCNView()
  private let configuration = ARImageTrackingConfiguration()
  private let physicalWidthCm: CGFloat
  private let onEvent: (String) -> Void
  private let onDismiss: () -> Void

  /// 连续命中帧数达到该阈值才报 tracking_stable（≈1s @30fps）；丢失即清零。
  private static let stableFrameThreshold = 30
  private var consecutiveHitFrames = 0
  private var hasReportedDetection = false
  private var isTracking = false

  init(physicalWidthCm: CGFloat, onEvent: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
    self.physicalWidthCm = physicalWidthCm
    self.onEvent = onEvent
    self.onDismiss = onDismiss
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    arView.frame = view.bounds
    arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    arView.session.delegate = self
    view.addSubview(arView)

    if let image = UIImage(named: "ArAnchorPoster"), let cgImage = image.cgImage {
      let widthMeters = physicalWidthCm / 100
      let reference = ARReferenceImage(
        cgImage,
        orientation: .up,
        physicalWidth: widthMeters
      )
      // iOS 27 SDK 命名：trackingImages（旧 SDK 叫 referenceImages），
      // maximumNumberOfTrackedImages 默认为 1，无需显式设置。
      configuration.trackingImages = [reference]
    }
    arView.session.run(configuration, options: [.removeExistingAnchors])
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    arView.session.pause()
    onDismiss()
  }

  // ARSessionDelegate — 只报识别状态事件，不下业务结论。
  // ObjC 头文件是 session:didUpdateFrame:，Swift 侧导入名仍是 session(_:didUpdate:)。
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let hit = frame.anchors.contains { ($0 as? ARImageAnchor)?.isTracked ?? false }
    if hit {
      consecutiveHitFrames += 1
      if !hasReportedDetection {
        hasReportedDetection = true
        isTracking = true
        onEvent("image_detected")
      }
      if consecutiveHitFrames == Self.stableFrameThreshold {
        onEvent("tracking_stable")
      }
    } else if hasReportedDetection, isTracking {
      isTracking = false
      consecutiveHitFrames = 0
      onEvent("tracking_lost")
    }
  }
}
