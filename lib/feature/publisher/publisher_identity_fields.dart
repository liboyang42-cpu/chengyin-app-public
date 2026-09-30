import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_inline_error.dart';
import '../../core/widgets/cy_widgets.dart';
import 'publisher_identity.dart';

/// 发布者实名表单的页面侧状态(三入口共用)。
///
/// ★ 隐私红线:姓名/身份证号**页面上填过之后不再回显** —— 登记成功当场
///   清空两格控件并收起整个表单,值不留在这份状态里,也不进任何日志/缓存。
class PublisherIdentityController extends ChangeNotifier {
  PublisherIdentityController({required this.source, this._registered = false});

  /// 采集入口:club_apply / merchant_apply / topic_publish。
  final String source;

  final TextEditingController realName = TextEditingController();
  final TextEditingController idCard = TextEditingController();

  bool _registered;
  bool _consented = false;
  String? _error;
  bool _busy = false;

  bool get registered => _registered;
  bool get consented => _consented;
  String? get error => _error;
  bool get busy => _busy;

  PublisherIdentityFormState get form => PublisherIdentityFormState(
    realName: realName.text,
    idCard: idCard.text,
    consented: _consented,
    registered: _registered,
    source: source,
  );

  /// 三项齐不齐(按钮可点性判据);规则只有 checkIdentityForm 一份。
  bool get satisfied => identitySatisfied(form);

  /// 第一条不满足的原因;齐了返回 null。置灰键被点时拿它说话。
  String? get firstProblem => checkIdentityForm(form);

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  void setError(String? message) {
    _error = message;
    notifyListeners();
  }

  void setConsented(bool value) {
    if (_consented == value) return;
    _consented = value;
    _error = null;
    notifyListeners();
  }

  /// 已登记(状态查询回来、或登记成功):收起填字段入口并当场清值。
  void markRegistered() {
    _registered = true;
    realName.clear();
    idCard.clear();
    _consented = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    realName.dispose();
    idCard.dispose();
    super.dispose();
  }
}

/// 发布者实名一节:标题 + (未登记时)姓名/身份证号/单独同意 + 页脚提示;
/// 已登记的人不再给填字段的入口,只回显一句状态。
///
/// 对齐真源三处形态(club apply 第 4 步 / merchant apply 第 4 步 / fabu
/// 发布确认弹层):字段、文案、时序一份,页面只提供各自的标题与页脚文案。
class PublisherIdentityFields extends StatelessWidget {
  const PublisherIdentityFields({
    super.key,
    required this.controller,
    required this.title,
    required this.footHint,
  });

  final PublisherIdentityController controller;
  final String title;
  final String footHint;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CySectionTitle(title),
          const SizedBox(height: CyTokens.space2),
          if (controller.registered)
            Text(
              kIdentityAlreadyRegisteredHint,
              style: CyType.footnote.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            )
          else ...<Widget>[
            CyField(
              label: '真实姓名',
              child: _textField(
                context,
                controller.realName,
                key: const ValueKey<String>('identity-real-name'),
                hint: '与身份证一致',
                maxLength: 20,
                next: true,
              ),
            ),
            CyField(
              label: '身份证号',
              child: _textField(
                context,
                controller.idCard,
                key: const ValueKey<String>('identity-id-card'),
                hint: '18 位',
                maxLength: 18,
                next: false,
              ),
            ),
            _ConsentRow(
              consented: controller.consented,
              enabled: !controller.busy,
              onChanged: controller.setConsented,
            ),
            const SizedBox(height: CyTokens.space1),
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Text(
                footHint,
                style: CyType.footnote.copyWith(
                  color: CyPalette.of(context).textTertiary,
                ),
              ),
            ),
            if (controller.error case final String message)
              CyInlineError(key: const Key('identity-error'), title: '实名没有登记', detail: message),
          ],
        ],
      ),
    );
  }

  Widget _textField(
    BuildContext context,
    TextEditingController editing, {
    required Key key,
    required String hint,
    required int maxLength,
    required bool next,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: editing,
      maxLength: maxLength,
      readOnly: controller.busy,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: next ? TextInputAction.next : TextInputAction.done,
      inputFormatters: <TextInputFormatter>[
        LengthLimitingTextInputFormatter(maxLength),
      ],
      onChanged: (_) => controller.setError(null),
      placeholder: hint,
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
    );
  }
}

/// 单独同意勾选(个保法 §29):默认不勾,必须用户显式给出。
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.consented,
    required this.enabled,
    required this.onChanged,
  });

  final bool consented;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('identity-consent'),
      container: true,
      checked: consented,
      enabled: enabled,
      label: kIdentityConsentText,
      onTap: enabled ? () => onChanged(!consented) : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!consented) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: ExcludeSemantics(
            child: Row(
              children: <Widget>[
                CupertinoCheckbox(
                  value: consented,
                  onChanged: enabled
                      ? (bool? value) => onChanged(value ?? false)
                      : null,
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Text(
                    kIdentityConsentText,
                    style: CyType.footnote.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
