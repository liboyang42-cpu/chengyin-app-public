import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../team/team_nearby_page.dart' show teamMapApiProvider;
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 票夹合并快照。真源 `signup/index.js` `rebuildTicketList()`:
/// 两个接口照旧各拉各的(owner_type 1/2),**只在渲染层合成一条**——
/// 「路线 / 场次」这层 tab 已由用户 2026-09-09 裁决删除,两种票放一起,
/// 落点差异由每张票自己分流(见 [walletTicketAction])。
/// 排序口径照真源 `topics.concat(activities)`:路线票在前、场次票在后,
/// 组内保持接口返回序,不自造任何排序。
class WalletSnapshot {
  const WalletSnapshot({required this.tickets, this.halfFailure});

  final List<MyRegistration> tickets;

  /// 只挂了一路:票夹照常显示能拿到的那半,但要报一次 ——
  /// 真源 `_reportHalfFailure` 原话「别让缺的那半静默」。
  final String? halfFailure;
}

/// 我的票夹:`POST /api/registration/list` 两路(1=路线票 / 2=场次票)。
/// 后端在 ownerType<3 时强制 registrationStatus=2,故此处只会拿到已支付的票。
/// 状态合成同真源:两路都失败才 error(walletErrorMsg = 路线 err 优先);
/// 一路失败 + 有票/全空 → 照常 ready/empty,失败那一路进 [halfFailure]。
/// 非 200 / 网络异常不兜底假数据。
final myTicketsProvider = FutureProvider.autoDispose<WalletSnapshot>((
  ref,
) async {
  // 游客:票在账号里,两路接口必然 401 —— 先不发注定失败的请求,由页内登录门
  // 解释(见 _TicketsPageState.build)。登录后本 provider 因依赖 auth 自动重跑。
  if (!ref.watch(authControllerProvider).isLoggedIn) {
    return const WalletSnapshot(tickets: <MyRegistration>[]);
  }
  final api = ref.watch(activityApiProvider);
  final results = await Future.wait(<Future<Object>>[
    api
        .topicTicketList(fallbackMsg: '路线票加载失败')
        .then<Object>((List<MyRegistration> v) => v)
        .catchError((Object e) => e),
    api
        .ticketList(fallbackMsg: '活动票加载失败')
        .then<Object>((List<MyRegistration> v) => v)
        .catchError((Object e) => e),
  ]);
  final Object topic = results[0];
  final Object activity = results[1];
  final String? topicErr = topic is List<MyRegistration>
      ? null
      : friendlyOrBackendMessage(topic, fallback: '路线票加载失败');
  final String? activityErr = activity is List<MyRegistration>
      ? null
      : friendlyOrBackendMessage(activity, fallback: '活动票加载失败');
  if (topicErr != null && activityErr != null) {
    // 真源 walletErrorMsg = topic.err || activity.err —— 两路都挂才判死整页。
    throw Exception(topicErr);
  }
  final List<MyRegistration> merged = <MyRegistration>[
    ...topic is List<MyRegistration> ? topic : const <MyRegistration>[],
    ...activity is List<MyRegistration> ? activity : const <MyRegistration>[],
  ];
  // App 范围只做 ③ 探店日的历史口径已废(fail-open,shouldShowInApp 恒 true),
  // 保留过滤位:未知 productType(null)仍展示,理由见 shouldShowInApp。
  return WalletSnapshot(
    tickets: merged
        .where((MyRegistration r) => r.shouldShowInApp)
        .toList(growable: false),
    halfFailure: topicErr ?? activityErr,
  );
});

/// 票夹一张票对应的队伍。真源 `subpackageMember/signup/index.js` `loadMyTeams()`。
class WalletTeam {
  const WalletTeam({
    required this.id,
    required this.title,
    this.joinedCount,
    this.maxMembers,
  });

  final int id;
  final String title;

  /// 人数拿不到就是 null,不补 0/0(真源 wxml 同口径)。
  final int? joinedCount;
  final int? maxMembers;
}

/// `/api/team/my` → `{ "ownerType:ownerId": 队伍 }`。快照 `index.js:205-228`:
/// 缺 id/ownerId 的行跳过;已结束(3)/已解散(4)不给入口 —— 点进去只看到死队伍。
Map<String, WalletTeam> indexWalletTeams(List<Map<String, dynamic>> rows) {
  final Map<String, WalletTeam> index = <String, WalletTeam>{};
  for (final Map<String, dynamic> t in rows) {
    final int? id = _walletInt(t['id']);
    final int? ownerId = _walletInt(t['ownerId']);
    if (id == null || id == 0 || ownerId == null || ownerId == 0) continue;
    final int? status = _walletInt(t['status']);
    if (status == 3 || status == 4) continue;
    final int? ownerType = _walletInt(t['ownerType']);
    if (ownerType == null) continue;
    index['$ownerType:$ownerId'] = WalletTeam(
      id: id,
      title: '${t['title'] ?? ''}'.trim(),
      joinedCount: _walletInt(t['joinedCount']),
      maxMembers: _walletInt(t['maxMembers']),
    );
  }
  return index;
}

/// 真源 `Number(字段)` 口径:数字照取,拿不到就是没下发(null),不当 0。
int? _walletInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 票夹「我的队伍 ›」索引:本页一次拉全量(每张票各发一次会把一屏刷成 N 个请求),
/// 再按 `ownerType:ownerId` 落到具体那张票上。**静默失败**是真源钉死的口径:
/// 拉不到 ≠ 没有队伍,这一行直接不出 —— 不弹全局 toast、不写空态。
final walletMyTeamsProvider =
    FutureProvider.autoDispose<Map<String, WalletTeam>>((ref) async {
      try {
        final rows = await ref.watch(teamMapApiProvider).myTeams();
        return indexWalletTeams(rows);
      } catch (_) {
        return const <String, WalletTeam>{};
      }
    });

/// 点卡分流,真源 `signup/index.js` `_openTicket`:
/// 待支付(唯一还会落订单的一档)→ 订单详情;已取消/已过期 → 只提示不跳;
/// 状态待确认 → 提示;其余(已报名/已核验)→ App 侧票根详情 /ticket/:id。
({String? route, String? notice}) walletTicketAction(MyRegistration ticket) {
  final int? status = ticket.registrationStatus;
  if (status == 1) {
    return (route: '/orders?detailId=${ticket.id}', notice: null);
  }
  if (status == 3 || status == 4) {
    return (route: null, notice: status == 4 ? '票已过期' : '票已取消');
  }
  if (status != 2) {
    return (route: null, notice: '票状态待确认');
  }
  return (route: '/ticket/${ticket.id}', notice: null);
}

/// 票夹页:两种票合并成一条列表 —— 「路线 / 场次」那层 tab 已由用户
/// 2026-09-09 裁决删除,打开票夹只看「我有哪些票」。
/// 点进去看票卡详情与履约记录。
class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key, this.focusId});

  final int? focusId;

  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  final GlobalKey _focusKey = GlobalKey();
  bool _focusScheduled = false;

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(myTicketsProvider);
    // 加载中/失败都给空表:那一行还没到就直接不出,和真源一个口径(不摆空入口)。
    final teamsByOwner =
        ref.watch(walletMyTeamsProvider).value ?? const <String, WalletTeam>{};
    // ★ 游客深链落地时给登录门,而不是被静默弹回首页(B1 报告 #231 P1)——
    //   路由那边已不再拦票夹三页,解释与登入口都放在这一屏。
    //   刻意不自动弹登录弹窗:冷启动深链直接盖一层 sheet 同样像"链接坏了"。
    final bool guest = !ref.watch(authControllerProvider).isLoggedIn;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    // 只挂一路时票夹照常显示能拿到的那半,但要把失败报出来一次 ——
    // 真源 `_reportHalfFailure`:「别让缺的那半静默」。
    ref.listen(myTicketsProvider, (
      Object? previous,
      AsyncValue<WalletSnapshot> next,
    ) {
      final String? half = next.value?.halfFailure;
      if (half != null) CyNativeNotice.show(context, half);
    });
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('票夹'),
              Expanded(
                child: guest
                    ? StatusView(
                        key: const Key('tickets-login-gate'),
                        message: '登录后查看票夹',
                        sub: '票都在账号里，登录完就能看到。',
                        icon: CupertinoIcons.lock,
                        large: true,
                        retryLabel: '去登录',
                        onRetry: () async {
                          if (!await requireLogin(context, ref)) return;
                        },
                      )
                    : RefreshIndicator.adaptive(
                        onRefresh: () async =>
                            ref.invalidate(myTicketsProvider),
                        child: tickets.when(
                          // 真源 `index.wxml:54` 的 loading-label 走 aria-label
                          // (骨架本体不渲染可见「加载中」文字,读屏要能听到在等什么)。
                          loading: () => Semantics(
                            container: true,
                            liveRegion: true,
                            label: '正在加载我的票',
                            // 真源 subpackageMember/signup 票夹用 ticket 档(居中单票)。
                            child: const CySkeleton(
                              type: CySkeletonType.ticket,
                              count: 1,
                            ),
                          ),
                          // 真源 `index.wxml:57`:title「票夹没能打开」,
                          // sub = walletErrorMsg(后端原文,不许吞成一句套话)。
                          error: (Object err, StackTrace st) => StatusView(
                            message: '票夹没能打开',
                            sub: friendlyOrBackendMessage(
                              err,
                              fallback: '票夹没能打开',
                            ),
                            icon: CupertinoIcons.cloud,
                            scrollable: true,
                            onRetry: () => ref.invalidate(myTicketsProvider),
                          ),
                          data: (WalletSnapshot snap) {
                            final List<MyRegistration> list = snap.tickets;
                            // 真源 `index.wxml:60`:删了 tab 就只有一句空态。
                            if (list.isEmpty) {
                              return StatusView(
                                message: '还没有票',
                                sub: '去首页发现路线或报名场次，票会在这里出现。',
                                large: true,
                                icon: CupertinoIcons.ticket,
                                scrollable: true,
                              );
                            }
                            final int focusIndex = widget.focusId == null
                                ? -1
                                : list.indexWhere(
                                    (MyRegistration ticket) =>
                                        ticket.id == widget.focusId,
                                  );
                            if (focusIndex >= 0 && !_focusScheduled) {
                              _focusScheduled = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final BuildContext? target =
                                    _focusKey.currentContext;
                                if (target != null) {
                                  Scrollable.ensureVisible(
                                    target,
                                    alignment: .5,
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : CyMotion.standard,
                                  );
                                }
                              });
                            }
                            return ListView.separated(
                              padding: EdgeInsets.all(CyTokens.space4),
                              itemCount: list.length,
                              separatorBuilder: (_, _) =>
                                  SizedBox(height: CyTokens.space3),
                              itemBuilder: (context, i) {
                                final MyRegistration ticket = list[i];
                                final WalletTeam? team =
                                    teamsByOwner['${ticket.ownerType}:${ticket.ownerId}'];
                                // 真源:队伍行跟着**具体那张票**,在票卡外面往下挂 ——
                                // 写在票外面会指到别的票上去。没有队伍就整行不出。
                                final Widget card = _TicketCard(ticket: ticket);
                                final Widget stacked = team == null
                                    ? card
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: <Widget>[
                                          card,
                                          _WalletTeamEntry(team: team),
                                        ],
                                      );
                                if (ticket.id != widget.focusId) return stacked;
                                return KeyedSubtree(
                                  key: ValueKey<String>(
                                    'ticket-focus-${ticket.id}',
                                  ),
                                  child: KeyedSubtree(
                                    key: _focusKey,
                                    child: stacked,
                                  ),
                                );
                              },
                            );
                          },
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

/// 票券卡片 —— 版式对齐小程序 `subpackageMember/signup`:
/// **一张票 = 上段票面 + 打孔虚线 + 下段票根**,状态**只沿左缘 4pt 色带**
/// 与票根那行文字表达。
///
/// ⚠️ 不要再加票面右下角的彩底状态胶囊 —— 小程序已明确删掉它,
///    理由是「同一状态说两遍」,且彩底白字的对比度账随之作废。
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final MyRegistration ticket;

  /// 左缘色带颜色。`--cy-color-status-*`:待使用=info、待支付=warning、
  /// 已核验/已取消=text-tertiary。取 `CyPalette`(随外观解析),不取暗色编译期常量。
  Color _bandColor(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return switch (ticket.ticketState) {
      TicketState.ready => palette.statusInfo,
      TicketState.pending => palette.statusWarning,
      TicketState.done || TicketState.voided => palette.textTertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ticket.ticketState;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: Stack(
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TicketFace(ticket: ticket),
              _TicketStub(state: state, label: ticket.ticketStatusLabel),
            ],
          ),
          // 左缘状态色带,贯穿票面与票根。
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: CyTokens.space1,
            child: ColoredBox(color: _bandColor(context)),
          ),
        ],
      ),
    );
    // 真源 aria-label 口径:`tk.cta || tk.label`,后接票名。已核验/已取消
    // 没有 CTA,读屏听到的就是状态词,而不是一个骗人的「查看」。
    return Semantics(
      button: true,
      label:
          '${state.cta.isEmpty ? ticket.ticketStatusLabel : state.cta}，'
          '${ticket.title ?? '票券'}',
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: () {
            final ({String? route, String? notice}) action = walletTicketAction(
              ticket,
            );
            final String? route = action.route;
            if (route != null) {
              context.push(route);
              return;
            }
            final String? notice = action.notice;
            if (notice != null) CyNativeNotice.show(context, notice);
          },
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          // 已取消整体压暗,与小程序 .tk--void { opacity:.6 } 一致。
          child: Opacity(
            opacity: state == TicketState.voided ? 0.6 : 1,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// 票夹里的队伍入口行。真源 `.team-entry`(`signup/index.wxml:113-121`):
/// 「我的队伍」+ 队名(有则写)+ 人数 N/M(两个都拿到才写)+ 右箭头;
/// 点击落点与小程序 `goMyTeam` 一致 —— 开这支队的队伍详情。
class _WalletTeamEntry extends StatelessWidget {
  const _WalletTeamEntry({required this.team});
  final WalletTeam team;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool showCount = team.joinedCount != null && team.maxMembers != null;
    return Padding(
      padding: EdgeInsets.only(top: CyTokens.space4),
      child: Semantics(
        button: true,
        label: team.title.isEmpty ? '打开我的队伍' : '打开我的队伍：${team.title}',
        child: ExcludeSemantics(
          child: CupertinoButton(
            // 真源是普通 view + hover 按压,不是凸起的按钮:默认内边距清零。
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            onPressed: () => context.push('/team/${team.id}'),
            child: Container(
              decoration: BoxDecoration(
                // 真源 --cy-bg-card = --cy-color-bg-surface,浅色值交给调色板。
                color: palette.bgSurface,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              padding: EdgeInsets.all(CyTokens.space4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '我的队伍',
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        if (team.title.isNotEmpty) ...<Widget>[
                          SizedBox(width: CyTokens.space2_5),
                          Flexible(
                            child: Text(
                              team.title,
                              style: TextStyle(
                                fontSize: CyTokens.typeCaption,
                                color: palette.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCount) ...<Widget>[
                    Text(
                      '${team.joinedCount}/${team.maxMembers}',
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: palette.textTertiary,
                      ),
                    ),
                    SizedBox(width: CyTokens.space2),
                  ],
                  // cy-icon arrow-right size=24rpx ⇒ 12pt,箭头交给系统语义。
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 12,
                    color: palette.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 上段票面。
class _TicketFace extends StatelessWidget {
  const _TicketFace({required this.ticket});
  final MyRegistration ticket;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      color: palette.bgSurface,
      padding: EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space4,
        CyTokens.space4,
        CyTokens.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ticket.title ?? '未命名活动',
            style: textTheme.titleMedium?.copyWith(
              fontSize: CyTokens.typeCardTitle,
              height: CyTokens.leadingTight,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: CyTokens.space2),
          if (ticket.participateDate != null &&
              ticket.participateDate!.isNotEmpty)
            _MetaLine(
              icon: Icons.event_outlined,
              text: ticket.participateDate!,
            ),
          if (ticket.registrationNo != null &&
              ticket.registrationNo!.isNotEmpty)
            _MetaLine(
              icon: Icons.receipt_long_outlined,
              text: ticket.registrationNo!,
            ),
        ],
      ),
    );
  }
}

/// 下段票根:打孔 + 撕线 + 状态文字 + 动作提示。
class _TicketStub extends StatelessWidget {
  const _TicketStub({required this.state, required this.label});
  final TicketState state;

  /// 状态直书。void 态再分「已取消 / 已过期」两档(真源 wxs `label()`),
  /// 所以文字由票传入,不直接取 `state.label`。
  final String label;

  /// 小程序票根高 132rpx。
  static const double _height = 66;

  /// 打孔直径。小程序是半径 20rpx 的透明半圆 ⇒ 直径 40rpx = 20pt。
  static const double _holeSize = 20;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return SizedBox(
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: double.infinity,
            height: _height,
            color: palette.bgElevated,
            padding: EdgeInsets.symmetric(horizontal: CyTokens.space4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: CyTokens.typeBody,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                // 真源 wxs `cta()`:已核验/已取消不出 CTA,票根只剩状态词。
                if (state.cta.isNotEmpty)
                  Text(
                    state.cta,
                    style: textTheme.labelMedium?.copyWith(
                      fontSize: CyTokens.typeLabel,
                      // 只有待使用态把动作提示提亮,其余保持次要。
                      color: state == TicketState.ready
                          ? palette.textPrimary
                          : palette.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          // 撕线:左右各留 space3,与两个孔之间相连。
          Positioned(
            left: CyTokens.space3,
            right: CyTokens.space3,
            top: 0,
            child: CustomPaint(
              painter: _DashedLinePainter(color: palette.borderStrong),
              size: const Size(double.infinity, 1),
            ),
          ),
          // 左右打孔。
          // ⚠️ 简化:小程序用 radial-gradient 做**真透明**半圆;这里用页面底色
          //    的圆模拟,视觉等效的前提是票卡直接铺在页面底上。日后若把票卡
          //    放到有背景图的容器里(如小程序 slides),要改成 ClipPath 真挖洞。
          Positioned(
            left: -_holeSize / 2,
            top: -_holeSize / 2,
            child: _Hole(size: _holeSize),
          ),
          Positioned(
            right: -_holeSize / 2,
            top: -_holeSize / 2,
            child: _Hole(size: _holeSize),
          ),
        ],
      ),
    );
  }
}

class _Hole extends StatelessWidget {
  const _Hole({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 孔 = 票卡底下那块页面底,取外观解析后的 `bgPage`(恒暗端与旧常量同值)。
        color: CyPalette.of(context).bgPage,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 撕线。Flutter 没有内置 dashed border,画一条即可,不引依赖。
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: CyTokens.space1),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: palette.textSecondary),
          SizedBox(width: CyTokens.space1_5),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: palette.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
