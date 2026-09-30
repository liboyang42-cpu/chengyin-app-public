import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/scan_result.dart';

/// `AppleLiquidSheet` 在已展示时对第二次 show 直接回 `true`。
/// 在整个核销第二步上复用同一 Future，既避免把该 `true`
/// 误解成“用户关闭且未选”，也避免同票并发提交两次。
Future<String>? _activeScanChoiceResolution;

/// 处理三态结果。★ **needsChoice 不是失败** ——
/// 它带着候选列表,要让商家选一个再提交第二步。
/// 当作失败抛掉,核销就是个死胡同(见 scan_result.dart 的注释)。
Future<String> resolveScanChoice({
  required BuildContext context,
  required WidgetRef ref,
  required ScanResult result,
  required String code,
}) async {
  final ScanResult r = result;
  if (r.outcome == ScanOutcome.redeemed) return r.message;
  if (!r.needsChoice) throw Exception(r.message);

  if (r.choices.isEmpty) {
    // 后端说要选,却没给候选 —— 说实话,别摆一个空面板让人干瞪眼。
    throw Exception('${r.message}(这次没有拿到可选项,请联系平台)');
  }

  final Future<String>? active = _activeScanChoiceResolution;
  if (active != null) return active;

  final Future<String> resolution = _resolvePendingScanChoice(
    context: context,
    ref: ref,
    result: r,
    code: code,
  );
  _activeScanChoiceResolution = resolution;
  try {
    return await resolution;
  } finally {
    if (identical(_activeScanChoiceResolution, resolution)) {
      _activeScanChoiceResolution = null;
    }
  }
}

Future<String> _resolvePendingScanChoice({
  required BuildContext context,
  required WidgetRef ref,
  required ScanResult result,
  required String code,
}) async {
  final ScanChoice? picked = await _showScanChoice(
    context: context,
    message: result.message,
    choices: result.choices,
  );
  // 商家关掉面板 = 没选 = 这次核销没做,如实说,不要伪装成失败。
  if (picked == null) throw Exception('已取消,这张票还没核销');

  final ScanResult second = result.choiceKind == 'station'
      // ⚠️ 站点这一步传的是**中标记录 ID**,不是站点 id(见 API 注释)。
      ? await ref
            .read(registrationApiProvider)
            .scanStation(code: code, registrationMerchantId: picked.id)
      : await ref
            .read(registrationApiProvider)
            .scanChapter(code: code, chapterId: picked.id);
  if (second.outcome == ScanOutcome.redeemed) return second.message;
  throw Exception(second.message);
}

Future<ScanChoice?> _showScanChoice({
  required BuildContext context,
  required String message,
  required List<ScanChoice> choices,
}) async {
  ScanChoice? nativeSelection;
  try {
    final bool shownNatively = await AppleLiquidSheet.showSheet(
      heightFraction: CyTokens.iosSheetHeightFraction,
      // 候选是高频、短任务，不额外缩放背景；保留系统 Sheet
      // 转场，避免自定义缩放绕过 Reduce Motion。
      backgroundZoomScale: 1,
      content: AppleLiquidSheetContent(
        title: message,
        doneSemanticLabel: '关闭',
        sections: <AppleLiquidSheetSection>[
          AppleLiquidSheetSection(
            rows: choices
                .map(
                  (ScanChoice choice) => AppleLiquidSheetRow.button(
                    title: choice.label,
                    semanticLabel: choice.label,
                    dismissesSheet: true,
                    style: const AppleLiquidSheetButtonStyle(
                      pressedScale: 1,
                      pressAnimationDuration: 0,
                    ),
                    onPressed: () => nativeSelection = choice,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
      scrollContext: context,
    );
    if (shownNatively) return nativeSelection;
  } on MissingPluginException {
    // 原生包未注册时回退 Flutter Sheet，核销不中断。
  } on PlatformException {
    // 原生层当下无法展示时保留原交互。
  }

  if (!context.mounted) return null;
  return showCupertinoModalPopup<ScanChoice>(
    context: context,
    builder: (BuildContext sheetContext) => CupertinoActionSheet(
      title: Text(message),
      actions: <CupertinoActionSheetAction>[
        for (final ScanChoice choice in choices)
          CupertinoActionSheetAction(
            key: Key('scan-choice-${choice.id}'),
            onPressed: () => Navigator.of(sheetContext).pop(choice),
            child: Text(choice.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: const Text('取消'),
      ),
    ),
  );
}
