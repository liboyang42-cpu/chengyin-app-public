import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/models/square_post.dart';
import '../auth/login_gate.dart';

/// 广场主题模板的「改编同款」入口。列表与详情共用一条真链。
class SquareTopicTemplateRemix extends ConsumerStatefulWidget {
  const SquareTopicTemplateRemix({super.key, required this.post});

  final SquarePost post;

  @override
  ConsumerState<SquareTopicTemplateRemix> createState() =>
      _SquareTopicTemplateRemixState();
}

class _SquareTopicTemplateRemixState
    extends ConsumerState<SquareTopicTemplateRemix> {
  bool _busy = false;

  Future<void> _remix() async {
    if (_busy || !widget.post.canRemixTopicTemplate) return;
    if (!await requireLogin(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      final int copiedTopicId = await ref
          .read(squareApiProvider)
          .remixTopicTemplate(widget.post.sportTopicId!);
      if (!mounted) return;
      context.push('/publish/pro?id=$copiedTopicId');
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.post.canRemixTopicTemplate) return const SizedBox.shrink();
    final String title = (widget.post.sportName ?? '').trim().isEmpty
        ? '主题模板'
        : widget.post.sportName!.trim();
    final bool usesLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final Widget summary = Row(
      children: <Widget>[
        if ((widget.post.sportCover ?? '').trim().isNotEmpty) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            child: Image.network(
              widget.post.sportCover!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 56,
                height: 56,
                child: Icon(CupertinoIcons.photo),
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space2_5),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: CyTokens.space1),
              const Text(
                '复制为你的草稿后再编辑',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final Widget action = CyNativeButton(
      key: const Key('square-topic-template-remix'),
      label: _busy ? '正在创建副本…' : '改编同款',
      onPressed: _busy ? null : _remix,
      loading: _busy,
      role: CyNativeButtonRole.secondary,
      icon: const CyNativeButtonIcon(
        sfSymbol: 'arrow.triangle.2.circlepath',
        fallback: CupertinoIcons.arrow_2_circlepath,
      ),
    );
    return Container(
      key: const Key('square-topic-template-card'),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: usesLargeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                summary,
                const SizedBox(height: CyTokens.space2),
                action,
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: summary),
                const SizedBox(width: CyTokens.space2),
                action,
              ],
            ),
    );
  }
}
