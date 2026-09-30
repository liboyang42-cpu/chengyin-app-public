import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

/// 表单向导骨架(对齐小程序 apply/create 的「分步向导」形态):
/// 大标题 + 步骤点 + 可滚动内容 + 底部「返回/下一步(提交)」条。
///
/// 返回语义由调用方决定:第 1 步返回 = 离开本页,其余 = 回上一步。
class ClubStepScaffold extends StatelessWidget {
  const ClubStepScaffold({
    super.key,
    required this.title,
    required this.step,
    required this.stepCount,
    required this.backLabel,
    required this.onBack,
    required this.nextLabel,
    required this.canNext,
    required this.busy,
    required this.onNext,
    required this.child,
  });

  final String title;
  final int step;
  final int stepCount;
  final String backLabel;
  final VoidCallback onBack;
  final String nextLabel;
  final bool canNext;
  final bool busy;
  final VoidCallback onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(title),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < stepCount; i++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(
                            right: i == stepCount - 1 ? 0 : CyTokens.space1,
                          ),
                          decoration: BoxDecoration(
                            // 已走过的步骤用主文字色,当前之后的步骤用弱底。
                            color: i < step
                                ? CyTokens.textPrimary
                                : CyTokens.bgSubtle,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  child: child,
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.pageX,
                    CyTokens.space3,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.bgSurface,
                    border: Border(
                      top: BorderSide(color: CyTokens.borderSubtle, width: 1),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          minimumSize: const Size.fromHeight(44),
                          color: CyTokens.actionSecondaryBg,
                          foregroundColor: CyTokens.textPrimary,
                          onPressed: busy ? null : onBack,
                          child: Text(backLabel),
                        ),
                      ),
                      const SizedBox(width: CyTokens.space3),
                      Expanded(
                        flex: 2,
                        child: CupertinoButton(
                          minimumSize: const Size.fromHeight(44),
                          color: CyTokens.actionPrimaryBg,
                          disabledColor: CyTokens.bgSubtle,
                          foregroundColor: (busy || !canNext)
                              ? CyTokens.textPlaceholder
                              : CyTokens.actionPrimaryFg,
                          onPressed: (busy || !canNext) ? null : onNext,
                          child: busy
                              ? const CupertinoActivityIndicator()
                              : Text(nextLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
