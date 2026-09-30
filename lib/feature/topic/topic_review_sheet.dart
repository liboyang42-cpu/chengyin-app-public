import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'topic_detail_controller.dart';

/// 评价路线(打分 + 写评价)。
///
/// ★ 为什么要从 `CupertinoActionSheet` 搬出来:小程序这一屏是**页内半屏弹层**
///   (`pages/topic/index/index.wxml` 的 `.pop-tit` 标题 + 五颗星 + `textarea` +
///   「发布评价」),而 action sheet 按 HIG 只放**用户主动发起的选项**(S4:
///   不滚动、不做表单),里面塞输入框是拿错控件 —— 键盘顶起来后既不是 sheet
///   的几何,也没有拖拽关闭。承载任意 Flutter 表单的 sheet 在桥 B1 落地前
///   走 `showCupertinoSheet`(全版本同样式,见手册 §3.4)。
///   键位/文案/判据与搬迁前一致,业务逻辑没动。
Future<void> showTopicReviewSheet(
  BuildContext context, {
  required int topicId,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.12,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _TopicReviewSheet(
              topicId: topicId,
              scrollController: scrollController,
            ),
  );
}

class _TopicReviewSheet extends ConsumerStatefulWidget {
  const _TopicReviewSheet({
    required this.topicId,
    required this.scrollController,
  });

  final int topicId;
  final ScrollController scrollController;

  @override
  ConsumerState<_TopicReviewSheet> createState() => _TopicReviewSheetState();
}

class _TopicReviewSheetState extends ConsumerState<_TopicReviewSheet> {
  final TextEditingController _controller = TextEditingController();
  int _rating = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _rating == 0 || _controller.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(topicApiProvider)
          .addReview(
            topicId: widget.topicId,
            rating: _rating,
            contents: _controller.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      // 评价是服务端事实:回来重读详情,别在本地插一条。
      ref.invalidate(topicDetailProvider(widget.topicId));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool canSubmit =
        !_busy && _rating > 0 && _controller.text.trim().isNotEmpty;
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('评价路线'),
        leading: CupertinoButton(
          key: const Key('topic-review-cancel'),
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              '点评越真实，积分越丰厚！',
              style: textTheme.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Row(
              children: List<Widget>.generate(
                5,
                (index) => CupertinoButton(
                  key: Key('topic-review-star-${index + 1}'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _rating = index + 1),
                  child: Icon(
                    index < _rating
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.star,
                    color: palette.actionPrimaryBg,
                    semanticLabel: '${index + 1} 星',
                  ),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              key: const Key('topic-review-content'),
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              placeholder: '请输入您的评价内容...',
              placeholderStyle: textTheme.bodyMedium?.copyWith(
                color: palette.textPlaceholder,
              ),
              style: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: palette.inputBgEmpty,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                border: Border.all(color: palette.borderSubtle),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('topic-review-submit'),
              minimumSize: const Size.fromHeight(44),
              color: palette.actionPrimaryBg,
              disabledColor: palette.bgSubtle,
              foregroundColor: canSubmit
                  ? palette.actionPrimaryFg
                  : palette.textPlaceholder,
              onPressed: canSubmit ? _submit : null,
              child: Text(_busy ? '发布中…' : '发布评价'),
            ),
          ],
        ),
      ),
    );
  }
}
