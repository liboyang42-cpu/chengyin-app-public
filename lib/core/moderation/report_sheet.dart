import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/models/community_report_reason.dart';
import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';
import '../widgets/cy_native_sheet.dart';

/// 旧圈子/私信入口的稳定展示合同；专业广场改由后端版本化策略驱动。
const List<String> kReportReasons = <String>[
  '含有违法违规内容',
  '色情低俗',
  '人身攻击或骚扰',
  '虚假信息或欺诈',
  '侵犯他人权益',
  '其他',
];

/// 举报确认弹层。确认后回**选中的理由**,取消回 null。
///
/// ★ Apple 审核指南 1.2:UGC 应用**必须**提供举报入口。
///
/// ⚠️ 原来这里只回 `true` —— 用户明明选了理由,却在返回时被丢掉了。
///   理由本身就是审核要看的信息，界面收了就不能在半路丢掉。
Future<String?> showReportSheet(
  BuildContext context, {
  required String targetLabel,
}) async {
  return (await showCommunityReportSheet(
    context,
    targetLabel: targetLabel,
    reasons: kReportReasons
        .map(
          (String label) => CommunityReportReason(
            CommunityReportReason.codeForLabel(label),
            label,
          ),
        )
        .toList(growable: false),
  ))?.label;
}

Future<CommunityReportReason?> showCommunityReportSheet(
  BuildContext context, {
  required String targetLabel,
  required List<CommunityReportReason> reasons,
  Widget Function(ValueChanged<bool>)? supplementBuilder,
}) {
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  return showCyNativeSheet<CommunityReportReason>(
    context,
    builder: (BuildContext context) => _ReportSheet(
      targetLabel: targetLabel,
      reasons: reasons,
      supplementBuilder: supplementBuilder,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.targetLabel,
    required this.reasons,
    this.supplementBuilder,
  });

  final String targetLabel;
  final List<CommunityReportReason> reasons;
  final Widget Function(ValueChanged<bool>)? supplementBuilder;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  CommunityReportReason? _reason;
  bool _blocked = false;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      // 原生承载时透明，透出系统 sheet 背景(S3)。
      backgroundColor: isCyNativeSheet(context)
          ? Colors.transparent
          : palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '举报${widget.targetLabel}',
                    style: textTheme.titleLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: '关闭举报',
                  button: true,
                  child: CupertinoButton(
                    key: const Key('report-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: palette.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const ExcludeSemantics(
                      child: Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              '我们会尽快审核。审核期间该内容仍可能可见 —— 这是为了避免误报直接下架。',
              style: textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            RadioGroup<CommunityReportReason>(
              groupValue: _reason,
              onChanged: (CommunityReportReason? value) =>
                  setState(() => _reason = value),
              child: Column(
                children: widget.reasons.map((CommunityReportReason reason) {
                  final bool selected = reason == _reason;
                  return Semantics(
                    selected: selected,
                    button: true,
                    label: reason.label,
                    child: CupertinoButton(
                      key: Key('report-reason-${reason.label}'),
                      minimumSize: const Size.fromHeight(52),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      foregroundColor: palette.textPrimary,
                      onPressed: () => setState(() => _reason = reason),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              reason.label,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          ExcludeSemantics(
                            child: CupertinoRadio<CommunityReportReason>(
                              value: reason,
                              activeColor: palette.brand,
                              useCheckmarkStyle: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            if (widget.supplementBuilder != null)
              widget.supplementBuilder!((blocked) {
                if (mounted) setState(() => _blocked = blocked);
              }),
            Semantics(
              button: true,
              enabled: _reason != null && !_blocked,
              child: CupertinoButton(
                key: const Key('report-submit'),
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                color: palette.actionPrimaryBg,
                disabledColor: palette.bgSubtle,
                foregroundColor: _reason == null
                    ? palette.textPlaceholder
                    : palette.actionPrimaryFg,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                // 没选原因就不给提交 —— 空举报对审核台没有信息量。
                onPressed: _reason == null || _blocked
                    ? null
                    : () => Navigator.of(context).pop(_reason),
                child: const Text('提交举报'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
