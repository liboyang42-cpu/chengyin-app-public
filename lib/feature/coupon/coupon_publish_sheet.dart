// 发布优惠券(商家侧)—— 对应小程序 utils/coupon-form.js + subpackageMember/couponInfo。
//
// App 此前**发不了券**:只有「我发布的券」列表(看),没有创建入口,
// /api/coupon/publish 零调用方。
//
// ★★ 后端两道闸,失败原因必须**原样透传**:
//   ① RBAC 配额:「你还能发几张」是可执行信息,吞掉了用户不知道该去下架旧券
//   ② 发券防重(Redis SETNX,商家+类型+分钟粒度):连点回「发券太频繁,请稍后再试」——
//      那是**保护不是错误**,别引导用户去改表单
//   所以这里 catch 到的话原文显示,一个字都不改写。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_sheet.dart';

/// 券类型。★ 与小程序 `utils/coupon-form.js` `COUPON_TYPE_LABELS` 逐字对齐,
///   并保留它的下标语义:
///   picker 里 0 是「请选择」,提交时要 **-1** 才是后端的类型值。
///   这个 off-by-one 是小程序那边的既有约定(coupon-form.js:47),
///   照搬而不是自己重新编号 —— 编号一变,历史券的类型就对不上了。
const List<String> kCouponTypePicker = <String>[
  '请选择',
  '礼品券',
  '9折券',
  '8折券',
  '体验卡',
];

/// picker 下标 → 后端 couponType。0(请选择)不合法,返回 null。
int? couponTypeWire(int pickerIndex) =>
    pickerIndex <= 0 || pickerIndex >= kCouponTypePicker.length
    ? null
    : pickerIndex - 1;

/// 后端 couponType → 展示文案(真源 `coupon.js normalizeCoupon`:
/// -1(存量无类型)不许落进 `[0]='请选择'` 冒充表单占位,认不出的回落「优惠券」)。
String couponTypeLabel(int? wireType) {
  if (wireType == null || wireType < 0) return '优惠券';
  final idx = wireType + 1;
  return idx < kCouponTypePicker.length ? kCouponTypePicker[idx] : '优惠券';
}

/// 表单校验。★ 报错顺序与小程序 `validate()` 一致 —— 按用户填写顺序,
/// 一次只说一条,不一次糊一堆。
String? couponFormBlocker({
  required String name,
  required DateTime? startTime,
  required DateTime? endTime,
  required int typePickerIndex,
  required int? publishCount,
}) {
  if (name.trim().isEmpty) return '请输入优惠券名称';
  if (startTime == null || endTime == null) return '请选择优惠券日期';
  if (couponTypeWire(typePickerIndex) == null) return '请选择优惠券类型';
  if (publishCount == null || publishCount <= 0) return '请输入大于0的投放数量';
  // ★ 小程序没校验这条,但结束早于开始的券发出去就是死券。
  //   多一道前端闸不会越权,只会少一次白发。
  if (!endTime.isAfter(startTime)) return '结束时间要晚于开始时间';
  return null;
}

Future<bool?> showCouponPublishSheet(BuildContext context) =>
    // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
    showCyNativeSheet<bool>(
      context,
      detents: CyNativeSheetDetents.large,
      builder: (BuildContext context) => const _Sheet(),
    );

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet();

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _count = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  int _type = 0;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _desc.dispose();
    super.dispose();
  }

  String? get _blocker => couponFormBlocker(
    name: _name.text,
    startTime: _start,
    endTime: _end,
    typePickerIndex: _type,
    publishCount: int.tryParse(_count.text.trim()),
  );

  /// 真源 `couponForm.isDirty`:6 字段任一非默认值即算编辑过。
  bool get _dirty =>
      _name.text.isNotEmpty ||
      _count.text.trim().isNotEmpty ||
      _desc.text.isNotEmpty ||
      _start != null ||
      _end != null ||
      _type != 0;

  /// 取消(真源 `onCancel`):有草稿先问「放弃编辑？」,没有就直接退。
  Future<void> _cancel() async {
    if (_busy) return;
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bool discard = await cyConfirm(
      context,
      title: '放弃编辑？',
      content: '已填写的优惠券内容不会保存。',
      confirmText: '放弃',
      cancelText: '继续编辑',
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _pick(bool start) async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: (start ? _start : _end) ?? now,
      minimumDate: now.subtract(const Duration(days: 1)),
      maximumDate: now.add(const Duration(days: 365 * 2)),
      title: start ? '选择开始日期' : '选择结束日期',
    );
    if (d == null || !mounted) return;
    setState(() => start ? _start = d : _end = d);
  }

  Future<void> _submit() async {
    if (_busy || _blocker != null) return;
    setState(() => _busy = true);
    try {
      final String msg = await ref
          .read(couponApiProvider)
          .publish(
            name: _name.text.trim(),
            startTime: _start!,
            endTime: _end!,
            publishCount: int.parse(_count.text.trim()),
            couponType: couponTypeWire(_type)!,
            description: _desc.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      CyNativeNotice.show(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // ★ 后端原文显示。配额提示和防重提示都是可执行信息,改写就没用了;
      //   但 DioException 原文不是人话(b1-sim S6),网络类走真源文案。
      CyNativeNotice.show(context, _submitErrorText(e), isError: true);
    }
  }

  /// Exception(msg) 是 coupon_api 透传的后端原话,剥掉壳直接给用户;
  /// DioException(断网/超时/非 2xx)按真源 `getRequestErrorMessage(err,'网络错误,请重试')`
  /// 收敛 —— 不把 `DioException [bad response] …` 糊到 toast 上。
  static String _submitErrorText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = data is Map ? data['msg'] : null;
      return (msg is String && msg.trim().isNotEmpty) ? msg.trim() : '网络错误，请重试';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final BoxDecoration inputDecoration = BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
    final TextStyle? inputStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPrimary,
    );
    final TextStyle? placeholderStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPlaceholder,
    );

    // ★ 表单类 sheet **保留不透明背景**:内容按深色主题画(黑底输入框 +
    //   浅灰标签),透明后系统浅色 sheet 底会让标签看不清 —— 可读性优先,
    //   玻璃只体现在系统 sheet 的边缘与圆角上。
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('优惠券设置')),
      child: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            _FieldLabel(text: '优惠券名称', required: true),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              controller: _name,
              key: const Key('coupon-name'),
              onChanged: (_) => setState(() {}),
              placeholder: '请输入优惠券名称',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              clearButtonMode: OverlayVisibilityMode.editing,
            ),
            const SizedBox(height: CyTokens.space4),
            _FieldLabel(text: '优惠券日期', required: true),
            const SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DateBtn(
                    keyName: 'coupon-start',
                    label: '开始',
                    value: _start,
                    onTap: () => _pick(true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  child: Text(
                    '-',
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: _DateBtn(
                    keyName: 'coupon-end',
                    label: '结束',
                    value: _end,
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space4),
            _FieldLabel(text: '投放数', required: true),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              controller: _count,
              key: const Key('coupon-count'),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) => setState(() {}),
              placeholder: '请输入投放数量',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CyTokens.space4),
            _FieldLabel(text: '优惠券类型', required: true),
            const SizedBox(height: CyTokens.space2),
            _CouponTypePicker(
              value: _type,
              onChanged: (int value) => setState(() => _type = value),
            ),
            const SizedBox(height: CyTokens.space4),
            const _FieldLabel(text: '优惠券说明'),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              controller: _desc,
              key: const Key('coupon-desc'),
              minLines: 2,
              maxLines: 5,
              placeholder: '请输入优惠券说明',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
            ),
            const SizedBox(height: CyTokens.space4),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 88,
                  child: CupertinoButton(
                    key: const Key('coupon-cancel'),
                    minimumSize: const Size.fromHeight(44),
                    color: palette.actionSecondaryBg,
                    foregroundColor: palette.textPrimary,
                    onPressed: _busy ? null : _cancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CupertinoButton(
                    key: const Key('coupon-submit'),
                    minimumSize: const Size.fromHeight(44),
                    color: palette.actionPrimaryBg,
                    // 未填完 = 主按钮**降透明度的自己**,不是换一个近白底色:
                    // 原来吃 bgSubtle(浅端 #F8FAFC)在白 sheet 上等于把主 CTA
                    // 画成一个空框,反而比左边「取消」(actionSecondaryBg #EEEEEE)
                    // 更轻,主次倒置。
                    disabledColor: palette.actionPrimaryBg.withValues(
                      alpha: 0.12,
                    ),
                    // 按钮上的缺项提示是**要读的字**,不是幽灵字。
                    foregroundColor: (_busy || _blocker != null)
                        ? palette.textSecondary
                        : palette.actionPrimaryFg,
                    onPressed: (_busy || _blocker != null) ? null : _submit,
                    // ★ 按钮上直接写缺什么 —— 灰按钮不说话等于把人堵在原地。
                    child: _busy
                        ? const CupertinoActivityIndicator()
                        : Text(_blocker ?? '发布优惠券'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 真源 `.item-tit` = font-body(14)/ **text-body(=secondary)**:标签比输入值
    // 弱一档,表单层级才分得开。原来吃 textPrimary,标签和填好的值一样重。
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(color: palette.textSecondary);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: text, style: style),
          if (required)
            // 真源 `.item-tit text{color:--cy-danger}`:这是商家恒浅页,
            // 必须吃 palette 的浅端危险值,`CyTokens.statusDanger` 是暗色常量。
            TextSpan(
              text: ' *',
              style: style?.copyWith(color: palette.statusDanger),
            ),
        ],
      ),
    );
  }
}

class _CouponTypePicker extends StatelessWidget {
  const _CouponTypePicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  Future<void> _show(BuildContext context) async {
    final int? picked = await showCupertinoModalPopup<int>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('类型'),
        actions: <Widget>[
          for (int i = 0; i < kCouponTypePicker.length; i++)
            CupertinoActionSheetAction(
              key: Key('coupon-type-option-$i'),
              isDefaultAction: i == value,
              onPressed: () => Navigator.of(context).pop(i),
              child: Text(kCouponTypePicker[i]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          key: const Key('coupon-type'),
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
          alignment: Alignment.centerLeft,
          foregroundColor: palette.textPrimary,
          onPressed: () => _show(context),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(kCouponTypePicker[value])),
              const Icon(CupertinoIcons.chevron_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBtn extends StatelessWidget {
  const _DateBtn({
    required this.keyName,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String keyName;
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: CupertinoButton(
        key: Key(keyName),
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
        foregroundColor: palette.textPrimary,
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(CupertinoIcons.calendar, size: 18),
            const SizedBox(width: CyTokens.space2),
            Flexible(
              child: Text(
                // 没选就说「未选」,不显示今天 —— 默认日期会被当成已经选好了。
                value == null
                    ? '$label:未选'
                    : '$label:${value!.month}/${value!.day}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
