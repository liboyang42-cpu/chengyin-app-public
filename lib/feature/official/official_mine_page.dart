import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/official_api.dart';
import '../../data/models/official_event.dart';
import '../auth/login_gate.dart';
import 'official_controller.dart';
import 'official_publish_page.dart';

/// 我发布的官方活动 + 通知。对齐小程序 `pages/activity/official-mine`。
class OfficialMinePage extends ConsumerWidget {
  const OfficialMinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPublishedProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('我发布的'),
        // ★★ 入口本身也受**同一道闸**管:没权限的人连按钮都不该看到。
        //   只在页里挡、入口照放,等于让绝大多数人点进去撞一句权限错误。
        trailing: ref.watch(officialCanPublishProvider).value == true
            ? CupertinoButton(
                key: const Key('official-publish-entry'),
                onPressed: () => GoRouter.of(context).push('/official-publish'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                child: const Text('发一个'),
              )
            : null,
      ),
      // ★ 与 official_inbox / events / publish 同款:`CupertinoPageScaffold`
      //   不提供 `DefaultTextStyle`,`CySectionTitle` 这类 inherit 样式会落到
      //   框架的「monospace + 黄下划线」兜底上(取证截图实测,2026-09-21)。
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: async.when(
            loading: () => Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) {
              // ★ 「无官方发布权限」是**权限态不是故障**。渲染成「加载失败 + 重试」
              //   会让没权限的用户一直点重试 —— 重试多少次都不会好。
              if (e is OfficialApiException && e.isNoPermission) {
                return const StatusView(
                  message: '你没有官方发布权限',
                  sub: '这个页面只对官方运营账号开放',
                  large: true,
                );
              }
              // ★ 游客 401(HTTP 层的「要登录」)和上面那条是**两个语义层**:
              //   后端对无 token 直接回 HTTP 401,抛的是 DioException 而不是
              //   OfficialApiException,漏进兜底分支就是满屏英文堆栈(B1 报告
              //   ofc-06;同 38790273 已修的 play 域「我走过的」)。这是可恢复的
              //   登录引导,不是故障 —— 「重试」对游客永远不会好。
              if (isUnauthorizedError(e)) {
                return StatusView(
                  message: '登录后查看我发布的内容',
                  sub: '这一步需要登录,登录完会自动回到这一页。',
                  icon: Icons.lock_outline,
                  large: true,
                  retryLabel: '去登录',
                  onRetry: () async {
                    if (!await requireLogin(context, ref)) return;
                    ref.invalidate(myPublishedProvider);
                  },
                );
              }
              return StatusView(
                message: '发布记录没能加载出来',
                sub: officialErrorSub(e),
                large: true,
                onRetry: () => ref.invalidate(myPublishedProvider),
              );
            },
            data: (MyPublished data) {
              if (data.isEmpty) {
                return const StatusView(
                  message: '还没有发布过内容',
                  sub: '发布官方活动或通知后,会出现在这里',
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(myPublishedProvider),
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  children: <Widget>[
                    if (data.events.isNotEmpty) ...<Widget>[
                      const CySectionTitle('我发布的活动'),
                      const SizedBox(height: CyTokens.space2),
                      ...data.events.map(
                        (OfficialEvent e) => CyCell(
                          title: e.title,
                          subtitle: e.subtitle,
                          onTap: () => context.push('/official/${e.id}'),
                        ),
                      ),
                      const SizedBox(height: CyTokens.space4),
                    ],
                    if (data.broadcasts.isNotEmpty) ...<Widget>[
                      const CySectionTitle('我发布的通知'),
                      const SizedBox(height: CyTokens.space2),
                      ...data.broadcasts.map(
                        (OfficialBroadcast b) => CyCell(
                          title: b.title,
                          subtitle: '触达 ${b.reach} 人',
                          // 触达只是送达数;阅读/点击要问复盘端点,点进去才拉。
                          onTap: () => showCupertinoSheet<void>(
                            context: context,
                            showDragHandle: true,
                            topGap: 0.4,
                            scrollableBuilder:
                                (
                                  BuildContext context,
                                  ScrollController scrollController,
                                ) => _BroadcastStatsSheet(
                                  broadcastId: b.id,
                                  title: b.title,
                                  scrollController: scrollController,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 播报复盘浮层:`GET /api/official/broadcast/{id}/stats`。
///
/// ★ 字段名以服务端为准,这里按**标量字段逐行**渲染:已知键给中文名,
///   未知键保留原名 —— 不猜字段,也不因为字段名没见过就装作没数据。
class _BroadcastStatsSheet extends ConsumerStatefulWidget {
  const _BroadcastStatsSheet({
    required this.broadcastId,
    required this.title,
    required this.scrollController,
  });

  final int broadcastId;
  final String title;
  final ScrollController scrollController;

  @override
  ConsumerState<_BroadcastStatsSheet> createState() =>
      _BroadcastStatsSheetState();
}

class _BroadcastStatsSheetState extends ConsumerState<_BroadcastStatsSheet> {
  static const Map<String, String> _kLabels = <String, String>{
    'reach': '触达人数',
    'read': '阅读人数',
    'reads': '阅读人数',
    'click': '点击人数',
    'clicks': '点击人数',
  };

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> stats = await ref
          .read(officialApiProvider)
          .broadcastStats(widget.broadcastId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<MapEntry<String, Object>> rows = _stats.entries
        .where(
          (MapEntry<String, dynamic> e) =>
              e.value is num || e.value is String || e.value is bool,
        )
        .map(
          (MapEntry<String, dynamic> e) =>
              MapEntry<String, Object>(e.key, e.value as Object),
        )
        .toList();
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(middle: const Text('播报复盘')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(CyTokens.pageX),
          children: <Widget>[
            const SizedBox(height: CyTokens.space1),
            // 条目名压成 footnote 档:导航标题已说「播报复盘」,这行只是
            // 「看的是哪条」,和分组卡抢字重就成层级倒置。
            Text(
              widget.title,
              style: text.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: CyTokens.space3),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_error != null) ...<Widget>[
              Text(
                _error!,
                key: const Key('official-broadcast-stats-error'),
                // 浅色语境(商家视角)下用浅色档的 red,不用暗色常量。
                style: text.bodySmall?.copyWith(color: palette.statusDanger),
              ),
              const SizedBox(height: CyTokens.space2),
              // 成件按钮(内容宽、左对齐),不是居中裸文字。
              CyNativeButton(
                key: const Key('official-broadcast-stats-retry'),
                label: '重试',
                role: CyNativeButtonRole.secondary,
                onPressed: _load,
              ),
            ] else if (rows.isEmpty)
              Text(
                '这次播报还没有可看的数据',
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
              )
            else
              // 与「合作方信誉」浮层同款:标量行进**一个**分组卡,
              // label 左 / 值右,行间发丝线。
              Container(
                decoration: BoxDecoration(
                  color: palette.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  // 暗端=1px 描边,浅端(商家)=白卡+投影,取 token 分工。
                  border: Border.all(
                    color: palette.cardBorder,
                    width: palette.cardBorder == Colors.transparent ? 0 : 1,
                  ),
                  boxShadow: palette.cardShadow,
                ),
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < rows.length; i++) ...<Widget>[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: CyTokens.space3),
                          child: Container(
                            height: 1,
                            color: palette.borderSubtle,
                          ),
                        ),
                      _statRow(rows[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(MapEntry<String, Object> e) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      alignment: Alignment.center,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              _kLabels[e.key] ?? e.key,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            '${e.value}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
