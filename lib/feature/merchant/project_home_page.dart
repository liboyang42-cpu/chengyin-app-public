import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';

/// 项目主页:同一条路线上的主办方和承接方落到同一个页面。
///
/// ★ 后端注释说明了它为什么存在:在此之前这些数据散在**五个接口**里
///   (topic/info-to-merchant、registration/merchant/info、coop/candidates、
///    coop/list、merchant/upcoming-runs),前端要打五次才拼得出一屏。
///
/// ★★ `host` 与 `join` **可以同时存在** —— 既主办又报名过的人两块都有。
///   `role` 只说哪个是主身份,**不是二选一**。
///   写成 if/else 的话,那个人会看不到自己的另一半。
final projectHomeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int?>((ref, topicId) {
      return ref.read(myProjectApiProvider).projectHome(topicId: topicId);
    });

class ProjectHomePage extends ConsumerWidget {
  const ProjectHomePage({super.key, this.topicId, this.scope});

  final int? topicId;

  /// 商家控制台那条动线带的归属标记(`/project/home/:id?scope=MERCHANT`)。
  /// 与小程序 `merchantinfo` 的 `operationScope` 是同一个东西:店员代店主操作时,
  /// 供给复核要按**店主**的身份发,服务端 `resolveProjectOwner` 读的就是它。
  final String? scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectHomeProvider(topicId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('项目主页')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const CySkeleton(),
            error: (Object e, StackTrace st) => StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: '项目主页没读出来',
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () => ref.invalidate(projectHomeProvider(topicId)),
            ),
            data: (Map<String, dynamic> d) => _body(context, ref, d),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Map<String, dynamic> d) {
    final Map<String, dynamic>? topic = d['topic'] as Map<String, dynamic>?;
    final Map<String, dynamic>? host = d['host'] as Map<String, dynamic>?;
    final Map<String, dynamic>? join = d['join'] as Map<String, dynamic>?;

    if (topic == null && host == null && join == null) {
      return const StatusView(
        icon: CupertinoIcons.tray,
        message: '还没有进行中的项目',
        sub: '发布主题或报名承接后,这里会显示招商进度与玩家名单',
        large: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        if (topic != null) _topicCard(context, topic),
        // ★ 两块都渲染,不是 if/else —— 既主办又报名过的人两块都该看到。
        if (host != null) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          _hostCard(context, ref, host, topic),
        ],
        if (join != null) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          _joinCard(context, join),
        ],
      ],
    );
  }

  Widget _topicCard(BuildContext context, Map<String, dynamic> topic) {
    final TextTheme t = Theme.of(context).textTheme;
    return _shell(
      context,
      title: (topic['name'] ?? topic['title'] ?? '未命名主题').toString(),
      children: <Widget>[
        if ((topic['city'] ?? '').toString().isNotEmpty)
          Text(
            topic['city'].toString(),
            style: t.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _hostCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> host,
    Map<String, dynamic>? topic,
  ) {
    final Map<String, dynamic>? recruit =
        host['recruit'] as Map<String, dynamic>?;
    // 后端 `host.players` 是 `{paidCount}` 这个对象,不是名单数组
    // (小程序 `merchantinfo.js:1507,1543`:`host.players || {}` → `players.paidCount`)。
    // 按数组取 length 在真机上是类型转换异常 —— 整张「我主办的」卡都渲染不出来。
    final Map<String, dynamic>? players =
        host['players'] as Map<String, dynamic>?;
    final int paidCount = (players?['paidCount'] as num?)?.toInt() ?? 0;
    final TextTheme t = Theme.of(context).textTheme;

    int n(Object? v) => v is num ? v.toInt() : 0;

    return _shell(
      context,
      title: '我主办的',
      children: <Widget>[
        if (recruit != null) ...<Widget>[
          // 招商进度用后端给的三个数,不自己算 —— 「已接/在等」的口径
          // 在 service 里(pendingCount 同时含待审报名与待确认邀约)。
          Text(
            '站点 ${n(recruit['nodeFilled'])} / ${n(recruit['nodeTotal'])} 已有人接'
            '${n(recruit['pendingCount']) > 0 ? ',还有 ${n(recruit['pendingCount'])} 家在等确认' : ''}',
            style: t.bodyMedium,
          ),
          const SizedBox(height: CyTokens.space2),
        ],
        // ★ 名单给的是「谁要来」,不是销量数字 —— 后端注释明确说了
        //   「给名单不给统计口径的分析」。所以这里只做入口,不在这儿报数。
        CyNativeButton(
          onPressed: () => GoRouter.of(context).push(
            topicId == null ? '/project/players' : '/project/players/$topicId',
          ),
          label: paidCount > 0 ? '看玩家名单($paidCount 人)' : '看玩家名单',
          role: CyNativeButtonRole.secondary,
        ),
        // 章节承接的审核与邀请是**按主题**的,没有 topicId 就没有可审的对象 ——
        // 摆一个点进去必然空手的入口不如不摆。
        if (topicId != null) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            key: const Key('project-host-chapter-applications'),
            onPressed: () => GoRouter.of(
              context,
            ).push('/merchant/topic/$topicId/applications'),
            label: '审商家承接申请 / 邀商家',
            role: CyNativeButtonRole.secondary,
          ),
        ],
        // 30 天供给复核:只有圈层实例(`circleThemeCode` 非空)才有这一块。
        // 同样要 topicId —— 复核是按实例发的,没有实例就无从复核。
        if (topicId != null &&
            (topic?['circleThemeCode'] ?? '')
                .toString()
                .isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _CircleReviewSection(
            topicId: topicId!,
            topic: topic!,
            scope: scope,
          ),
        ],
      ],
    );
  }

  Widget _joinCard(BuildContext context, Map<String, dynamic> join) {
    final Map<String, dynamic>? reg =
        join['registration'] as Map<String, dynamic>?;
    final TextTheme t = Theme.of(context).textTheme;
    return _shell(
      context,
      title: '我承接的',
      children: <Widget>[
        Text(
          reg == null ? '你报名过这个主题' : (reg['addressName'] ?? '我的门店').toString(),
          style: t.bodyMedium,
        ),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          onPressed: () => GoRouter.of(context).push('/merchant/registrations'),
          label: '查看我的报名',
          role: CyNativeButtonRole.secondary,
        ),
      ],
    );
  }

  Widget _shell(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: t.titleSmall),
          const SizedBox(height: CyTokens.space2),
          ...children,
        ],
      ),
    );
  }
}

/// 30 天供给复核。
///
/// 小程序 `pages/topic/components/project-host/index.wxml:92-100` +
/// `merchantinfo.js:1844`(`reviewCircleSupplies`)。状态行取
/// `/api/project/home` 的 `topic.circleReviewedAt` —— 没有就说「尚未完成」,
/// **不拿今天兜底**:那会把「从没复核过」渲染成「刚复核过」。
///
/// ★ 失败原文透传:后端那句「少于 3 家 / 资料过期 / 商家重复时不会刷新」
///   是复核规则的正常回话,不是可以重试的故障(`page_parity_api.dart:55`)。
class _CircleReviewSection extends ConsumerStatefulWidget {
  const _CircleReviewSection({
    required this.topicId,
    required this.topic,
    this.scope,
  });

  final int topicId;
  final Map<String, dynamic> topic;

  /// 店员代店主操作时带的归属标记,原样进提交体(服务端 `resolveProjectOwner`)。
  final String? scope;

  @override
  ConsumerState<_CircleReviewSection> createState() =>
      _CircleReviewSectionState();
}

class _CircleReviewSectionState extends ConsumerState<_CircleReviewSection> {
  bool _reviewing = false;

  Future<void> _review() async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      await ref
          .read(pageParityApiProvider)
          .reviewCircleInstance(
            topicId: widget.topicId,
            scope: widget.scope,
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '供给复核已更新');
      ref.invalidate(projectHomeProvider(widget.topicId));
    } on Exception catch (error) {
      if (!mounted) return;
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[project-home] 供给复核失败: $error');
      CyNativeNotice.show(
        context,
        friendlyOrBackendMessage(error, fallback: '供给复核没有提交成功，请稍后重试'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String reviewedAt = (widget.topic['circleReviewedAt'] ?? '')
        .toString()
        .trim();
    final String status = reviewedAt.isEmpty
        ? '尚未完成城市供给复核'
        : '${reviewedAt.length > 10 ? reviewedAt.substring(0, 10) : reviewedAt} 已复核';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('30天供给复核', style: t.titleSmall)),
            Text(
              status,
              style: t.labelSmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '系统会重新校验3—4家当前供给；少于3家、资料过期或商家重复时不会刷新。',
          style: t.bodySmall?.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          key: const Key('project-host-circle-review'),
          onPressed: _reviewing ? null : _review,
          label: '确认本实例供给已复核',
          role: CyNativeButtonRole.secondary,
        ),
      ],
    );
  }
}
