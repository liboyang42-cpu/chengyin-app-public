import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import 'chat_card.dart';
import '../../l10n/strings.dart';

/// 系统卡的「处理结果」面板 —— 小程序 im/chat 的 `cy-sheet title="处理结果"`
/// (`reviewResult`),承载审核回执的 taskId / bizId / outcome / reason / followUp。
///
/// §3.4:这种「标题 + 若干行任意文本」的 sheet,现有两个原生包都只吃可点行,
/// 撑不住自由文案 —— 桥落地前按手册走 `showCupertinoSheet`(自绘、无玻璃、
/// iOS 全版本一致;举报面板同一条口径 `core/moderation/report_sheet.dart`)。
///
/// ⚠️ 空字段不渲 —— 小程序那边四行都渲,空值就是一行空白;空白行不是信息,
///   而「审核任务 # · 业务 #」这种半截文案更像出错。
Future<void> showChatReviewResult(BuildContext context, ChatCardResult result) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.26,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        _ReviewSheet(result: result, scrollController: controller),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.result, required this.scrollController});

  final ChatCardResult result;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    // 半截的「审核任务 # · 业务 #22」看起来像出错 —— 只拼拿得到的部分
    // (空字段在小程序那边就是一行空白,空白不是信息)。
    final List<String> ids = <String>[
      if (result.taskId.isNotEmpty) stringsOf(context).imRemainingTask(result.taskId),
      if (result.bizId.isNotEmpty) stringsOf(context).imRemainingBusiness(result.bizId),
    ];
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
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
                    stringsOf(context).imRemainingReviewTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: stringsOf(context).imRemainingCloseReview,
                  button: true,
                  child: CupertinoButton(
                    key: const Key('review-result-close'),
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
            if (ids.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                ids.join(' · '),
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (result.outcome.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Text(
                result.outcome,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ],
            if (result.reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2_5),
              Text(
                stringsOf(context).imRemainingReason(result.reason),
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ],
            if (result.followUp.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2_5),
              Text(
                result.followUp,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
