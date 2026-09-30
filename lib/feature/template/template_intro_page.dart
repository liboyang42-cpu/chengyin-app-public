import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/publish_draft.dart';
import '../auth/login_gate.dart';
import 'template_creation_navigation.dart';

final templateIntroCardsProvider =
    FutureProvider.autoDispose<List<PublishTemplate>>((Ref ref) async {
      final PublishTemplateHomeData home = await ref
          .watch(publishApiProvider)
          .templateHomeSections();
      final List<PublishTemplate> pool = home.recommended.isNotEmpty
          ? home.recommended
          : home.hot.isNotEmpty
          ? home.hot
          : home.latest;
      return pool.take(3).toList(growable: false);
    });

/// 模板创建第 0 页。与小程序一样：真实卡片可缺省，但不拦创建。
class TemplateIntroPage extends ConsumerWidget {
  const TemplateIntroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PublishTemplate>> cards = ref.watch(
      templateIntroCardsProvider,
    );
    return TemplateIntroView(
      cards: cards.value ?? <PublishTemplate>[],
      // 真源 wxml 是 if/elif/elif/else 四态:有卡片先画卡片,再依次 载 → 错 → 空。
      // 三个标记都往下传,由 View 按同一顺序择一渲染。
      cardsLoading: cards.isLoading,
      cardsError: cards.hasError ? _cardsReason(cards.error) : '',
      onRetryCards: () => ref.invalidate(templateIntroCardsProvider),
      // redirectTo 语义：编辑器返回时不再经过引导页。
      //
      // ★ 出口先过登录门禁:「开始创建」与「跳过」都 replace 到 `/template/new`,
      //   而那是整页需登录路由 —— 游客态会被守卫**静默换成首页**,创建流程第 0 步
      //   就断掉(2026-09-18 模拟器实拍 t12→t13)。口径与「发布 FAB」一致:
      //   先弹登录弹窗,登完留在本页继续。
      onExitIntro: (String route) async {
        if (!await requireLogin(context, ref)) return;
        if (!context.mounted) return;
        replaceTemplateCreationStep(context, route);
      },
    );
  }
}

/// 真源 `cy-inline-error` 的 sub = `getRequestErrorMessage(res, 兜底句)`:
/// 后端 msg 是人话就透出;dio 的传输层错误自带英文机器话
/// (`DioException [connection error]…`),播给用户等于没说话,换真源的兜底句。
String _cardsReason(Object? error) {
  final String raw = (error ?? '')
      .toString()
      .replaceFirst('Exception: ', '')
      .trim();
  if (raw.isEmpty || raw.startsWith('DioException')) {
    return '精选示例加载失败，请重试';
  }
  return raw;
}

/// 路由与数据无关的公开布局缝，用于锁定模块顺序与返回落点。
class TemplateIntroView extends StatelessWidget {
  const TemplateIntroView({
    super.key,
    required this.cards,
    required this.onExitIntro,
    this.cardsLoading = false,
    this.cardsError = '',
    this.onRetryCards,
  });

  final List<PublishTemplate> cards;
  final ValueChanged<String> onExitIntro;

  /// 卡堆舞台的载/错态(真源 `ti-stage--state`)。cards 非空时两者都不看。
  final bool cardsLoading;
  final String cardsError;
  final VoidCallback? onRetryCards;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        trailing: CupertinoButton(
          key: const Key('template-intro-skip'),
          onPressed: () => onExitIntro('/template/new'),
          minimumSize: const Size.square(44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
          child: const Text('跳过'),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              CyTokens.space4,
            ),
            child: Column(
              children: <Widget>[
                if (cards.isNotEmpty)
                  SizedBox(
                    key: const Key('template-intro-card-stack'),
                    height: 300,
                    child: _TemplateCardStack(cards: cards),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: _IntroStageState(
                      loading: cardsLoading,
                      error: cardsError,
                      onRetry: onRetryCards,
                    ),
                  ),
                if (cards.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 18,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.textPrimary,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusLg,
                          ),
                        ),
                      ),
                      for (int i = 0; i < 2; i++) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.borderStrong,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const Spacer(),
                Text(
                  '把你玩过的一段路',
                  textAlign: TextAlign.center,
                  // 真源 --cy-font-page-title(58rpx = 29)→ 梯级最近档 Title1 28(T2);
                  // T3:强调用 bold(700),w800 属堆重。
                  style: CyType.title1.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '做成别人也能走的玩法',
                  textAlign: TextAlign.center,
                  style: CyType.title1.copyWith(color: p.textSecondary),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: CyNativeButton(
                    key: const Key('template-intro-create'),
                    onPressed: () => onExitIntro('/template/new'),
                    label: '开始创建',
                    width: double.infinity,
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

/// 卡堆位置的 载 / 错 / 空 三态。
///
/// 真源 `ti-stage--state` 同样是**定高**舞台(560rpx):三种状态共用一个块,
/// 状态切换时下面的主张文案不跳。空态文案是真源原文
/// 「暂时没有精选示例，你仍可直接创建自己的节点玩法。」——缺省不拦创建。
class _IntroStageState extends StatelessWidget {
  const _IntroStageState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      // 真源 `<cy-skeleton type="card" count="3" />`。
      return const CySkeleton(type: CySkeletonType.card, count: 3);
    }
    if (error.isNotEmpty) {
      return StatusView(
        key: const Key('template-intro-cards-error'),
        message: '精选示例暂未加载',
        sub: error,
        onRetry: onRetry,
      );
    }
    final CyPalette p = CyPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space6),
        child: Text(
          '暂时没有精选示例，你仍可直接创建自己的节点玩法。',
          key: const Key('template-intro-cards-empty'),
          textAlign: TextAlign.center,
          style: CyType.subhead.copyWith(color: p.textSecondary),
        ),
      ),
    );
  }
}

class _TemplateCardStack extends StatelessWidget {
  const _TemplateCardStack({required this.cards});

  final List<PublishTemplate> cards;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Color> accents = <Color>[
      scheme.error,
      scheme.tertiary,
      scheme.primary,
    ];
    final List<double> angles = <double>[-0.22, -0.03, 0.20];
    final List<Offset> offsets = <Offset>[
      const Offset(-58, 22),
      Offset.zero,
      const Offset(58, -24),
    ];
    final List<int> order = cards.length >= 3
        ? <int>[0, 2, 1]
        : List<int>.generate(cards.length, (int i) => i);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (final int index in order)
          Transform.translate(
            offset: offsets[index],
            child: Transform.rotate(
              angle: angles[index],
              child: _IntroCard(
                template: cards[index],
                accent: accents[index % accents.length],
              ),
            ),
          ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.template, required this.accent});

  final PublishTemplate template;
  final Color accent;

  String get _categoryName {
    final Object? categories = template.raw['sysCategoryList'];
    if (categories is List && categories.isNotEmpty) {
      final Object? first = categories.first;
      if (first is Map) {
        final String value = (first['categoryName'] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '节点玩法';
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      width: 180,
      height: 250,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.bgElevated,
        border: Border.all(color: accent, width: 4),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: accent,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space2,
              vertical: CyTokens.space1,
            ),
            child: Text(
              _categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // --cy-font-caption(22rpx = 11)与梯级 Caption2 同值,换梯级名字。
              style: CyType.caption2.copyWith(
                color: p.textInverse,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: template.imgUrl.trim().isEmpty
                ? _CoverFallback(title: template.title)
                : Image.network(
                    template.imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _CoverFallback(title: template.title),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return ColoredBox(
      color: p.bgSurfaceStrong,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.rotate(
                angle: math.pi / 18,
                child: const Icon(CupertinoIcons.map, size: 34),
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                // 真源 `cy-cover-fallback` 兜底文字 = card-title(32rpx = 16)/700
                // → Headline 17 Semibold(T2/T3);原来吃 Material 默认 14。
                style: CyType.headline.copyWith(color: p.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
