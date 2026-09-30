import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_tabs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../../data/models/activity_status.dart';
import 'activity_controller.dart';
import '../auth/login_gate.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

/// 后端是否以「未登录」拒绝了这次请求。只认 401,不把网络故障也当成要登录 ——
/// 那会让断网的用户被反复推去登录页,登完还是失败。(与详情页同一判据)
bool _isUnauthorized(Object err) =>
    err is DioException && err.response?.statusCode == 401;

/// 活动目录:卡片列表(满幅封面 + 名 + 地点 + 起价),三态,点进详情。
/// 顶部两段切换:全部活动 / 我报名的。
class ActivityListPage extends ConsumerStatefulWidget {
  const ActivityListPage({super.key, this.now});

  /// 固定时钟,只给测试 / 基准图注入;正常运行时为 null,走系统时间。
  final DateTime? now;

  @override
  ConsumerState<ActivityListPage> createState() => _ActivityListPageState();
}

class _ActivityListPageState extends ConsumerState<ActivityListPage> {
  /// 0 进行中 / 1 即将 / 2 已结束 / 3 我的 —— 对齐小程序 `tabs`(index.js:62)。
  /// 此前只有「全部活动 / 我报名的」两档,少了时间维度。
  int _tab = 0;

  /// 搜索关键词。小程序是**前端过滤**(index.js:210-214),不发后端 —— 照做。
  String _keyword = '';

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        trailing:
            // ★ 官方活动是**另一套目录**(/api/official/events),不是这一页的
            //   /api/activity/list。小程序把它们分成两页,App 此前只有这一页,
            //   官方活动玩家根本发现不了。
            CupertinoButton(
              key: const Key('activities-official-entry'),
              onPressed: () => context.push('/official-events'),
              minimumSize: const Size.square(CyTokens.btnH),
              // ★ §3.7 真机「裁半截」的结构性免疫:文字盒占满导航栏 44pt 整带
              //   (=真源 --cy-btn-h)、居中,不再依赖「按钮默认 6pt 内衬 + 字体
              //   行高恰好装得下墨迹」这两个真机才成立的巧合;行高显式 ≥1em,
              //   墨迹永远落在行盒内,任何一层裁剪(导航栏带裁剪 / 行盒裁剪)都削不到字。
              padding: EdgeInsets.zero,
              child: const SizedBox(
                height: CyTokens.btnH,
                // Align 不给 widthFactor 会横向吃满导航栏约束:入口被推到屏幕
                // 正中(长得像页面标题),命中区盖住整条导航栏。宽度钉回文字本身,
                // 纵向仍占满 44pt 整带。
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: Text(
                    '官方活动',
                    maxLines: 1,
                    style: TextStyle(height: 1.4),
                  ),
                ),
              ),
            ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('活动'),
              Expanded(
                child: Column(
                  children: <Widget>[
                    // 搜索框 —— 小程序有,App 此前完全没有。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CyTokens.space4,
                        CyTokens.space3,
                        CyTokens.space4,
                        0,
                      ),
                      child: CySearchField(
                        value: _keyword,
                        placeholder: '搜索活动名称或城市',
                        onChanged: (String v) => setState(() => _keyword = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CyTokens.space4,
                        CyTokens.space3,
                        CyTokens.space4,
                        CyTokens.space1,
                      ),
                      // 小程序用 cy-tabs;这里用同一套 CyChip 表达分段选择,
                      // 四档对齐小程序 index.js:62 的 tabs。
                      child: CyTabs(
                        variant: CyTabsVariant.chip,
                        tabs: <CyTab>[
                          for (int i = 0; i < kActivityTabLabels.length; i++)
                            CyTab(key: '$i', label: kActivityTabLabels[i]),
                        ],
                        active: '$_tab',
                        onChanged: (String k) =>
                            setState(() => _tab = int.parse(k)),
                      ),
                    ),
                    Expanded(
                      child: _tab == 3
                          ? _JoinedList(keyword: _keyword)
                          : _AllList(
                              bucket: ActivityBucket.values[_tab],
                              bucketLabel: kActivityTabLabels[_tab],
                              keyword: _keyword,
                              now: widget.now,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllList extends ConsumerWidget {
  const _AllList({
    required this.bucket,
    required this.bucketLabel,
    required this.keyword,
    this.now,
  });

  final ActivityBucket bucket;
  final String bucketLabel;
  final String keyword;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    return activities.when(
      // 真源 pages/activity/list 活动流用 feed-card 档(封面+三行+标签)。
      loading: () => const CySkeleton(
        type: CySkeletonType.feedCard,
        count: 3,
      ),
      error: (Object err, StackTrace st) => StatusView(
        message: '没能加载活动',
        sub: '检查网络后重试',
        icon: Icons.cloud_off,
        onRetry: () => ref.invalidate(activityListProvider),
      ),
      data: (List<Activity> all) {
        // 分档 + 关键词都在前端做 —— 与小程序同一套(index.js:205-214),
        // 它也不为筛选发请求。★ 分档判据走真实时间字段,不是 status:
        //   这个端点的响应里没有 status(见 activityInTimeBucket 的注释)。
        final List<Activity> list = all
            .where(
              (Activity a) => activityInTimeBucket(
                startDate: a.startDate,
                endDate: a.endDate,
                bucket: bucket,
                now: now,
              ),
            )
            .where(
              (Activity a) => activityMatchesKeyword(
                keyword: keyword,
                title: a.name,
                subtitle: a.description,
                city: a.addressName,
              ),
            )
            .toList();

        if (list.isEmpty) {
          // 空态文案按档区分,搜索无结果另有一句 —— 小程序 EMPTY_COPY 与 index.js:221。
          final ({String title, String sub}) c = keyword.trim().isEmpty
              ? activityEmptyCopy(bucket)
              : kActivitySearchEmpty;
          return StatusView(
            message: c.title,
            sub: c.sub,
            icon: Icons.event_outlined,
            onRetry: () => ref.invalidate(activityListProvider),
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(activityListProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(CyTokens.space4),
            // +1 是计数行,小程序在列表上方有一行「档名 · 共 N 个活动」。
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  activitySummary(
                    keyword: keyword,
                    bucketLabel: bucketLabel,
                    count: list.length,
                  ),
                  // `.oe-summary`:type-caption + text-tertiary
                  style: CyType.caption2.copyWith(color: CyTokens.textTertiary),
                );
              }
              return _ActivityCard(activity: list[i - 1]);
            },
          ),
        );
      },
    );
  }
}

class _JoinedList extends ConsumerWidget {
  const _JoinedList({required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(myJoinedActivitiesProvider);
    return joined.when(
      loading: () => const CySkeleton(),
      error: (Object err, StackTrace st) => _isUnauthorized(err)
          // ★ 游客点「我的」必然走到这里:`POST /api/registration/my-joined`
          //   无 token 时返回 401(实测生产),而路由是让游客直接浏览的。
          //   通用错误态的「重试」按多少次都还是 401 —— 是条死路。
          //   改成与详情页同一套可恢复的登录引导。
          ? StatusView(
              message: '登录后查看报名记录',
              sub: '这一步需要登录,登录完会自动回到这一页。',
              icon: Icons.lock_outline,
              retryLabel: '去登录',
              onRetry: () async {
                if (!await requireLogin(context, ref)) return;
                ref.invalidate(myJoinedActivitiesProvider);
              },
            )
          : StatusView(
              message: '没能加载报名记录',
              sub: '检查网络后重试',
              icon: Icons.cloud_off,
              onRetry: () => ref.invalidate(myJoinedActivitiesProvider),
            ),
      data: (List<MyRegistration> all) {
        // 「我的」这档同样吃搜索 —— 小程序四档都过滤(index.js:209 在分档之后统一过)。
        final List<MyRegistration> list = all
            .where(
              (MyRegistration r) =>
                  activityMatchesKeyword(keyword: keyword, title: r.title),
            )
            .toList();
        if (list.isEmpty) {
          final ({String title, String sub}) c = keyword.trim().isEmpty
              ? activityEmptyCopy(ActivityBucket.live, mine: true)
              : kActivitySearchEmpty;
          return StatusView(
            message: c.title,
            sub: c.sub,
            icon: Icons.how_to_reg_outlined,
            onRetry: () => ref.invalidate(myJoinedActivitiesProvider),
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(myJoinedActivitiesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(CyTokens.space4),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  activitySummary(
                    keyword: keyword,
                    bucketLabel: '我的',
                    count: list.length,
                  ),
                  // `.oe-summary`:type-caption + text-tertiary
                  style: CyType.caption2.copyWith(color: CyTokens.textTertiary),
                );
              }
              return _JoinedCard(reg: list[i - 1]);
            },
          ),
        );
      },
    );
  }
}

/// 活动卡:满幅 4:3 封面 + body(标题 / 副标 / 地点·价格)。
/// 对齐小程序 `pages/activity/list/index.wxml` 的 `.oe-card`(竖版满幅封面)。
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final hasDesc = (activity.description?.isNotEmpty ?? false);
    final address = (activity.addressName?.isNotEmpty ?? false)
        ? activity.addressName!
        : (activity.address?.isNotEmpty ?? false)
        ? activity.address!
        : '';
    // ★ 有意偏离小程序:它的列表 meta 是「时间 · 城市 · N人参与」,**不显示价格**
    //   (pages/activity/list/index.wxml 里没有价格字段)。这里保留起价,理由:
    //   ③ 探店日是卖票的,列表阶段给出最低价能帮用户决策;小程序不显示大概是因为
    //   多票种、价格要到详情才明确。**这不是漏对齐,别照小程序删掉。**
    //
    // ★ 更正(2026-08-18):这里原先写着「列表 VO 没有时间与报名人数字段」——
    //   **时间那半是错的**。生产 `/api/activity/list` 一直在下发 startDate/endDate,
    //   只是 Activity 模型没解析。已补上并在 meta 里显示时间。
    //   **报名人数那半是对的**:响应里只有 viewCount(浏览量),没有报名人数,
    //   所以小程序那句「N人参与」在 App 上仍然做不了。
    final price = activity.minAmount != null && activity.minAmount! > 0
        ? '¥${activity.minAmount!.toStringAsFixed(2)} 起'
        : '免费';
    // 只取到「日 时:分」,列表里不需要秒与年份的精度。
    final start = activity.startDate;
    final when = (start != null && start.length >= 16)
        ? start.substring(5, 16)
        : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: CupertinoButton(
        onPressed: () => context.push('/activity/${activity.id}'),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Cover(url: activity.imgUrl),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    activity.name.isEmpty ? '未命名活动' : activity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.callout.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (hasDesc) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      activity.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.caption1.copyWith(
                        color: CyTokens.textTertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      if (address.isNotEmpty) ...<Widget>[
                        if (when != null) ...<Widget>[
                          Icon(
                            Icons.schedule_outlined,
                            size: 14,
                            color: CyTokens.textDisabled,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            when,
                            style: CyType.caption1.copyWith(
                              color: CyTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(width: CyTokens.space2),
                        ],
                        const Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: CyTokens.textDisabled,
                        ),
                        const SizedBox(width: CyTokens.space1),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CyType.caption1.copyWith(
                              color: CyTokens.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: CyTokens.space2),
                      ],
                      Text(
                        price,
                        style: CyType.caption1.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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

/// 我报名的卡:满幅 4:3 封面 + 标题 + 参与日期 + 状态胶囊。
class _JoinedCard extends StatelessWidget {
  const _JoinedCard({required this.reg});
  final MyRegistration reg;

  // 状态一律走 [MyRegistration.ticketState] —— 它与小程序票夹的 wxs `state()`
  // 逐字对齐(判定顺序 已核验→已取消→待使用→待支付,顺序不可重排)。
  //
  // ★ 这里原先手写了第二套解析,同一个状态在 App 里出现两种说法:
  //   票夹叫「已核验」,这张卡叫「已核销」。两处各自维护,改一处必漏另一处。
  //   顺带一提,原来那套的「待支付」「已取消」两个分支在本页是**死代码** ——
  //   本页数据来自 `/api/registration/my-joined`,后端那个接口写死
  //   `q.setRegistrationStatus(2)`(ApiRegistrationController.java:810),
  //   只返已支付的,压根不会下发 1 或 3。走 ticketState 后这层判断收归一处,
  //   本页拿到什么就显示什么,不必在页面里重复猜。
  Color get _statusColor => switch (reg.ticketState) {
    TicketState.pending => CyTokens.statusWarning,
    TicketState.voided => CyTokens.textDisabled,
    TicketState.done => CyTokens.statusSuccess,
    TicketState.ready => CyTokens.statusInfo,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: CupertinoButton(
        onPressed: () => context.push('/activity/${reg.ownerId}'),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Cover(url: reg.imgUrl),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (reg.title?.isNotEmpty ?? false) ? reg.title! : '活动',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.callout.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (reg.participateDate?.isNotEmpty ?? false) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      '参与日期：${reg.participateDate}',
                      style: CyType.caption1.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: CyTokens.space2),
                  Container(
                    height: 22, // 44rpx,与 .cy-tag 同高
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2_5,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CyTokens.bgSubtle,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    ),
                    child: Text(
                      reg.ticketState.label,
                      style: CyType.caption2.copyWith(color: _statusColor),
                    ),
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

/// 满幅 4:3 封面,无图时兜底「封面暂不可用」。
/// 对齐小程序 `.oe-cover`(padding-top:75%)与 `.cover-error`。
class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(
          Icons.event_outlined,
          size: 32,
          color: CyTokens.textDisabled,
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '封面暂不可用',
          style: CyType.caption2.copyWith(color: CyTokens.textSecondary),
        ),
      ],
    );
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        color: CyTokens.bgSurfaceSubtle,
        child: (url == null || url!.isEmpty)
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
