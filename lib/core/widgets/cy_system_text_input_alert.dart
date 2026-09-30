import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CySystemKeyboardKind { text, ascii, number, decimal, phone, email, url }

const MethodChannel _nativeInputAlertChannel = MethodChannel(
  'com.chengyin.app/native_text_input_alert',
);

/// iOS 真机优先使用 `UIAlertController.addTextField`，由系统提供
/// Alert、UITextField、键盘、Dynamic Type 和 VoiceOver。
///
/// 其他平台、widget test 或原生通道异常时，只退回 Flutter
/// 官方 Cupertino Alert，不退回 Material Dialog。
Future<String?> showCySystemTextInputAlert({
  required BuildContext context,
  required String title,
  required String placeholder,
  required String confirmText,
  String cancelText = '取消',
  String initialValue = '',
  CySystemKeyboardKind keyboardKind = CySystemKeyboardKind.ascii,
}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
    try {
      return await _nativeInputAlertChannel
          .invokeMethod<String>('show', <String, Object>{
            'title': title,
            'placeholder': placeholder,
            'confirmText': confirmText,
            'cancelText': cancelText,
            'initialValue': initialValue,
            'keyboardKind': keyboardKind.name,
          });
    } on MissingPluginException {
      // Tests and older embeddings have no native presenter.
    } on PlatformException {
      // A presentation failure must not remove the manual recovery path.
    }
  }

  if (!context.mounted) return null;
  final TextEditingController controller = TextEditingController(
    text: initialValue,
  );
  final bool usesNaturalLanguage = keyboardKind == CySystemKeyboardKind.text;
  final String? value = await showCupertinoDialog<String>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          key: const Key('cy-system-input-alert-field'),
          controller: controller,
          autofocus: true,
          placeholder: placeholder,
          keyboardType: _keyboardType(keyboardKind),
          textInputAction: TextInputAction.done,
          autocorrect: usesNaturalLanguage,
          enableSuggestions: usesNaturalLanguage,
          smartDashesType: usesNaturalLanguage
              ? SmartDashesType.enabled
              : SmartDashesType.disabled,
          smartQuotesType: usesNaturalLanguage
              ? SmartQuotesType.enabled
              : SmartQuotesType.disabled,
          onSubmitted: (String value) =>
              Navigator.of(context).pop(value.trim()),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(cancelText),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  // Dialog 的退出动画还会读 controller，下一帧再释放。
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return value;
}

TextInputType _keyboardType(CySystemKeyboardKind kind) => switch (kind) {
  CySystemKeyboardKind.text => TextInputType.text,
  CySystemKeyboardKind.ascii => TextInputType.visiblePassword,
  CySystemKeyboardKind.number => TextInputType.number,
  CySystemKeyboardKind.decimal => const TextInputType.numberWithOptions(
    decimal: true,
  ),
  CySystemKeyboardKind.phone => TextInputType.phone,
  CySystemKeyboardKind.email => TextInputType.emailAddress,
  CySystemKeyboardKind.url => TextInputType.url,
};
