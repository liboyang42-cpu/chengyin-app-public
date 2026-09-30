// 官方活动列表 —— 对应小程序 pages/activity/list。
//
// ⚠️ 那页的路由名叫 `activity/list`,但它**不是**活动目录 ——
//   `utils/scene-registry.js:27` 写着 `title: '官方活动'`。
//   App 的 /activities 是另一回事(主题/局的目录,走 /api/activity/list)。
//   两边同名不同物,我一开始就是照名字对错了。
//
// ★ App 此前有官方活动的**详情 / 收件箱 / 我发布的 / 发布页**,
//   唯独没有**列表** —— 玩家根本发现不了官方活动。
//
// ★ 四档与筛选逐条照小程序 applyFilter(index.js:205-214):
//   进行中(live)/ 即将(status==1)/ 已结束(status>=5)/ 我的(my-events),
//   关键词是**前端过滤**(标题/副标/城市),不发后端。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity_status.dart';
import '../../data/models/official_event.dart';
import '../auth/login_gate.dart';
import 'official_controller.dart' show officialErrorSub;
import 'official_publish_page.dart';

final officialEventsProvider = FutureProvider.autoDispose<List<OfficialEvent>>(
  (Ref ref) => ref.watch(officialApiProvider).events(),
);

/// 我报名的。★ 单独一个 provider —— 小程序也是两条请求各自成败,
/// 合成一个的话公开列表挂了会把「我的」也一起打红。
final myOfficialEventsProvider =
    FutureProvider.autoDispose<List<OfficialEvent>>(
      (Ref ref) => ref.watch(officialApiProvider).myEvents(),
    );

/// 关键词过滤。★ 与小程序同三个字段:标题 / 副标 / 城市。
List<OfficialEvent> filterOfficialEvents(
  List<OfficialEvent> rows,
  String keyword,
) {
  final String kw = keyword.trim().toLowerCase();
  if (kw.isEmpty) return rows;
  bool hit(String? s) => (s ?? '').toLowerCase().contains(kw);
  return rows
      .where(
        (OfficialEvent e) => hit(e.title) || hit(e.subtitle) || hit(e.city),
      )
      .toList();
}

/// 丢掉缺 id 或缺标题的行。
///
/// ★ 小程序有同一道闸(`_isCompleteEvent`)。留着的话列表里会出现
///   一张点不开的空卡 —— 而用户看不出它为什么点不开。
List<OfficialEvent> completeOnly(List<OfficialEvent> rows) => rows
    .where((OfficialEvent e) => e.id > 0 && e.title.trim().isNotEmpty)
    .toList();

class OfficialEventsPage extends ConsumerStatefulWidget {
  const OfficialEventsPage({super.key, this.onOpenMine, this.onOpenInbox});

  final VoidCallback? onOpenMine;
  final VoidCallback? onOpenInbox;

  @override
  ConsumerState<OfficialEventsPage> createState() => _State();
}

class _State extends ConsumerState<OfficialEventsPage> {
  int _tab = 0;
  String _kw = '';

  static const List<({String key, String label})> _tabs =
      <({String key, String label})>[
        (key: 'live', label: '进行中'),
        (key: 'upcoming', label: '即将'),
        (key: 'ended', label: '已结束'),
        (key: 'mine', label: '我的'),
      ];

  List<OfficialEvent> _visibleRows(List<OfficialEvent> all, bool mine) {
    return filterOfficialEvents(
      mine
          ? completeOnly(all)
          : completeOnly(all)
                .where(
                  (OfficialEvent e) =>
                      activityInBucket(e.status, ActivityBucket.values[_tab]),
                )
                .toList(),
      _kw,
    );
  }

  void _openMine() {
    final VoidCallback? callback = widget.onOpenMine;
    if (callback != null) {
      callback();
      return;
    }
    context.push('/official-mine');
  }

  void _openInbox() {
    final VoidCallback? callback = widget.onOpenInbox;
    if (callback != null) {
      callback();
      return;
    }
    context.push('/official-inbox');
  }

  @override
  Widget build(BuildContext context) {
    final bool mine = _tab == 3;
    final AsyncValue<List<OfficialEvent>> async = ref.watch(
      mine ? myOfficialEventsProvider : officialEventsProvider,
    );
    final bool canPublish = ref.watch(officialCanPublishProvider).value == true;
    final bool hasData = async is AsyncData<List<OfficialEvent>>;
    final List<OfficialEvent> summaryRows = hasData
        ? _visibleRows(async.value, mine)
        : const <OfficialEvent>[];
    final String summary = !hasData
        ? ''
        : (_kw.trim().isNotEmpty
              ? '「${_kw.trim()}」${summaryRows.length} 个结果'
              : '${_tabs[_tab].label} · 共 ${summaryRows.length} 个活动');
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('官方活动')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              // 顺序照真源 `pages/activity/list/index.wxml`:搜索 → 分档 → 摘要行;
              // 搜索在「我的」档隐藏(`wx:if="{{tab !== 3}}"`)。
              if (!mine)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space4,
                    CyTokens.space4,
                    CyTokens.space4,
                    0,
                  ),
                  // 搜索框走 CySearchField(门禁 no_material_segmented 拦各页自拼的 TextField)。
                  child: CySearchField(
                    key: const Key('official-events-search'),
                    value: _kw,
                    placeholder: '搜活动名 / 城市',
                    onChanged: (String v) => setState(() => _kw = v),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  mine ? CyTokens.space4 : CyTokens.space2,
                  CyTokens.space4,
                  CyTokens.space2,
                ),
                child: CyTabs(
                  // 四档是列表筛选,下划线型按手册 §6 P3 收敛成 iOS 分段
                  //(iOS 26+ 走系统分段控件,旧系统回退 Cupertino 滑动分段)。
                  variant: CyTabsVariant.segmented,
                  active: _tabs[_tab].key,
                  tabs: <CyTab>[
                    for (final t in _tabs) CyTab(key: t.key, label: t.label),
                  ],
                  onChanged: (String k) => setState(
                    () => _tab = _tabs.indexWhere((t) => t.key == k),
                  ),
                ),
              ),
              if (canPublish || hasData)
                Padding(
                  key: const Key('official-events-summary-row'),
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space4,
                    0,
                    CyTokens.space4,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CyType.caption1.copyWith(
                            color: CyPalette.of(context).textTertiary,
                          ),
                        ),
                      ),
                      if (canPublish)
                        _SummaryLink(
                          key: const Key('official-events-mine'),
                          label: '我发布的 ›',
                          onPressed: _openMine,
                        ),
                      if (hasData)
                        _SummaryLink(
                          key: const Key('official-events-inbox'),
                          // 真源 pages/activity/list/index.wxml:27 的 oe-inbox-link
                          // 写的就是「邀约 ›」。「承接邀约」是 App 自己加的注解,
                          // 与真源不一致 —— 回退。
                          label: '邀约 ›',
                          onPressed: _openInbox,
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: async.when(
                  loading: () => Center(child: CupertinoActivityIndicator()),
                  error: (Object e, StackTrace _) =>
                      // ★ 游客点「我的」档必撞 HTTP 401(`/api/official/my-events`
                      //   要登录态)。原样吐 e.toString() = 满屏 dio 英文堆栈,
                      //   且「重试」永远不会好 —— 分流成登录引导。
                      //   真源 `pages/activity/list` 对各入口不做游客隐藏(小程序
                      //   静默 wx.login,无游客 401 一说),所以入口照留,
                      //   死路改在落点上修(口径同 play 域 38790273)。
                      mine && isUnauthorizedError(e)
                      ? StatusView(
                          message: '登录后查看我参与的活动',
                          sub: '这一步需要登录,登录完会自动回到这一页。',
                          icon: CupertinoIcons.lock,
                          large: true,
                          retryLabel: '去登录',
                          onRetry: () async {
                            if (!await requireLogin(context, ref)) return;
                            ref.invalidate(myOfficialEventsProvider);
                          },
                        )
                      : StatusView(
                          message: '活动列表没能打开',
                          sub: officialErrorSub(e),
                          large: true,
                          onRetry: () => ref.invalidate(
                            mine
                                ? myOfficialEventsProvider
                                : officialEventsProvider,
                          ),
                        ),
                  data: (List<OfficialEvent> all) {
                    final List<OfficialEvent> rows = _visibleRows(all, mine);
                    if (rows.isEmpty) {
                      // 文案逐字对齐真源 `EMPTY_COPY`(index.js:35)与搜不到那一档:
                      // 三档各说各的,「搜不到」另算 —— 混成一句会让用户以为
                      // 整个官方活动都没了。
                      const List<List<String>> buckets = <List<String>>[
                        <String>['暂无进行中的活动', '官方策展活动会第一时间出现在这里'],
                        <String>['暂无即将上线的活动', '官方策展活动会第一时间出现在这里'],
                        <String>['暂无已结束的活动', '往期活动归档后会出现在这里'],
                        <String>['还没有参与的活动', '报名活动后会出现在这里'],
                      ];
                      return StatusView(
                        message: _kw.isNotEmpty ? '没有找到相关活动' : buckets[_tab][0],
                        sub: _kw.isNotEmpty
                            ? '换个关键词，或看看其他分类'
                            : buckets[_tab][1],
                        large: true,
                      );
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async => ref.invalidate(
                        mine
                            ? myOfficialEventsProvider
                            : officialEventsProvider,
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space4,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (BuildContext c, int i) => _Card(rows[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLink extends StatelessWidget {
  const _SummaryLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
        onPressed: onPressed,
        child: Text(
          label,
          style: CyType.caption1.copyWith(color: p.textPrimary),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.e);
  final OfficialEvent e;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final ActivityStatusMeta meta = activityStatusMeta(e.status);
    return CupertinoButton(
      key: Key('official-event-${e.id}'),
      onPressed: () => context.push('/official/${e.id}'),
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space3),
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          border: Border.all(color: p.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 封面可空(migration_official_event.sql:16 DEFAULT NULL)。
            // CyNetImage 自带兜底,不会渲成系统碎图标。
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CyNetImage(e.coverImg, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CyType.headline.copyWith(color: p.textPrimary),
                        ),
                      ),
                      if (meta.text.isNotEmpty)
                        Text(
                          meta.text,
                          key: Key('official-status-${e.id}'),
                          style: CyType.caption1.copyWith(
                            color: p.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  if ((e.subtitle ?? '').trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      e.subtitle!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.caption1.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    <String>[
                      if ((e.city ?? '').trim().isNotEmpty) e.city!.trim(),
                      '${e.participants} 人参与',
                    ].join(' · '),
                    style: CyType.caption1.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
