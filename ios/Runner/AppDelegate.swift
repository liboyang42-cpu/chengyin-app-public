import Flutter
import MapKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeDatePickerChannel: FlutterMethodChannel?
  private var nativeDatePickerController: NativeDatePickerViewController?
  private var placeSearchChannel: FlutterMethodChannel?
  private var nativeTextInputAlertChannel: FlutterMethodChannel?
  private var nativeTextInputAlertCoordinator: NativeTextInputAlertCoordinator?
  private var directionsBridge: DirectionsBridge?
  private var arImageTrackingBridge: ArImageTrackingBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ChengyinNativeDatePicker") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.chengyin.app/native_date_picker",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentNativeDatePicker(arguments: call.arguments, result: result)
    }
    nativeDatePickerChannel = channel

    // MapKit 地点搜索(lib/core/map/place_search.dart)。国内返回 GCJ-02,与后端一致。
    let placeChannel = FlutterMethodChannel(
      name: "com.chengyin.app/place_search",
      binaryMessenger: registrar.messenger()
    )
    placeChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "search",
        let args = call.arguments as? [String: Any],
        let query = args["query"] as? String,
        let lat = args["latitude"] as? Double,
        let lng = args["longitude"] as? Double
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
        latitudinalMeters: 20_000,
        longitudinalMeters: 20_000
      )
      MKLocalSearch(request: request).start { response, error in
        if let error = error {
          result(FlutterError(code: "search_failed", message: error.localizedDescription, details: nil))
          return
        }
        result((response?.mapItems ?? []).prefix(20).compactMap { item -> [String: Any]? in
          guard let name = item.name else { return nil }
          return [
            "name": name,
            "address": item.placemark.title ?? "",
            "latitude": item.placemark.coordinate.latitude,
            "longitude": item.placemark.coordinate.longitude,
          ]
        })
      }
    }
    placeSearchChannel = placeChannel

    let inputChannel = FlutterMethodChannel(
      name: "com.chengyin.app/native_text_input_alert",
      binaryMessenger: registrar.messenger()
    )
    inputChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentNativeTextInputAlert(arguments: call.arguments, result: result)
    }
    nativeTextInputAlertChannel = inputChannel
    directionsBridge = DirectionsBridge(messenger: registrar.messenger())
    arImageTrackingBridge = ArImageTrackingBridge(messenger: registrar.messenger())
  }

  private func presentNativeTextInputAlert(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let title = args["title"] as? String,
      let presenter = Self.topViewController()
    else {
      result(FlutterError(code: "invalid_arguments", message: "Input alert arguments are incomplete", details: nil))
      return
    }
    guard nativeTextInputAlertCoordinator == nil else {
      result(FlutterError(code: "already_presented", message: "An input alert is already visible", details: nil))
      return
    }

    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    let coordinator = NativeTextInputAlertCoordinator(result: result) { [weak self] in
      self?.nativeTextInputAlertCoordinator = nil
    }
    coordinator.alert = alert
    nativeTextInputAlertCoordinator = coordinator
    alert.addTextField { field in
      field.placeholder = args["placeholder"] as? String
      field.text = args["initialValue"] as? String
      field.clearButtonMode = .whileEditing
      field.returnKeyType = .done
      field.delegate = coordinator
      let keyboardKind = args["keyboardKind"] as? String
      let usesNaturalLanguage = keyboardKind == "text"
      field.autocorrectionType = usesNaturalLanguage ? .default : .no
      field.spellCheckingType = usesNaturalLanguage ? .default : .no
      if #available(iOS 11.0, *) {
        field.smartDashesType = usesNaturalLanguage ? .default : .no
        field.smartQuotesType = usesNaturalLanguage ? .default : .no
      }
      switch keyboardKind {
      case "text": field.keyboardType = .default
      case "number": field.keyboardType = .numberPad
      case "decimal": field.keyboardType = .decimalPad
      case "phone": field.keyboardType = .phonePad
      case "email": field.keyboardType = .emailAddress
      case "url": field.keyboardType = .URL
      default: field.keyboardType = .asciiCapable
      }
    }
    alert.addAction(UIAlertAction(
      title: args["cancelText"] as? String ?? NSLocalizedString("cancel", comment: "Cancel"),
      style: .cancel,
      handler: { [weak coordinator] _ in coordinator?.complete(nil) }
    ))
    alert.addAction(UIAlertAction(
      title: args["confirmText"] as? String ?? NSLocalizedString("confirm", comment: "Confirm"),
      style: .default,
      handler: { [weak coordinator] _ in
        coordinator?.complete(alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    ))
    presenter.present(alert, animated: true)
  }

  private func presentNativeDatePicker(arguments: Any?, result: @escaping FlutterResult) {
    guard nativeDatePickerController == nil else {
      result(FlutterError(code: "already_presented", message: "A date picker is already visible", details: nil))
      return
    }
    guard
      let args = arguments as? [String: Any],
      let initialMilliseconds = args["initialMilliseconds"] as? NSNumber,
      let minimumMilliseconds = args["minimumMilliseconds"] as? NSNumber,
      let maximumMilliseconds = args["maximumMilliseconds"] as? NSNumber,
      let presenter = Self.topViewController()
    else {
      result(FlutterError(code: "invalid_arguments", message: "Date picker arguments are incomplete", details: nil))
      return
    }
    let pickerMode: UIDatePicker.Mode
    switch args["mode"] as? String {
    case "date": pickerMode = .date
    case "time": pickerMode = .time
    case "dateTime": pickerMode = .dateAndTime
    default:
      result(FlutterError(code: "invalid_arguments", message: "Date picker mode is invalid", details: nil))
      return
    }

    let controller = NativeDatePickerViewController(
      titleText: args["title"] as? String ?? NSLocalizedString("datePickerTitle", comment: "Date picker title"),
      cancelText: args["cancelText"] as? String ?? NSLocalizedString("cancel", comment: "Cancel"),
      doneText: args["doneText"] as? String ?? NSLocalizedString("done", comment: "Done"),
      localeIdentifier: args["localeIdentifier"] as? String,
      mode: pickerMode,
      initialDate: Date(timeIntervalSince1970: initialMilliseconds.doubleValue / 1000),
      minimumDate: Date(timeIntervalSince1970: minimumMilliseconds.doubleValue / 1000),
      maximumDate: Date(timeIntervalSince1970: maximumMilliseconds.doubleValue / 1000),
      result: result,
      onFinish: { [weak self] in self?.nativeDatePickerController = nil }
    )
    nativeDatePickerController = controller
    controller.modalPresentationStyle = .pageSheet
    if #available(iOS 15.0, *) {
      controller.sheetPresentationController?.detents = [.medium()]
      controller.sheetPresentationController?.prefersGrabberVisible = true
      controller.sheetPresentationController?.preferredCornerRadius = 24
    }
    presenter.present(controller, animated: true)
  }

  private static func topViewController(_ base: UIViewController? = {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows.first { $0.isKeyWindow }?
      .rootViewController
  }()) -> UIViewController? {
    if let navigation = base as? UINavigationController {
      return topViewController(navigation.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topViewController(tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topViewController(presented)
    }
    return base
  }
}

private final class NativeTextInputAlertCoordinator: NSObject, UITextFieldDelegate {
  weak var alert: UIAlertController?

  private let completion: FlutterResult
  private let onFinish: () -> Void
  private var didComplete = false

  init(result: @escaping FlutterResult, onFinish: @escaping () -> Void) {
    completion = result
    self.onFinish = onFinish
  }

  func complete(_ value: String?, dismiss: Bool = false) {
    guard !didComplete else { return }
    didComplete = true
    let finish = { [completion, onFinish] in
      completion(value)
      onFinish()
    }
    if dismiss, let alert {
      alert.dismiss(animated: true, completion: finish)
    } else {
      finish()
    }
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    complete(
      textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
      dismiss: true
    )
    return false
  }
}

private final class NativeDatePickerViewController: UIViewController,
  UIAdaptivePresentationControllerDelegate
{
  private let picker = UIDatePicker()
  private let completion: FlutterResult
  private let onFinish: () -> Void
  private var didComplete = false
  private let titleText: String
  private let cancelText: String
  private let doneText: String
  private let mode: UIDatePicker.Mode

  init(
    titleText: String,
    cancelText: String,
    doneText: String,
    localeIdentifier: String?,
    mode: UIDatePicker.Mode,
    initialDate: Date,
    minimumDate: Date,
    maximumDate: Date,
    result: @escaping FlutterResult,
    onFinish: @escaping () -> Void
  ) {
    self.titleText = titleText
    self.cancelText = cancelText
    self.doneText = doneText
    self.mode = mode
    if let localeIdentifier = localeIdentifier {
      picker.locale = Locale(identifier: localeIdentifier)
    }
    completion = result
    self.onFinish = onFinish
    picker.date = initialDate
    picker.minimumDate = minimumDate
    picker.maximumDate = maximumDate
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    presentationController?.delegate = self

    picker.datePickerMode = mode
    if #available(iOS 14.0, *) {
      picker.preferredDatePickerStyle = mode == .date ? .inline : .wheels
    } else if #available(iOS 13.4, *) {
      picker.preferredDatePickerStyle = .wheels
    }
    picker.translatesAutoresizingMaskIntoConstraints = false

    let cancel = UIButton(type: .system)
    cancel.setTitle(cancelText, for: .normal)
    cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    let done = UIButton(type: .system)
    done.setTitle(doneText, for: .normal)
    done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

    let title = UILabel()
    title.text = titleText
    title.textAlignment = .center
    title.font = .preferredFont(forTextStyle: .headline)
    title.adjustsFontForContentSizeCategory = true

    let header = UIStackView(arrangedSubviews: [cancel, title, done])
    header.axis = .horizontal
    header.alignment = .center
    header.distribution = .fill
    header.translatesAutoresizingMaskIntoConstraints = false
    cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    done.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true

    view.addSubview(header)
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      header.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      picker.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      picker.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
    ])
  }

  @objc private func cancelTapped() {
    finish(nil)
  }

  @objc private func doneTapped() {
    finish(Int64(picker.date.timeIntervalSince1970 * 1000))
  }

  private func finish(_ value: Any?) {
    guard !didComplete else { return }
    didComplete = true
    dismiss(animated: true) { [completion, onFinish] in
      completion(value)
      onFinish()
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard !didComplete else { return }
    didComplete = true
    completion(nil)
    onFinish()
  }
}
