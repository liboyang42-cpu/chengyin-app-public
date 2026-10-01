import '../../l10n/strings.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_api.dart' show ClubApiException;
import '../../data/api/club_topic_ops_api.dart';
import '../../data/api/game_session_api.dart';
import '../../data/models/club_director.dart';
import '../../data/models/club_topic_ops.dart';
import 'club_director_controller.dart';
import 'club_director_messages.dart';
import 'club_director_sheets.dart';
import 'club_director_labels.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

/// 导演台的复盘导出。俱乐部的接口面与商家那个 `GameSessionGateway` 不同,
/// 所以单独一个 provider(别把两边并成一个接口 —— 商家页的替身会一起红)。
final gameSessionApiClubProvider = Provider<ClubGameSessionGateway>((ref) {
  return GameSessionApi(ref.watch(dioClientProvider));
});

/// 俱乐部 · 活动详情(H1–H6 + 导演台 4-C)。对齐小程序 `pages/club/topic-detail`。
///
/// 这是**俱乐部视角**的主题详情:这条路线有几章几站、剧情写没写、玩法配没配、
/// 今天这一场谁来。玩家视角走 `/topic/:id`,商家承接视角走
/// `/merchant/recruit/:topicId` —— 三个视角读同一份公开投影,但看的东西不同,
/// 别为了复用把三页合成一页。
///
/// 「活动导演台」就在这一页(真源同页:`director.js` 混进 `index.js`):
/// canDirect 且有「这一场」时,`clubDirectorProvider` 挂上来 ——
///   · 六态胶囊 = 审核态优先,否则由会话投影七态映射(小程序 `applyDetail` 同序);
///   · 底部主键三段(开始准备/开始活动/结束活动)是**导演台写动作**,
///     经 `/api/game/session/command` 走写入安全内核(先落存根再发,
///     结果未知锁全部写,核对/重放是唯一出口);
///   · D1 准备总览、D4–D8 场次工具(`club_director_sheets.dart`)在本页就位;
///   · 复盘正文(漏斗/节点完成/榜单)仍归下一里程碑,本页只做 recaphead
///     (note + 复制导出),与 `copyRecap` 对齐。
class ClubTopicDetailPage extends ConsumerStatefulWidget {
  const ClubTopicDetailPage({
    super.key,
    required this.clubId,
    required this.topicId,
    this.activityId,
  });

  final int clubId;
  final int topicId;

  /// 从场次进来时带的是「这一场」的标识(H1–H6 的核销数就是这一场的)。
  final int? activityId;

  @override
  ConsumerState<ClubTopicDetailPage> createState() =>
      _ClubTopicDetailPageState();
}

class _ClubTopicDetailPageState extends ConsumerState<ClubTopicDetailPage> {
  ClubOpsLoadState _stage = ClubOpsLoadState.loading;
  ClubTopicOverview? _overview;
  ClubTopicManageStats? _stats;
  String _error = '';
  ClubRecapState? _recap;
  String _recapError = '';
  bool _exporting = false;

  /// 后端以 HTTP 401 表态「没登录/登录过期」——与 403(没权限)是两回事
  /// (#258 域内口径):游客深链撞进来要给页内登录门,不是「你看不到这条活动」。
  bool _loginRequired = false;

  /// 导演台只挂一次(小程序 `startDirector` 的 `_directorStarted` 闸):
  /// 同一场反复回读不重跑 initDirector,换场才重挂。
  int _directorStartedFor = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 两条一起拉:详情(`/api/topic/info-to-user`)管陈列,管理向统计
  /// (`/api/club/crm/topic-manage-stats`)管三个身份与四个数。小程序也是并发发两条,
  /// 且**统计失败不降级成「看起来是普通成员」**——整页失败,重试两条一起重发(拍板1)。
  ///
  /// [showLoading] 只在首次进页为真:写成功后的回读是原地换数,不该闪一次骨架屏。
  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _stage = ClubOpsLoadState.loading;
        _error = '';
      });
    }
    try {
      final ClubTopicOpsApi api = ref.read(clubTopicOpsApiProvider);
      final List<Object> wanted = await Future.wait<Object>(<Future<Object>>[
        api.overview(widget.topicId),
        api.manageStats(
          clubId: widget.clubId,
          topicId: widget.topicId,
          activityId: widget.activityId,
        ),
      ]);
      final ClubTopicOverview overview = wanted[0] as ClubTopicOverview;
      ClubTopicManageStats stats = wanted[1] as ClubTopicManageStats;
      // 小程序 `maybeEnterDirector`:只带 topicId 进来、主题下**恰好一场**、且自己是
      // 导演时,这一场就是「本场」,统计按这一场重拉一次(本场人数/待核销是单场口径)。
      // 多场不认领 —— 那是场次管理的事。
      final int? sole = overview.soleActivityId;
      if (widget.activityId == null && stats.canDirect && sole != null) {
        stats = await api.manageStats(
          clubId: widget.clubId,
          topicId: widget.topicId,
          activityId: sole,
        );
      }
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _stats = stats;
        _stage = ClubOpsLoadState.ready;
        _error = '';
        _loginRequired = false;
      });
      // 小程序 startDirector:canDirect 且有「这一场」才挂导演台,一场挂一次。
      final int directorId = _directorActivityId;
      if (stats.canDirect &&
          directorId > 0 &&
          _directorStartedFor != directorId) {
        _directorStartedFor = directorId;
        ref.read(clubDirectorProvider(directorId).notifier).load();
      }
      // 已结束态的复盘头:主题审核态说「已结束」,或导演台投影说这一局已打完
      // (applyDetail 里 statusKey 覆盖了 overview 的情况)。
      if (_recapActivityId > 0 &&
          (overview.status == ClubTopicStatus.ended || _directorSessionEnded)) {
        await _loadRecap();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubTopicLoadFailed);
        _loginRequired = clubLoginRequired(error);
      });
    }
  }

  /// 这一场是哪一场:从场次进来带 activityId,从俱乐部页进来只有 topicId
  /// (小程序 director.js 的同一条兜底:取主题下第一个场次)。
  int get _recapActivityId {
    final int? fromQuery = widget.activityId;
    if (fromQuery != null && fromQuery > 0) return fromQuery;
    final List<ClubTopicActivity> activities =
        _overview?.activities ?? const <ClubTopicActivity>[];
    return activities.isEmpty ? 0 : activities.first.id;
  }

  /// 集合时间的对象 = 小程序的 `_directorActivityId`:带 activityId 进来就是这一场;
  /// 只带 topicId 时,恰好一场且自己是导演才算「这一场」。没有它就是 0 ——
  /// 不猜、也不拿第一场冒充。
  int get _directorActivityId {
    final int? fromQuery = widget.activityId;
    if (fromQuery != null && fromQuery > 0) return fromQuery;
    if (_stats?.canDirect != true) return 0;
    return _overview?.soleActivityId ?? 0;
  }

  /// 会话七态 → 页面六态(小程序 `applyProjectionStatus` 的同一张表)。
  /// 认不出的状态返回 null —— 宁可退回审核态,也不猜一个把人带错方向。
  static ClubTopicStatus? _sessionStatusKey(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'NOT_PREPARED':
      case 'DRAFT':
        return ClubTopicStatus.confirmed;
      case 'PREPARING':
      case 'READY':
        return ClubTopicStatus.preparing;
      case 'RUNNING':
        return ClubTopicStatus.running;
      case 'FINISHED':
      case 'CANCELLED':
        return ClubTopicStatus.ended;
      default:
        return null;
    }
  }

  /// 导演台是否已把这一局判成「已结束」(build 外的异步路径用 ref.read)。
  bool get _directorSessionEnded {
    final int id = _directorActivityId;
    if (id <= 0 || _stats?.canDirect != true) return false;
    final ClubDirectorState d = ref.read(clubDirectorProvider(id));
    return d.load == ClubDirectorLoadState.ready &&
        _sessionStatusKey(d.projection?.status) == ClubTopicStatus.ended;
  }

  /// 导演台状态(watch 唯一入口):没挂上就是 null —— 被转发进来的
  /// 普通成员不画导演台(真源 `directorActive` 的闸)。
  ClubDirectorState? get _directorState {
    final int id = _directorActivityId;
    if (_stage != ClubOpsLoadState.ready ||
        _stats?.canDirect != true ||
        id <= 0) {
      return null;
    }
    return ref.watch(clubDirectorProvider(id));
  }

  /// 页面六态 = 审核态优先,其次由导演台投影接管
  /// (小程序 `applyDetail`:`auditKey 审核中/未通过 ? auditKey : (_directorStatusKey || auditKey)`)。
  /// CANCELLED 也是「已结束」,但胶囊文案另说、核销区随之藏掉。
  ({ClubTopicStatus status, bool cancelled}) _effectiveStatus(
    ClubTopicOverview overview,
    ClubDirectorState? d,
  ) {
    final bool auditWins =
        overview.status == ClubTopicStatus.reviewing ||
        overview.status == ClubTopicStatus.rejected;
    final ClubTopicStatus? mapped =
        auditWins || d == null || d.load != ClubDirectorLoadState.ready
        ? null
        : _sessionStatusKey(d.projection?.status);
    if (mapped == null) {
      return (status: overview.status, cancelled: false);
    }
    return (
      status: mapped,
      cancelled: d!.projection!.status.toUpperCase() == 'CANCELLED',
    );
  }

  /// HO-26 集合时间的当前值。真源是这一场的 `startDate`(与小程序同一条正则),
  /// 拿不到合法时间就不给这一格 —— 宁可不给入口,也不给一个会写错的入口。
  ({String date, String time, String text})? get _opsTime {
    final int activityId = _directorActivityId;
    if (activityId <= 0) return null;
    for (final ClubTopicActivity activity
        in _overview?.activities ?? const <ClubTopicActivity>[]) {
      if (activity.id != activityId) continue;
      final RegExpMatch? match = RegExp(
        r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}:\d{2})(?::\d{2})?$',
      ).firstMatch(activity.startDate);
      if (match == null) return null;
      final String time = match[4]!;
      return (
        date: '${match[1]}-${match[2]}-${match[3]}',
        time: time,
        text: stringsOf(context).clubTopicMeetingDate(int.parse(match[2]!), int.parse(match[3]!), time),
      );
    }
    return null;
  }

  Future<void> _openOpsTimeSheet() async {
    final ({String date, String time, String text})? ops = _opsTime;
    if (ops == null) return;
    final bool? reread = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => _OpsTimeSheet(
        activityId: _directorActivityId,
        date: ops.date,
        time: ops.time,
      ),
    );
    // 成功和「结果未知」都要回读真源(小程序 fetchDetail):新时间从 activityList
    // 重新取,不在本地先改。
    if (reread == true && mounted) await _load(showLoading: false);
  }

  Future<void> _loadRecap() async {
    final int activityId = _recapActivityId;
    if (activityId <= 0) return;
    try {
      final ClubGameSessionGateway gameSessionApi = ref.read(
        gameSessionApiClubProvider,
      );
      final ClubRecapState state = await gameSessionApi.loadClubView(
        activityId: activityId,
      );
      if (!mounted) return;
      setState(() {
        _recap = state;
        _recapError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recap = null;
        _recapError = clubOpsErrorMessage(error, stringsOf(context).clubTopicRecapLoadFailed);
      });
    }
  }

  Future<void> _copyRecap() async {
    final ClubRecapState? state = _recap;
    final int activityId = _recapActivityId;
    if (state == null ||
        !state.exportAvailable ||
        _exporting ||
        activityId <= 0) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicRecapNotReady);
      return;
    }
    setState(() => _exporting = true);
    try {
      final ClubGameSessionGateway gameSessionApi = ref.read(
        gameSessionApiClubProvider,
      );
      final Map<String, dynamic> payload = await gameSessionApi
          .loadClubRecapExport(activityId: activityId);
      await Clipboard.setData(ClipboardData(text: jsonEncode(payload)));
      if (!mounted) return;
      setState(() => _exporting = false);
      CyNativeNotice.show(context, stringsOf(context).clubTopicRecapCopied);
    } catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      CyNativeNotice.show(
        context,
        classifyClubOpsFailure(error).network ? stringsOf(context).clubTopicCopyNetworkFailed : stringsOf(context).clubTopicRecapCopyFailed,
      );
    }
  }

  /// D9 已结束:复盘导出。对应小程序 `ctd-director-recaphead`(note + 复制按钮),
  /// 复盘正文(漏斗/节点完成/榜单)不在这一里程碑;复盘在但不可导出时小程序也是空的,
  /// 所以整段不画。`ended` 用页面六态(审核态可能被导演台投影覆盖成已结束)。
  Widget? _recapSection({required bool ended}) {
    if (!ended || _recapActivityId <= 0) {
      return null;
    }
    final ClubRecapState? state = _recap;
    if (state == null) {
      return ClubOpsSection(
        title: stringsOf(context).clubTopicRecapTitle,
        note: _recapError.isEmpty ? stringsOf(context).clubTopicRecapLoading : _recapError,
        children: <Widget>[
          if (_recapError.isNotEmpty)
            ClubOpsCard(
              children: <Widget>[
                ClubOpsRowLink(
                  key: const Key('topic-recap-retry'),
                  label: stringsOf(context).clubTopicRetry,
                  onTap: _loadRecap,
                ),
              ],
            ),
        ],
      );
    }
    if (!state.recapAvailable) {
      return ClubOpsSection(
        title: stringsOf(context).clubTopicRecapTitle,
        note: stringsOf(context).clubTopicRecapMissing,
        children: <Widget>[],
      );
    }
    if (!state.exportAvailable) return null;
    return ClubOpsSection(
      title: stringsOf(context).clubTopicRecapTitle,
      children: <Widget>[
        ClubOpsCard(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(CyTokens.space4),
              child: CyNativeButton(
                key: const Key('topic-recap-export'),
                label: _exporting ? stringsOf(context).clubTopicCopying : stringsOf(context).clubTopicCopyRecap,
                role: CyNativeButtonRole.secondary,
                width: double.infinity,
                onPressed: _exporting ? null : _copyRecap,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String get _clubPath => '/club/${widget.clubId}';

  void _openStory() {
    context.push('$_clubPath/topic/${widget.topicId}/story');
  }

  void _openEventOps() {
    // 真源 goEventOps(topic-detail js:635)带 clubId&topicId:E-07 起
    // event-ops 会把它预选到本主题。
    context.push('$_clubPath/event-ops?topicId=${widget.topicId}');
  }

  void _openLedger() {
    // 真源 goLedger(topic-detail js:641-644)带 clubId&topicId,
    // enroll 页 E-07 起到达即展开本主题。
    context.push('$_clubPath/enroll?topicId=${widget.topicId}');
  }

  void _openGroupCode() {
    final String query = widget.activityId != null
        ? 'activityId=${widget.activityId}'
        : 'topicId=${widget.topicId}';
    context.push('/club/group-code?$query');
  }

  void _editTopic() {
    // 发布页的编辑主题参数是 `?id=`(`publishEditTopicId` 只认 id);此前推
    // `?topicId=` 会把编辑落进空白新建表单 —— 那是复刻小程序的参数 Bug,修掉。
    context.push('/publish/pro?id=${widget.topicId}');
  }

  /// 底部主键(小程序 `onPrimary` 的落点顺序原样搬):
  ///   未通过 → 改主题;已结束 → 结算报告;没有「这一场」→ 场次管理
  ///   (主键文案此时已是 去开场/去选一场);三段状态流转是**导演台写动作**。
  Future<void> _onPrimary(
    ClubTopicOverview overview,
    ({ClubTopicStatus status, bool cancelled}) eff,
  ) async {
    if (!_primaryPlan(overview, eff).enabled) return;
    final ClubTopicStatus status = eff.status;
    // ⚠️「修改并重新提交」必须排在场次闸**前面**:被拒的主题通常一场都还没开,
    //    导演台对象根本不存在 —— 放在闸后面等于永远走不到。
    if (status == ClubTopicStatus.rejected) {
      _editTopic();
      return;
    }
    if (status == ClubTopicStatus.ended) {
      // 结算报告页由 p4-club-crm(#51)提供 —— 见 PR 说明的跨线依赖一条。
      context.push('$_clubPath/settlement');
      return;
    }
    final int directorId = _directorActivityId;
    if (directorId <= 0 || _stats?.canDirect != true) {
      _openEventOps();
      return;
    }
    switch (status) {
      case ClubTopicStatus.confirmed:
        await _onPrepareSession(directorId);
      case ClubTopicStatus.preparing:
        await _onStartSession(directorId);
      case ClubTopicStatus.running:
      case ClubTopicStatus.selfRun:
        await _onFinishSession(directorId);
      case ClubTopicStatus.rejected:
      case ClubTopicStatus.ended:
      case ClubTopicStatus.reviewing:
        // 都在闸前另走各的去处(rejected→改主题、ended→结算报告),到这里只剩 reviewing。
        break;
    }
  }

  // ─── 导演台三段状态流转(真源 §5.4):
  //   已确认 ──[开始准备]──► 准备中 ──[开始活动]──► 进行中 ──[结束活动]──► 已结束
  // 三句「当前不能…」的闸在页面(确认弹层开出来之前),与小程序
  // onPrepareSession/onStartSession/onFinishSession 的落点一致;
  // 控制器只兜底执行安全(锁定中/没投影/没版本号不发)。
  // 「结束活动」按稿只此一道 T2 居中确认(真源 2026-09-05 审核:不叠双重确认)。

  Future<void> _onPrepareSession(int directorId) async {
    final ClubDirectorProjection? p = ref
        .read(clubDirectorProvider(directorId))
        .projection;
    if (p == null) return;
    if (!p.canPrepare) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicCannotPrepare);
      return;
    }
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).clubTopicPrepareTitle,
      content: stringsOf(context).clubTopicPrepareBody,
      confirmText: stringsOf(context).clubTopicPrepareAction,
    );
    if (!ok || !mounted) return;
    await _directorWrite(
      directorId,
      ref.read(clubDirectorProvider(directorId).notifier).prepare(),
    );
  }

  Future<void> _onStartSession(int directorId) async {
    final ClubDirectorProjection? p = ref
        .read(clubDirectorProvider(directorId))
        .projection;
    if (p == null) return;
    if (!p.canStart) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicNotReady);
      return;
    }
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).clubTopicStartTitle,
      content: stringsOf(context).clubTopicStartBody,
      confirmText: stringsOf(context).clubTopicStartAction,
    );
    if (!ok || !mounted) return;
    await _directorWrite(
      directorId,
      ref.read(clubDirectorProvider(directorId).notifier).start(),
    );
  }

  Future<void> _onFinishSession(int directorId) async {
    final ClubDirectorProjection? p = ref
        .read(clubDirectorProvider(directorId))
        .projection;
    if (p == null) return;
    if (!p.canFinish) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicCannotEnd);
      return;
    }
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).clubTopicEndTitle,
      content:
          stringsOf(context).clubTopicEndSessionBody,
      confirmText: stringsOf(context).clubTopicEndAction,
      cancelText: stringsOf(context).clubTopicReconsider,
      danger: true,
    );
    if (!ok || !mounted) return;
    await _directorWrite(
      directorId,
      ref.read(clubDirectorProvider(directorId).notifier).finish(),
    );
  }

  /// 写回执的话术(executeAction 各分支的 toast;confirmed 不弹 ——
  /// 投影与宿主页一起回读就是最好的确认)。
  Future<void> _directorWrite(
    int directorId,
    Future<ClubDirectorWriteResult> write,
  ) async {
    final ClubDirectorWriteResult result = await write;
    if (!mounted) return;
    clubDirectorNotifyWriteResult(
      context,
      result,
      ref.read(clubDirectorProvider(directorId)),
    );
  }

  /// unknown-write 的两个安全出口(真源 onReconcileUnknownWrite / retryUnknownWrite):
  /// 核对 = 用原 requestId 回读,绝不重发;重试 = 同一 requestId 幂等重放。
  Future<void> _onReconcileUnknownWrite(int directorId) async {
    final ClubDirectorReconcileResult? outcome = await ref
        .read(clubDirectorProvider(directorId).notifier)
        .reconcileOutcome();
    if (!mounted || outcome == null) return;
    CyNativeNotice.show(context, outcome == ClubDirectorReconcileResult.confirmed
        ? stringsOf(context).clubDirectorMessageConfirmedNotice
        : stringsOf(context).clubDirectorMessageRejectedNotice);
  }

  Future<void> _onRetryUnknownWrite(int directorId) async {
    final ClubDirectorController c = ref.read(
      clubDirectorProvider(directorId).notifier,
    );
    final ClubDirectorWriteResult result = await c.retryPending();
    if (!mounted) return;
    if (result == ClubDirectorWriteResult.blocked) {
      // retryPending 只有「存根没存住/没得重试」才会 blocked。
      CyNativeNotice.show(context, stringsOf(context).clubTopicRetryNotSent);
      return;
    }
    clubDirectorNotifyWriteResult(
      context,
      result,
      ref.read(clubDirectorProvider(directorId)),
    );
  }

  /// 底部主键。小程序 `resolvePrimary` 的移植:状态流转(开始准备/开始活动/结束活动)
  /// 是**导演台写动作**,得先有「这一场」且 canDirect;其余人退到「去选一场 / 去开场」,
  /// 两个出口都落在场次管理;连场次管理都没有就不出主键(被转发进来的普通成员
  /// 不该看到一个点进去是管理页的 CTA)。已结束/未通过各有去处,不受此闸。
  ({String text, bool enabled, String hint}) _primaryPlan(
    ClubTopicOverview overview,
    ({ClubTopicStatus status, bool cancelled}) eff,
  ) {
    final ClubTopicStatus status = eff.status;
    final ({String text, bool enabled, String hint}) base = (
      text: _topicPrimaryLabel(context, status),
      enabled: !status.primaryDisabled,
      hint: '',
    );
    const ({String text, bool enabled, String hint}) none = (
      text: '',
      enabled: false,
      hint: '',
    );
    final bool directs = switch (status) {
      ClubTopicStatus.confirmed ||
      ClubTopicStatus.preparing ||
      ClubTopicStatus.running ||
      ClubTopicStatus.selfRun => true,
      _ => false,
    };
    if (!directs) return base;
    // 已经站在某一场上(带 activityId 进来、或恰好一场被认领):写动作只给这一场的导演。
    if (_directorActivityId > 0) {
      return _stats?.canDirect == true ? base : none;
    }
    if (_stats?.canManageSessions != true) return none;
    if (overview.activities.isNotEmpty) {
      return (text: stringsOf(context).clubTopicSelectSession, enabled: true, hint: '');
    }
    // §5-断6:没场次时主键换成「去开场」,原因就地写出来 —— 不留点了没反应的死入口。
    return (text: stringsOf(context).clubTopicCreateSession, enabled: true, hint: stringsOf(context).clubTopicNeedsSession);
  }

  /// 主键文案为空(小程序 `primary.text = ''`)时整条不出。
  List<Widget> _footer(
    ClubTopicOverview overview,
    ({ClubTopicStatus status, bool cancelled}) eff,
  ) {
    final ({String text, bool enabled, String hint}) plan = _primaryPlan(
      overview,
      eff,
    );
    if (plan.text.isEmpty) return const <Widget>[];
    return <Widget>[
      CyFooterBar(
        primary: CyNativeButton(
          key: const Key('topic-detail-primary'),
          label: plan.text,
          width: double.infinity,
          onPressed: plan.enabled ? () => _onPrimary(overview, eff) : null,
        ),
      ),
    ];
  }

  Future<void> _openSettingSheet() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) => _TopicSettingSheet(
        clubId: widget.clubId,
        topicId: widget.topicId,
        canManageSessions: _stats?.canManageSessions ?? false,
        onEditTopic: _editTopic,
        onStory: _openStory,
        onLedger: _openLedger,
        onSessions: _openEventOps,
        onEnded: _load,
      ),
    );
  }

  Future<void> _openMerchants() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _SheetFrame(
        title: stringsOf(context).clubTopicMerchants,
        sheetKey: const Key('topic-merchants-sheet'),
        child: _MerchantsBody(clubId: widget.clubId, topicId: widget.topicId),
      ),
    );
  }

  Future<void> _openCustomers() async {
    var wantBroadcast = false;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _SheetFrame(
        title: stringsOf(context).clubTopicMembers,
        sheetKey: const Key('topic-customers-sheet'),
        child: _CustomersBody(
          clubId: widget.clubId,
          topicId: widget.topicId,
          onBroadcast: () => wantBroadcast = true,
        ),
      ),
    );
    // 真源 goBroadcast:先收掉成员半屏,再开广播半屏。
    if (wantBroadcast && mounted) await _openBroadcastSheet();
  }

  /// 小程序 `openBroadcast` 的闸:锁定中不出;不能发就当场说清楚。
  Future<void> _openBroadcastSheet() async {
    final int directorId = _directorActivityId;
    if (directorId <= 0) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicBroadcastDenied);
      return;
    }
    final ClubDirectorState s = ref.read(clubDirectorProvider(directorId));
    if (s.writeLocked) return;
    if (s.projection?.canBroadcast != true) {
      CyNativeNotice.show(context, stringsOf(context).clubTopicBroadcastDenied);
      return;
    }
    await ClubDirectorBroadcastSheet.open(context, ref, directorId);
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final ClubTopicOverview? overview = _overview;
    final ClubDirectorState? d = _directorState;
    // 每一次被服务端确认的写都要带着宿主一起回读(director.js executeAction
    // 成功后同时 loadProjection + fetchDetail:核销数/场次/时间都在变)。
    if (d != null && overview != null) {
      final int directorId = _directorActivityId;
      ref.listen(clubDirectorProvider(directorId), (
        ClubDirectorState? prev,
        ClubDirectorState next,
      ) {
        if (prev != null && next.refreshTick != prev.refreshTick && mounted) {
          _load(showLoading: false);
        }
      });
    }
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubTopicTitle),
              Expanded(child: _body()),
              if (_stage == ClubOpsLoadState.ready && overview != null)
                ..._footer(overview, _effectiveStatus(overview, d)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 401 排在四态之前:登录过期既不是「没权限」也不是「网络差」,
    // 重试不改登录态就是死路 —— 就地给登录门(#258)。
    if (_loginRequired) {
      return ClubLoginGate(message: stringsOf(context).clubTopicLogin, onSignedIn: () => _load());
    }
    switch (_stage) {
      case ClubOpsLoadState.loading:
        return CySkeleton(
          type: CySkeletonType.card,
          count: 4,
          label: stringsOf(context).clubTopicLoading,
        );
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).clubTopicDenied,
          sub: _error.isEmpty ? stringsOf(context).clubTopicDeniedBody : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).clubTopicNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          // 小程序 retry="重新连接" —— 断网后是「重连」不是泛泛的「重试」。
          retryLabel: stringsOf(context).clubTopicReconnect,
          onRetry: _load,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: stringsOf(context).clubTopicUnavailable,
          sub: _error.isEmpty ? stringsOf(context).clubTopicUnavailableBody : _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.ready:
        return _readyBody(_overview!, _stats!);
    }
  }

  Widget _readyBody(ClubTopicOverview overview, ClubTopicManageStats stats) {
    final ({String date, String time, String text})? opsTime = _opsTime;
    final ClubDirectorState? d = _directorState;
    final ({ClubTopicStatus status, bool cancelled}) eff = _effectiveStatus(
      overview,
      d,
    );
    final ({String text, bool enabled, String hint}) plan = _primaryPlan(
      overview,
      eff,
    );
    final ClubDirectorProjection? p =
        d != null && d.load == ClubDirectorLoadState.ready
        ? d.projection
        : null;
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        _HeroHeader(
          overview: overview,
          stats: stats,
          status: eff.status,
          cancelled: eff.cancelled,
        ),
        _QuickActions(
          onMerchant: _openMerchants,
          onCustomer: _openCustomers,
          onGroupCode: _openGroupCode,
          onMore: _openSettingSheet,
        ),
        if (overview.status.showsRejectReason &&
            overview.rejectReason.isNotEmpty)
          ClubOpsSection(
            title: stringsOf(context).clubTopicRejectionReason,
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(CyTokens.space4),
                    child: Text(
                      overview.rejectReason,
                      key: const Key('topic-detail-reject-reason'),
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        height: 1.5,
                        color: CyTokens.statusDanger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        // 核销区的唯一真源:状态 + canViewVerify(主理人/管理员/核销员同判据);
        // 局被取消时随之藏掉(小程序 applyVerifyVisibility)。
        if (eff.status.showsVerify && stats.canViewVerify && !eff.cancelled)
          _VerifySection(stats: stats, onLedger: _openLedger),
        ClubOpsSection(
          title: stringsOf(context).clubTopicTopic,
          children: <Widget>[
            _TopicCard(overview: overview, stats: stats, onTap: _openStory),
          ],
        ),
        if (overview.status.showsSessions && overview.sessions.isNotEmpty)
          ClubOpsSection(
            title: stringsOf(context).clubTopicNext,
            trailing: stats.canManageSessions
                ? ClubOpsRowLink(
                    key: const Key('topic-detail-manage-sessions'),
                    label: stringsOf(context).clubTopicManageSessions,
                    onTap: _openEventOps,
                  )
                : null,
            children: <Widget>[
              ClubOpsCard(
                children: overview.sessions
                    .map((ClubTopicSession s) => _SessionRow(session: s))
                    .toList(growable: false),
              ),
            ],
          ),
        // 导演台读取态 + unknown-write 安全出口(真源 directorActive 状态块)。
        ..._directorStatesBlock(d),
        // HO-26 集合时间:真源 `directorActive && loadState === 'ready'`,
        // 导演台没读到就不给这个入口。
        if (opsTime != null && (d == null || p != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space4,
              CyTokens.pageX,
              0,
            ),
            child: ClubOpsCard(
              children: <Widget>[
                ClubOpsRow(
                  key: const Key('topic-ops-time'),
                  title: stringsOf(context).clubTopicMeetingTime,
                  value: opsTime.text,
                  valueColor: CyPalette.of(context).textPrimary,
                  trailing: ClubOpsRowLink(
                    key: const Key('topic-ops-time-edit'),
                    label: stringsOf(context).clubTopicChange,
                    onTap: _openOpsTimeSheet,
                  ),
                  onTap: _openOpsTimeSheet,
                ),
              ],
            ),
          ),
        // D1 准备总览:只在「准备中」态出,其余状态它没有意义。
        ..._directorReadyBlocks(d, p, eff, palette),
        // 收编时别把这句丢了:它挡着「把没下发读成零进度」的误读。
        if (p != null && p.stations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.pageX,
              vertical: CyTokens.space4,
            ),
            child: StatusView(
              message: stringsOf(context).clubTopicNoNodeStatus,
              sub: stringsOf(context).clubTopicNoNodeStatusBody,
              icon: CupertinoIcons.number,
            ),
          ),
        if (p != null && p.canUnlockChapter)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space4,
              CyTokens.pageX,
              0,
            ),
            child: Text(
              stringsOf(context).clubTopicChapterStateOnly,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
        ?_recapSection(ended: eff.status == ClubTopicStatus.ended),
        if (plan.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space4,
              CyTokens.pageX,
              0,
            ),
            child: Text(
              plan.hint,
              key: const Key('topic-detail-session-hint'),
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
        // E-04:导演台四个弹层的入口,一个都没有时整条不出。
        ..._directorTools(d, p),
      ],
    );
  }

  /// 真源 directorActive 状态块:loading/business-error/network-error/empty/ready
  /// (ready 时只剩 unknown-write 安全出口;数据区在下面各归各位)。
  List<Widget> _directorStatesBlock(ClubDirectorState? d) {
    if (d == null) return const <Widget>[];
    final int directorId = _directorActivityId;
    const EdgeInsetsGeometry pad = EdgeInsets.fromLTRB(
      CyTokens.pageX,
      CyTokens.space4,
      CyTokens.pageX,
      0,
    );
    // 读投影被 401 挡下(多半是登录中 token 过期):格子换成登录引导,
    // 不说「暂时无法打开/网络不可用」(#258 同口径)。
    if (d.loginRequired) {
      return <Widget>[
        Padding(
          padding: pad,
          child: ClubLoginGate(
            message: stringsOf(context).clubTopicDirectorLogin,
            onSignedIn: () =>
                ref.read(clubDirectorProvider(directorId).notifier).load(),
          ),
        ),
      ];
    }
    switch (d.load) {
      case ClubDirectorLoadState.loading:
        return const <Widget>[
          Padding(
            padding: pad,
            child: CySkeleton(type: CySkeletonType.card, count: 4),
          ),
        ];
      case ClubDirectorLoadState.businessError:
        return <Widget>[
          Padding(
            padding: pad,
            child: StatusView(
              message: stringsOf(context).clubTopicDirectorFailed,
              sub: clubDirectorErrorMessage(context, d),
              icon: CupertinoIcons.exclamationmark_triangle,
              onRetry: () =>
                  ref.read(clubDirectorProvider(directorId).notifier).load(),
              retryLabel: stringsOf(context).clubTopicReload,
            ),
          ),
        ];
      case ClubDirectorLoadState.networkError:
        return <Widget>[
          Padding(
            padding: pad,
            child: StatusView(
              message: stringsOf(context).clubTopicNetworkFailed,
              sub: clubDirectorErrorMessage(context, d),
              icon: CupertinoIcons.exclamationmark_triangle,
              onRetry: () =>
                  ref.read(clubDirectorProvider(directorId).notifier).load(),
              retryLabel: stringsOf(context).clubTopicReconnect,
            ),
          ),
        ];
      case ClubDirectorLoadState.empty:
        return <Widget>[
          Padding(
            padding: pad,
            child: StatusView(
              message: stringsOf(context).clubTopicNoSession,
              sub: d.errorText.isEmpty ? stringsOf(context).clubTopicNoSessionBody : clubDirectorErrorMessage(context, d),
              icon: CupertinoIcons.gamecontroller,
            ),
          ),
        ];
      case ClubDirectorLoadState.ready:
        return <Widget>[
          ClubDirectorUnknownBar(
            state: d,
            onReconcile: () => _onReconcileUnknownWrite(directorId),
            onRetry: () => _onRetryUnknownWrite(directorId),
          ),
        ];
    }
  }

  /// D1 准备总览(小程序 `cy-club-director-ready`):节点状态 + 队伍进度 +
  /// 「开始活动」主键 + writeMessage caption。
  List<Widget> _directorReadyBlocks(
    ClubDirectorState? d,
    ClubDirectorProjection? p,
    ({ClubTopicStatus status, bool cancelled}) eff,
    CyPalette palette,
  ) {
    if (d == null || p == null || eff.status != ClubTopicStatus.preparing) {
      return const <Widget>[];
    }
    return <Widget>[
      ClubOpsSection(
        title: stringsOf(context).clubTopicPreparationOverview,
        caption: d.writeMessage.isEmpty ? null : clubDirectorWriteMessage(context, d),
        children: <Widget>[
          ClubDirectorSectionTitle(stringsOf(context).clubTopicNodeStatus),
          Padding(
            padding: const EdgeInsets.only(
              left: CyTokens.pageX,
              bottom: CyTokens.space2,
            ),
            child: Text(
              ClubDirectorLabels(context).readiness(p.readiness),
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
          ClubDirectorRowList(rows: clubDirectorStationRows(p.stations, context: context)),
          ClubDirectorSectionTitle(stringsOf(context).clubTopicTeamProgress),
          Padding(
            padding: const EdgeInsets.only(
              left: CyTokens.pageX,
              bottom: CyTokens.space2,
            ),
            child: Text(
              ClubDirectorLabels(context).sessionStatus(p.status),
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
          ClubDirectorRowList(rows: clubDirectorTeamRows(p.teams, context: context)),
          const SizedBox(height: CyTokens.space4),
          // 「开始活动」在非法态是**禁用**,不是消失 —— 主理人得看见自己卡在哪。
          CyNativeButton(
            key: const Key('topic-director-d1-start'),
            label: stringsOf(context).clubTopicStartAction,
            width: double.infinity,
            onPressed: !p.canStart || d.writeLocked
                ? null
                : () => _onStartSession(_directorActivityId),
          ),
        ],
      ),
    ];
  }

  /// ctd-tools:真源同判据 —— 工具条只在导演台就绪且至少还有一个工具时出;
  /// 每个工具各按各的闸(手动解锁 canUnlockChapter / 队伍进度有行 /
  /// 角色分配 canAssignRoles 且有成员 / 现场事件有行)。
  List<Widget> _directorTools(ClubDirectorState? d, ClubDirectorProjection? p) {
    if (d == null || p == null || d.load != ClubDirectorLoadState.ready) {
      return const <Widget>[];
    }
    final bool hasTeamRows = clubDirectorTeamRows(p.teams, context: context).isNotEmpty;
    final bool hasMemberRows = p.canAssignRoles && p.roleMemberRows.isNotEmpty;
    final List<({String label, Key key, Future<void> Function() open})>
    tools = <({String label, Key key, Future<void> Function() open})>[
      if (p.canUnlockChapter)
        (
          label: stringsOf(context).clubTopicUnlockChapter,
          key: const Key('director-tool-unlock'),
          open: () =>
              ClubDirectorChapterSheet.open(context, ref, _directorActivityId),
        ),
      if (hasTeamRows)
        (
          label: stringsOf(context).clubTopicTeamProgress,
          key: const Key('director-tool-teams'),
          open: () =>
              ClubDirectorTeamSheet.open(context, ref, _directorActivityId),
        ),
      if (hasMemberRows)
        (
          label: stringsOf(context).clubTopicAssignRoles,
          key: const Key('director-tool-roles'),
          open: () =>
              ClubDirectorRoleSheet.open(context, ref, _directorActivityId),
        ),
      if (p.incidents.isNotEmpty)
        (
          label: stringsOf(context).clubTopicIncidents,
          key: const Key('director-tool-incidents'),
          open: () =>
              ClubDirectorIncidentSheet.open(context, ref, _directorActivityId),
        ),
    ];
    if (tools.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space5,
          CyTokens.pageX,
          0,
        ),
        child: Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: tools
              .map(
                (({String label, Key key, Future<void> Function() open}) t) =>
                    CyNativeButton(
                      key: t.key,
                      label: t.label,
                      role: CyNativeButtonRole.secondary,
                      onPressed: d.writeLocked ? null : () => t.open(),
                    ),
              )
              .toList(growable: false),
        ),
      ),
    ];
  }
}

/// ① Hero:封面 + 商家 logo + 状态胶囊 + 标题 + meta + chips。
/// `status` 是页面六态(审核态优先,其次被导演台投影接管),`cancelled`
/// 给胶囊换「已取消」三个字(真源:`ended && _sessionCancelled`)。
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.overview,
    required this.stats,
    required this.status,
    this.cancelled = false,
  });

  final ClubTopicOverview overview;
  final ClubTopicManageStats stats;
  final ClubTopicStatus status;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CyNetImage(
                    overview.cover,
                    fit: BoxFit.cover,
                    fallback: ColoredBox(color: palette.bgSurfaceSubtle),
                  ),
                  // 封面压一层 scrim,保证白字在浅色封面上也读得清。
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x00000000), Color(0x99000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: CyTokens.space3,
                    bottom: CyTokens.space3,
                    right: CyTokens.space3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _StatusCapsule(status: status, cancelled: cancelled),
                        const SizedBox(height: CyTokens.space2),
                        Text(
                          overview.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CyTokens.typeCardTitle,
                            fontWeight: FontWeight.w700,
                            color: palette.textInverse,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (overview.merchantLogo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space2),
                  child: CyNetImage(
                    overview.merchantLogo,
                    width: 32,
                    height: 32,
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    fallback: const SizedBox.shrink(),
                  ),
                ),
              if (overview.dateRangeText.isNotEmpty)
                _MetaLine(
                  icon: CupertinoIcons.calendar,
                  text: overview.dateRangeText,
                ),
              if (overview.verifyModeText.isNotEmpty)
                _MetaLine(
                  icon: CupertinoIcons.time,
                  text: overview.verifyModeText,
                ),
              if (overview.chipsOf(stats).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: CyTokens.space2),
                  child: Wrap(
                    spacing: CyTokens.space2,
                    runSpacing: CyTokens.space2,
                    children: overview
                        .chipsOf(stats)
                        .map((String text) => _Chip(label: text))
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space1),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: palette.textTertiary),
          const SizedBox(width: CyTokens.space1_5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({required this.status, this.cancelled = false});

  final ClubTopicStatus status;

  /// 局被取消:胶囊读「已取消」,点位色仍按已结束。
  final bool cancelled;

  Color _dotColor(CyPalette palette) {
    switch (status) {
      case ClubTopicStatus.reviewing:
        return CyTokens.statusInfo;
      case ClubTopicStatus.rejected:
        return CyTokens.statusDanger;
      case ClubTopicStatus.confirmed:
      case ClubTopicStatus.preparing:
        return CyTokens.statusWarning;
      case ClubTopicStatus.running:
      case ClubTopicStatus.selfRun:
        return CyTokens.statusSuccess;
      case ClubTopicStatus.ended:
        return palette.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      key: const Key('topic-detail-status'),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: palette.overlay,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _dotColor(palette),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: CyTokens.space1_5),
          Text(
            cancelled ? stringsOf(context).clubTopicCancelled : _topicStatusLabel(context, status),
            style: TextStyle(
              fontSize: CyTokens.typeMicro,
              fontWeight: FontWeight.w600,
              color: palette.textInverse,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: CyTokens.typeMicro,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// ② 四圆钮:商家 · 成员 · 团码 · 更多(整块属于头部,与 logo/标题同一套基准)。
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onMerchant,
    required this.onCustomer,
    required this.onGroupCode,
    required this.onMore,
  });

  final VoidCallback onMerchant;
  final VoidCallback onCustomer;
  final VoidCallback onGroupCode;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 四圆钮是一整块导航(小程序 aria-label="活动快捷入口"),
      // 读屏时四个孤立图标读不出它们是一组。
      container: true,
      label: stringsOf(context).clubTopicQuickEntries,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space4,
          CyTokens.pageX,
          0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _QuickAction(
              actionKey: const Key('topic-detail-quick-merchant'),
              icon: CupertinoIcons.briefcase,
              label: stringsOf(context).clubTopicMerchants,
              onTap: onMerchant,
            ),
            _QuickAction(
              actionKey: const Key('topic-detail-quick-customer'),
              icon: CupertinoIcons.person_2,
              label: stringsOf(context).clubTopicMembers,
              onTap: onCustomer,
            ),
            _QuickAction(
              actionKey: const Key('topic-detail-quick-groupcode'),
              icon: CupertinoIcons.qrcode,
              label: stringsOf(context).clubTopicGroupCode,
              onTap: onGroupCode,
            ),
            _QuickAction(
              actionKey: const Key('topic-detail-quick-more'),
              icon: CupertinoIcons.ellipsis,
              label: stringsOf(context).clubTopicMore,
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return GestureDetector(
      key: actionKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: palette.textPrimary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            label,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// ④ 核销(H4/H5/H6)。已结束也出这一区:下架的主题照样可能有人没核销。
class _VerifySection extends StatelessWidget {
  const _VerifySection({required this.stats, required this.onLedger});

  final ClubTopicManageStats stats;
  final VoidCallback onLedger;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClubOpsSection(
      title: stringsOf(context).clubTopicCheckin,
      trailing: Semantics(
        // 小程序: aria-label="打开核销台账"(可见字仍是「台账」)
        button: true,
        excludeSemantics: true,
        label: stringsOf(context).clubTopicOpenLedger,
        child: ClubOpsRowLink(
          key: const Key('topic-detail-ledger'),
          label: stringsOf(context).clubTopicLedger,
          onTap: onLedger,
        ),
      ),
      children: <Widget>[
        ClubOpsCard(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space4,
                vertical: CyTokens.space3,
              ),
              child: Row(
                children: stats.verifyMetrics
                    .map(
                      (({String label, int value}) metric) => Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              '${metric.value}',
                              style: TextStyle(
                                fontSize: CyTokens.typeDisplay,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              metric.label,
                              style: TextStyle(
                                fontSize: CyTokens.typeCaption,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ⑤ 主题:封面 + 名称 + 结构 + 两枚软胶囊 + 打开剧情与玩法。
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.overview,
    required this.stats,
    required this.onTap,
  });

  final ClubTopicOverview overview;
  final ClubTopicManageStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClubOpsCard(
      children: <Widget>[
        ClubOpsRow(
          key: const Key('topic-detail-story'),
          title: overview.name,
          meta: overview.structureTextOf(stats),
          leading: SizedBox(
            width: 52,
            height: 52,
            child: CyNetImage(
              overview.cover,
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              fallback: ColoredBox(color: palette.bgSurfaceSubtle),
            ),
          ),
          value: stringsOf(context).clubTopicOpenStory,
          onTap: onTap,
        ),
        if (overview.statusChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.space4,
              0,
              CyTokens.space4,
              CyTokens.space3,
            ),
            child: Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space1,
              children: overview.statusChips
                  .map(
                    (({String text, bool success}) chip) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: chip.success
                            ? CyTokens.statusSuccess.withValues(alpha: 0.14)
                            : palette.bgSurfaceSubtle,
                        borderRadius: BorderRadius.circular(
                          CyTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        chip.text,
                        style: TextStyle(
                          fontSize: CyTokens.typeMicro,
                          color: chip.success
                              ? CyTokens.statusSuccess
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}

/// ⑥ 接下来:一场一行(时间 / 谁 / 预计 / 类型)。
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final ClubTopicSession session;

  @override
  Widget build(BuildContext context) {
    final String meta = <String>[
      session.whoText,
      session.etaText,
    ].where((String s) => s.isNotEmpty).join(' · ');
    return ClubOpsRow(
      key: Key('topic-detail-session-${session.id}'),
      title: session.whenText.isEmpty ? stringsOf(context).clubTopicTimePending : session.whenText,
      meta: meta.isEmpty ? null : meta,
      value: session.kindText,
    );
  }
}

/// 半屏 sheet 的公共外壳:标题 + 关闭 + 可滚动内容。
/// ★ 材质交给系统 [CupertinoPopupSurface](iOS 弹窗材质:半透明 + 模糊 + 饱和),
///   不再自绘 `bgPage` 实色卡片 —— 自绘的那张和页面同色,除了遮罩外**看不出层次**。
///   真玻璃由原生桥负责(iOS 26+);这里是 Flutter 回退路径。
/// ★ 顶部圆角取 [CupertinoPopupSurface] 自己的 13,底部贴屏边不圆。
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child, this.sheetKey});

  final String title;
  final Widget child;
  final Key? sheetKey;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      child: CupertinoPopupSurface(
        child: Container(
          key: sheetKey,
          // 原生 sheet 停位 = 屏高减一个顶部间隙(SDK 默认 topGap 0.08 → 92%)。
          // 原先的 0.78 是照小程序压出来的,App 没有胶囊要避让,该高就高。
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.space3,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('sheet-close'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 24,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma J4「更多」= 主题设置:入口行 + 三个开关 + 章节承接 + 结束主题。
/// 一次请求(`topic-setting/detail`)喂整张半屏;`denied` / `error` 两态各自成屏。
class _TopicSettingSheet extends ConsumerStatefulWidget {
  const _TopicSettingSheet({
    required this.clubId,
    required this.topicId,
    required this.canManageSessions,
    required this.onEditTopic,
    required this.onStory,
    required this.onLedger,
    required this.onSessions,
    required this.onEnded,
  });

  final int clubId;
  final int topicId;
  final bool canManageSessions;
  final VoidCallback onEditTopic;
  final VoidCallback onStory;
  final VoidCallback onLedger;
  final VoidCallback onSessions;
  final Future<void> Function() onEnded;

  @override
  ConsumerState<_TopicSettingSheet> createState() => _TopicSettingSheetState();
}

class _TopicSettingSheetState extends ConsumerState<_TopicSettingSheet> {
  ClubOpsLoadState _stage = ClubOpsLoadState.loading;
  TopicSetting? _setting;
  String _error = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stage = ClubOpsLoadState.loading;
      _error = '';
    });
    try {
      final TopicSetting setting = await ref
          .read(clubTopicOpsApiProvider)
          .settingDetail(clubId: widget.clubId, topicId: widget.topicId);
      if (!mounted) return;
      setState(() {
        _setting = setting;
        _stage = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubTopicSettingsRetryLater);
      });
    }
  }

  /// 三个开关**一起**提交(后端少收一个就拒绝,不会把没传的当 false 关掉)。
  /// 存不上就把开关拨回去:留在新位置等于骗人说存住了。
  Future<void> _toggle({
    required bool coopOpen,
    required bool pinned,
    required bool memberOnly,
  }) async {
    final TopicSetting? before = _setting;
    if (before == null || !before.canManage || _saving) return;
    setState(() {
      _saving = true;
      _setting = TopicSetting(
        topicName: before.topicName,
        lifecycleText: before.lifecycleText,
        coopOpen: coopOpen,
        pinned: pinned,
        memberOnly: memberOnly,
        canManage: before.canManage,
        chapters: before.chapters,
      );
    });
    try {
      final TopicSetting saved = await ref
          .read(clubTopicOpsApiProvider)
          .saveSetting(
            clubId: widget.clubId,
            topicId: widget.topicId,
            coopOpen: coopOpen,
            pinned: pinned,
            memberOnly: memberOnly,
          );
      if (!mounted) return;
      setState(() {
        _setting = saved;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _setting = before;
        _saving = false;
      });
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubTopicSaveFailed),
        isError: true,
      );
    }
  }

  Future<void> _toggleChapterRecruit(TopicSettingChapter chapter) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clubTopicOpsApiProvider)
          .chapterRecruit(chapterId: chapter.id, enabled: !chapter.recruiting);
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
      if (!mounted) return;
      CyNativeNotice.show(context, chapter.recruiting ? stringsOf(context).clubTopicMerchantClosed : stringsOf(context).clubTopicMerchantOpened);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubTopicChangeFailed),
        isError: true,
      );
    }
  }

  Future<void> _finishChapter(TopicSettingChapter chapter) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clubTopicOpsApiProvider)
          .chapterFinish(chapterId: chapter.id);
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubTopicChapterEndFailed),
        isError: true,
      );
    }
  }

  Future<void> _openRules() async {
    Navigator.of(context).pop();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _SheetFrame(
        title: stringsOf(context).clubTopicExitRules,
        sheetKey: Key('topic-rules-sheet'),
        child: _RulesBody(),
      ),
    );
  }

  Future<void> _openEndTopic() async {
    final TopicSetting? setting = _setting;
    if (setting == null || !setting.canManage) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (_) => _EndTopicDialog(
        clubId: widget.clubId,
        topicId: widget.topicId,
        topicName: setting.topicName,
        onEnded: (TopicEndResult result) async {
          if (mounted) {
            CyNativeNotice.show(context, result.summaryText);
          }
          await widget.onEnded();
          if (mounted) await _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: stringsOf(context).clubTopicMore,
      sheetKey: const Key('topic-setting-sheet'),
      child: _body(),
    );
  }

  Widget _body() {
    switch (_stage) {
      case ClubOpsLoadState.loading:
        return const Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: CySkeleton(type: CySkeletonType.card, count: 3),
        );
      case ClubOpsLoadState.noPermission:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicRoleDenied,
            sub: stringsOf(context).clubTopicSettingsPermission,
            icon: CupertinoIcons.lock,
          ),
        );
      case ClubOpsLoadState.networkError:
      case ClubOpsLoadState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicSettingsFailed,
            sub: _error.isEmpty ? stringsOf(context).clubTopicRetryLater : _error,
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: _load,
          ),
        );
      case ClubOpsLoadState.ready:
        return _readyBody(_setting!);
    }
  }

  Widget _readyBody(TopicSetting setting) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            setting.topicName,
            style: TextStyle(
              fontSize: CyTokens.typeCardTitle,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (setting.lifecycleText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                setting.lifecycleText,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          ClubOpsCard(
            children: <Widget>[
              ClubOpsRow(
                key: const Key('topic-setting-edit'),
                title: stringsOf(context).clubTopicEditContent,
                meta: stringsOf(context).clubTopicEditContentBody,
                metaLines: 2,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onEditTopic();
                },
              ),
              ClubOpsRow(
                key: const Key('topic-setting-story'),
                title: stringsOf(context).clubTopicStory,
                meta: stringsOf(context).clubTopicStoryBody,
                metaLines: 2,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onStory();
                },
              ),
              ClubOpsRow(
                key: const Key('topic-setting-ledger'),
                title: stringsOf(context).clubTopicCheckinLedger,
                meta: stringsOf(context).clubTopicLedgerBody,
                metaLines: 2,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onLedger();
                },
              ),
              if (widget.canManageSessions)
                ClubOpsRow(
                  key: const Key('topic-setting-sessions'),
                  title: stringsOf(context).clubTopicSessionManagement,
                  meta: stringsOf(context).clubTopicSessionManagementBody,
                  metaLines: 2,
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSessions();
                  },
                ),
              Semantics(
                button: true,
                label: stringsOf(context).clubTopicViewRules,
                child: ClubOpsRow(
                  key: const Key('topic-setting-rules'),
                  title: stringsOf(context).clubTopicExitRules,
                  meta: stringsOf(context).clubTopicRulesBody,
                  metaLines: 2,
                  onTap: _openRules,
                ),
              ),
            ],
          ),
          _sectionLabel(stringsOf(context).clubTopicMerchantConnections),
          ClubOpsCard(
            children: <Widget>[
              _SwitchRow(
                rowKey: const Key('topic-setting-coop'),
                title: stringsOf(context).clubTopicMerchantParticipation,
                meta: stringsOf(context).clubTopicMerchantParticipationBody,
                value: setting.coopOpen,
                enabled: setting.canManage && !_saving,
                onChanged: (bool next) => _toggle(
                  coopOpen: next,
                  pinned: setting.pinned,
                  memberOnly: setting.memberOnly,
                ),
              ),
            ],
          ),
          if (setting.chapters.isNotEmpty) ...<Widget>[
            _sectionLabel(stringsOf(context).clubTopicChapters),
            ClubOpsCard(
              children: setting.chapters
                  .map(
                    (TopicSettingChapter chapter) => ClubOpsRow(
                      key: Key('topic-setting-chapter-${chapter.id}'),
                      title: chapter.name.isEmpty ? stringsOf(context).clubTopicUnnamedChapter : chapter.name,
                      meta: chapter.finished ? stringsOf(context).clubTopicChapterEnded : stringsOf(context).clubTopicManageMerchants,
                      value: chapter.recruitingText,
                      valueColor: chapter.recruiting
                          ? null
                          : palette.textDisabled,
                      enabled: setting.canManage && !_saving,
                      onTap: () => _openChapterActions(chapter),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          _sectionLabel(stringsOf(context).clubTopicClubDisplay),
          ClubOpsCard(
            children: <Widget>[
              _SwitchRow(
                rowKey: const Key('topic-setting-pinned'),
                title: stringsOf(context).clubTopicPin,
                meta: stringsOf(context).clubTopicPinBody,
                value: setting.pinned,
                enabled: setting.canManage && !_saving,
                onChanged: (bool next) => _toggle(
                  coopOpen: setting.coopOpen,
                  pinned: next,
                  memberOnly: setting.memberOnly,
                ),
              ),
              _SwitchRow(
                rowKey: const Key('topic-setting-member-only'),
                title: stringsOf(context).clubTopicMembersOnly,
                meta: stringsOf(context).clubTopicMembersOnlyBody,
                value: setting.memberOnly,
                enabled: setting.canManage && !_saving,
                onChanged: (bool next) => _toggle(
                  coopOpen: setting.coopOpen,
                  pinned: setting.pinned,
                  memberOnly: next,
                ),
              ),
            ],
          ),
          // 不再拿「还在售卖」当出现条件:已经下架的主题照样可能有已付款未核销的票要退。
          if (setting.canManage)
            ClubOpsCard(
              children: <Widget>[
                ClubOpsRow(
                  key: const Key('topic-setting-end'),
                  title: stringsOf(context).clubTopicEndTopic,
                  titleColor: CyTokens.statusDanger,
                  meta: stringsOf(context).clubTopicEndRefundBody,
                  metaLines: 2,
                  onTap: _openEndTopic,
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              stringsOf(context).clubTopicManualRefundBody,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChapterActions(TopicSettingChapter chapter) async {
    final _ChapterAction? action =
        await showCupertinoModalPopup<_ChapterAction>(
          context: context,
          builder: (BuildContext sheetContext) => CupertinoActionSheet(
            title: Text(chapter.name.isEmpty ? stringsOf(context).clubTopicUnnamedChapter : chapter.name),
            actions: <Widget>[
              if (!chapter.finished)
                CupertinoActionSheetAction(
                  key: Key('topic-setting-chapter-recruit-${chapter.id}'),
                  onPressed: () => Navigator.of(
                    sheetContext,
                  ).pop(_ChapterAction.toggleRecruit),
                  child: Text(chapter.recruiting ? stringsOf(context).clubTopicCloseMerchantParticipation : stringsOf(context).clubTopicMerchantParticipation),
                ),
              if (!chapter.finished)
                CupertinoActionSheetAction(
                  key: Key('topic-setting-chapter-finish-${chapter.id}'),
                  isDestructiveAction: true,
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_ChapterAction.finish),
                  child: Text(stringsOf(context).clubTopicEndChapter),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(stringsOf(context).clubTopicCancel),
            ),
          ),
        );
    if (action == null || !mounted) return;
    switch (action) {
      case _ChapterAction.toggleRecruit:
        await _toggleChapterRecruit(chapter);
      case _ChapterAction.finish:
        await _finishChapter(chapter);
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CyTokens.space4,
        bottom: CyTokens.space1,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: CyTokens.typeCaption,
          fontWeight: FontWeight.w600,
          color: CyPalette.of(context).textTertiary,
        ),
      ),
    );
  }
}

enum _ChapterAction { toggleRecruit, finish }

/// 开关行:标题 + 说明 + 原生开关(内容层用 Cupertino,不挂平台视图)。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.rowKey,
    required this.title,
    required this.meta,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key rowKey;
  final String title;
  final String meta;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClubOpsRow(
      key: rowKey,
      title: title,
      meta: meta,
      metaLines: 2,
      enabled: enabled,
      trailing: CupertinoSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// J5 结束主题确认(T2 居中,无顶栏无 ✕)。
///
/// ⚠️ 弹层**不自己关**:失败时把后端的原话留在屏幕上让人再点一次 ——
///   只报「已结束」会让主理人以为钱全退干净了(manualOrders 必须照实说)。
class _EndTopicDialog extends ConsumerStatefulWidget {
  const _EndTopicDialog({
    required this.clubId,
    required this.topicId,
    required this.topicName,
    required this.onEnded,
  });

  final int clubId;
  final int topicId;
  final String topicName;
  final Future<void> Function(TopicEndResult result) onEnded;

  @override
  ConsumerState<_EndTopicDialog> createState() => _EndTopicDialogState();
}

class _EndTopicDialogState extends ConsumerState<_EndTopicDialog> {
  bool _submitting = false;
  String _errorText = '';


  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorText = '';
    });
    try {
      final TopicEndResult result = await ref
          .read(clubTopicOpsApiProvider)
          .endTopic(clubId: widget.clubId, topicId: widget.topicId);
      if (!mounted) return;
      if (result.hasFailures) {
        // 有场次没退成:框不关,把是哪一场、为什么留在屏幕上,让人能再点一次。
        setState(() {
          _submitting = false;
          _errorText =
              stringsOf(context).clubTopicFailedSessions(result.failedSessions.length, result.failedSessions.first);
        });
        return;
      }
      Navigator.of(context).pop();
      await widget.onEnded(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // 后端的拒绝文案是写给主理人看的(「当前岗位没有这个权限」「主题状态刚刚变过」),
        // 原样回显。
        _errorText =
            error is ClubApiException && error.message.trim().isNotEmpty
            ? error.message
            : stringsOf(context).clubTopicEndNetworkFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      // 标题与小程序 `结束这场活动？` 同一句;主题名放正文,
      // 因为标题里插名字会把原文句子打断(「结束主题「X」？」读起来是两句话)。
      title: Text(stringsOf(context).clubTopicEndTitle),
      content: Text(
        stringsOf(context).clubTopicEndNamedBody(widget.topicName) +
        '${_errorText.isEmpty ? '' : '\n$_errorText'}',
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          key: const Key('topic-setting-end-cancel'),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).clubTopicReconsider),
        ),
        CupertinoDialogAction(
          key: const Key('topic-setting-end-confirm'),
          isDestructiveAction: true,
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? stringsOf(context).clubTopicEnding : stringsOf(context).clubTopicEndAndRefund),
        ),
      ],
    );
  }
}

/// Figma J7 商家(半屏)。联系方式由服务端按「商家已确认」裁剪。
class _MerchantsBody extends ConsumerStatefulWidget {
  const _MerchantsBody({required this.clubId, required this.topicId});

  final int clubId;
  final int topicId;

  @override
  ConsumerState<_MerchantsBody> createState() => _MerchantsBodyState();
}

class _MerchantsBodyState extends ConsumerState<_MerchantsBody> {
  ClubOpsLoadState _stage = ClubOpsLoadState.loading;
  List<RecruitOverviewNode> _rows = const <RecruitOverviewNode>[];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stage = ClubOpsLoadState.loading;
      _error = '';
    });
    try {
      final RecruitOverview overview = await ref
          .read(clubTopicOpsApiProvider)
          .recruitOverview(clubId: widget.clubId, topicId: widget.topicId);
      if (!mounted) return;
      setState(() {
        _rows = overview.undertaken;
        _stage = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubTopicMerchantsRetryLater);
      });
    }
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    CyNativeNotice.show(context, stringsOf(context).clubTopicPhoneCopied);
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    switch (_stage) {
      case ClubOpsLoadState.loading:
        return const Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: CySkeleton(type: CySkeletonType.card, count: 2),
        );
      case ClubOpsLoadState.noPermission:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicRoleDenied,
            sub: stringsOf(context).clubTopicMerchantsPermission,
            icon: CupertinoIcons.lock,
          ),
        );
      case ClubOpsLoadState.networkError:
      case ClubOpsLoadState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicMerchantsFailed,
            sub: _error.isEmpty ? stringsOf(context).clubTopicRetryLater : _error,
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: _load,
          ),
        );
      case ClubOpsLoadState.ready:
        if (_rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.pageX,
              vertical: CyTokens.space5,
            ),
            child: StatusView(
              message: stringsOf(context).clubTopicNoMerchants,
              sub: stringsOf(context).clubTopicNoMerchantsBody,
              icon: CupertinoIcons.briefcase,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            0,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClubOpsCard(
                children: _rows
                    .map(
                      (RecruitOverviewNode node) => ClubOpsRow(
                        key: Key('topic-merchant-${node.nodeId}'),
                        title: node.merchantName.isEmpty
                            ? stringsOf(context).clubTopicUnnamedMerchant
                            : node.merchantName,
                        meta: node.stationName.isEmpty
                            ? node.contactText
                            : '${node.stationName} · ${node.contactText}',
                        metaLines: 2,
                        trailing: node.confirmed
                            ? CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(44, 44),
                                onPressed: () => _copyPhone(node.phone),
                                child: Text(
                                  stringsOf(context).clubTopicCopy,
                                  style: TextStyle(
                                    fontSize: CyTokens.typeLabel,
                                    color: palette.brand,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    )
                    .toList(growable: false),
              ),
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  stringsOf(context).clubTopicContactScope,
                  style: TextStyle(
                    fontSize: CyTokens.typeCaption,
                    height: 1.45,
                    color: palette.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// Figma J2 成员 · 主题内(半屏)。四个 chip 就是服务端 filter 的四个取值。
class _CustomersBody extends ConsumerStatefulWidget {
  const _CustomersBody({
    required this.clubId,
    required this.topicId,
    this.onBroadcast,
  });

  final int clubId;
  final int topicId;

  /// D7 定向广播的第二个入口(成员弹层里那格)。为 null 时那一格不出。
  final VoidCallback? onBroadcast;

  @override
  ConsumerState<_CustomersBody> createState() => _CustomersBodyState();
}

class _CustomersBodyState extends ConsumerState<_CustomersBody> {
  List<({String value, String label})> get _chips =>
      <({String value, String label})>[
        (value: '', label: stringsOf(context).clubTopicAll),
        (value: 'pending', label: stringsOf(context).clubTopicPending),
        (value: 'contacted', label: stringsOf(context).clubTopicContacted),
        (value: 'verified', label: stringsOf(context).clubTopicVerified),
      ];

  ClubOpsLoadState _stage = ClubOpsLoadState.loading;
  String _filter = '';
  TopicCustomers? _data;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stage = ClubOpsLoadState.loading;
      _error = '';
    });
    try {
      final TopicCustomers data = await ref
          .read(clubTopicOpsApiProvider)
          .customers(
            clubId: widget.clubId,
            topicId: widget.topicId,
            filter: _filter,
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _stage = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubTopicMembersRetryLater);
      });
    }
  }

  void _pick(String value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    switch (_stage) {
      case ClubOpsLoadState.loading:
        return const Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: CySkeleton(type: CySkeletonType.card, count: 2),
        );
      case ClubOpsLoadState.noPermission:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicRoleDenied,
            sub: stringsOf(context).clubTopicMembersPermission,
            icon: CupertinoIcons.lock,
          ),
        );
      case ClubOpsLoadState.networkError:
      case ClubOpsLoadState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space5,
          ),
          child: StatusView(
            message: stringsOf(context).clubTopicMembersFailed,
            sub: _error.isEmpty ? stringsOf(context).clubTopicRetryLater : _error,
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: _load,
          ),
        );
      case ClubOpsLoadState.ready:
        return _readyBody(_data!, palette);
    }
  }

  Widget _readyBody(TopicCustomers data, CyPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 三个数是全量口径,不随 chip 变(服务端在过滤前先数完)。
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space1,
            children: data.stats
                .map(
                  (({String text, String tone}) stat) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.bgSurfaceSubtle,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    ),
                    child: Text(
                      stat.text,
                      style: TextStyle(
                        fontSize: CyTokens.typeMicro,
                        color: _toneColor(palette, stat.tone),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: _chips
                .map(
                  (({String value, String label}) chip) => GestureDetector(
                    key: Key(
                      'topic-customers-chip-${chip.value.isEmpty ? 'all' : chip.value}',
                    ),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pick(chip.value),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space3,
                        vertical: CyTokens.space1,
                      ),
                      decoration: BoxDecoration(
                        color: chip.value == _filter
                            ? palette.actionPrimaryBg
                            : palette.bgSurfaceSubtle,
                        borderRadius: BorderRadius.circular(
                          CyTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: chip.value == _filter
                              ? palette.actionPrimaryFg
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: CyTokens.space3),
          if (data.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space5),
              child: StatusView(
                message: _filter.isEmpty ? stringsOf(context).clubTopicNoMembers : stringsOf(context).clubTopicFilterEmpty,
                sub: _filter.isEmpty ? stringsOf(context).clubTopicNoMembersBody : stringsOf(context).clubTopicFilterEmptyBody,
                icon: CupertinoIcons.person_2,
              ),
            )
          else
            ClubOpsCard(
              children: data.rows
                  .map(
                    (TopicCustomerRow row) => ClubOpsRow(
                      key: Key('topic-customer-${row.key}'),
                      title: row.nameMissing ? stringsOf(context).clubTopicUnnamedMember : row.displayName,
                      meta: <String>[
                        row.timeMissing ? stringsOf(context).clubTopicMissingTime : row.timeText,
                        row.phoneText,
                      ].where((String s) => s.isNotEmpty).join(' · '),
                      metaLines: 2,
                      value: row.statusText,
                    ),
                  )
                  .toList(growable: false),
            ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              stringsOf(context).clubTopicPhoneScope,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
          // 真源 goBroadcast:这一格无条件出现(能不能发由 D7 的闸当场说),
          // 点了先关成员弹层再开广播弹层 —— 半屏叠半屏会糊在一起。
          if (widget.onBroadcast != null)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: ClubOpsCard(
                children: <Widget>[
                  ClubOpsRow(
                    key: const Key('topic-customers-broadcast'),
                    title: stringsOf(context).clubTopicBroadcast,
                    meta: stringsOf(context).clubTopicBroadcastBody,
                    metaLines: 2,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onBroadcast!.call();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _toneColor(CyPalette palette, String tone) {
    switch (tone) {
      case 'warning':
        return CyTokens.statusWarning;
      case 'success':
        return CyTokens.statusSuccess;
      default:
        return palette.textSecondary;
    }
  }
}

/// Figma J8 退出与暂停规则。
///
/// ★ 静态内容,不打接口 —— 规则的真源是代码,不是一张可以被后台改文案的表。
///   每一行都对应代码里真正在执行的判据,括号里是原话;改文案前先改判据。
class _RulesBody extends StatelessWidget {
  const _RulesBody();

  List<_RulesSection> _sections(BuildContext context) => <_RulesSection>[
    _RulesSection(
      label: stringsOf(context).clubRulesCopy1,
      rows: <_RulesRow>[
        _RulesRow(
          title: stringsOf(context).clubRulesCopy2,
          text: stringsOf(context).clubRulesCopy3,
        ),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy4,
          text: stringsOf(context).clubRulesCopy5,
        ),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy6,
          text: stringsOf(context).clubRulesCopy7,
        ),
      ],
    ),
    _RulesSection(
      label: stringsOf(context).clubRulesCopy8,
      rows: <_RulesRow>[
        _RulesRow(title: stringsOf(context).clubRulesCopy9, text: stringsOf(context).clubRulesCopy10),
        _RulesRow(title: stringsOf(context).clubRulesCopy11, text: stringsOf(context).clubRulesCopy12),
        _RulesRow(title: stringsOf(context).clubRulesCopy13, text: stringsOf(context).clubRulesCopy14),
      ],
    ),
    _RulesSection(
      label: stringsOf(context).clubRulesCopy15,
      rows: <_RulesRow>[
        _RulesRow(
          title: stringsOf(context).clubRulesCopy16,
          text: stringsOf(context).clubRulesCopy17,
        ),
        _RulesRow(title: stringsOf(context).clubRulesCopy18, text: stringsOf(context).clubRulesCopy19),
        _RulesRow(title: stringsOf(context).clubRulesCopy20, text: stringsOf(context).clubRulesCopy21),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy22,
          text: stringsOf(context).clubRulesCopy23,
        ),
      ],
    ),
    _RulesSection(
      label: stringsOf(context).clubRulesCopy24,
      rows: <_RulesRow>[
        _RulesRow(title: stringsOf(context).clubRulesCopy25, text: stringsOf(context).clubRulesCopy26),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy27,
          text: stringsOf(context).clubRulesCopy28,
        ),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy29,
          text: stringsOf(context).clubRulesCopy30,
        ),
        _RulesRow(title: stringsOf(context).clubRulesCopy31, text: stringsOf(context).clubRulesCopy32),
        _RulesRow(
          title: stringsOf(context).clubRulesCopy33,
          text: stringsOf(context).clubRulesCopy34,
        ),
        _RulesRow(title: stringsOf(context).clubRulesCopy35, text: stringsOf(context).clubRulesCopy36),
      ],
    ),
    _RulesSection(
      label: stringsOf(context).clubRulesCopy37,
      rows: <_RulesRow>[
        _RulesRow(
          title: stringsOf(context).clubRulesCopy38,
          text: stringsOf(context).clubRulesCopy39,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            stringsOf(context).clubRulesCopy40,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              height: 1.45,
              color: palette.textTertiary,
            ),
          ),
          for (final _RulesSection section in _sections(context)) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(
                top: CyTokens.space4,
                bottom: CyTokens.space2,
              ),
              child: Text(
                section.label,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  fontWeight: FontWeight.w600,
                  color: palette.textTertiary,
                ),
              ),
            ),
            for (final _RulesRow rule in section.rows) ...<Widget>[
              Text(
                rule.title,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rule.text,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
            ],
          ],
          Text(
            stringsOf(context).clubRulesCopy41,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              height: 1.45,
              color: palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// J8 规则页的一段(静态内容,不打接口)。
class _RulesSection {
  const _RulesSection({required this.label, required this.rows});

  final String label;
  final List<_RulesRow> rows;
}

class _RulesRow {
  const _RulesRow({required this.title, required this.text});

  final String title;
  final String text;
}

/// 改集合时间失败的两种读法(小程序 `confirmOpsTime` 的 fail / successStatusAbnormal):
/// · 业务拒绝(4xx 且非 408 / body `code != 200`)是**明确拒绝**,后端原话原样带出去;
/// · 传输失败、5xx、408 都只是**结果未知** —— 不下「没改成」的结论,回读服务端真相。
({bool definite, String why}) _opsWriteFailure(BuildContext context, Object error) {
  String whenEmpty(String message) =>
      message.trim().isEmpty ? stringsOf(context).clubOpsTimeRefused : message.trim();
  if (error is ClubApiException) {
    return (definite: true, why: whenEmpty(error.message));
  }
  final DioException? dio = error is DioException ? error : null;
  final int? status = dio?.response?.statusCode;
  if (status != null && status >= 400 && status < 500 && status != 408) {
    final Object? data = dio?.response?.data;
    final Object? msg = data is Map ? data['msg'] : null;
    return (definite: true, why: whenEmpty(msg is String ? msg : ''));
  }
  if (status != null) {
    return (definite: false, why: stringsOf(context).clubOpsTimeServiceUnknown);
  }
  return (definite: false, why: stringsOf(context).clubOpsTimeNetworkUnknown);
}

/// HO-26 改集合时间(半屏)。日期 + 时间各一格,底部两颗按钮并排。
///
/// 前端**不自判**能不能改:已售锁定(CR-63)与「只有承接方领队可改」都在服务端,
/// 所以入口常显、半屏里先把规则说在前面,后端拒绝原文进结果提示。
/// 关掉半屏时返回「要不要回读详情」:写成功与结果未知都要。
class _OpsTimeSheet extends ConsumerStatefulWidget {
  const _OpsTimeSheet({
    required this.activityId,
    required this.date,
    required this.time,
  });

  final int activityId;

  /// 当前值,`yyyy-MM-dd` / `HH:mm`(由调用方从 `startDate` 解出来)。
  final String date;
  final String time;

  @override
  ConsumerState<_OpsTimeSheet> createState() => _OpsTimeSheetState();
}

class _OpsTimeSheetState extends ConsumerState<_OpsTimeSheet> {
  String get _soldLockHint => stringsOf(context).clubOpsTimeSoldPolicy;
  String get _effectHint => stringsOf(context).clubOpsTimeEffectPolicy;
  String get _doneHint => stringsOf(context).clubOpsTimeDonePolicy;

  late String _date = widget.date;
  late String _time = widget.time;
  bool _submitting = false;

  static String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: DateTime.tryParse(_date) ?? today,
      minimumDate: DateTime(today.year, today.month, today.day),
      maximumDate: today.add(const Duration(days: 365)),
      title: stringsOf(context).clubOpsTimeDate,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _date = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}',
    );
  }

  Future<void> _pickTime() async {
    final DateTime today = DateTime.now();
    final List<String> parts = _time.split(':');
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.time,
      initialDateTime: DateTime(
        today.year,
        today.month,
        today.day,
        int.tryParse(parts.first) ?? 0,
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      ),
      minimumDate: DateTime(today.year, today.month, today.day),
      maximumDate: DateTime(today.year, today.month, today.day, 23, 59),
      title: stringsOf(context).clubOpsTimeTime,
    );
    if (picked == null || !mounted) return;
    setState(() => _time = '${_two(picked.hour)}:${_two(picked.minute)}');
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date) ||
        !RegExp(r'^\d{2}:\d{2}$').hasMatch(_time)) {
      CyNativeNotice.show(context, stringsOf(context).clubOpsTimeRequired);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(clubTopicOpsApiProvider)
          .editOps(
            activityId: widget.activityId,
            startDate: '$_date $_time:00',
          );
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).clubOpsTimeUpdated(_doneHint));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final ({bool definite, String why}) failure = _opsWriteFailure(context, error);
      CyNativeNotice.show(context, stringsOf(context).clubOpsTimeNotChanged(failure.why), isError: true);
      Navigator.of(context).pop(!failure.definite);
    }
  }

  Widget _pickerRow({
    required Key key,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return ClubOpsRow(
      key: key,
      title: label,
      value: value,
      valueColor: palette.textPrimary,
      trailing: Icon(
        CupertinoIcons.chevron_down,
        size: 14,
        color: palette.textTertiary,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextStyle hintStyle = TextStyle(
      fontSize: CyTokens.typeCaption,
      height: 1.45,
      color: palette.textTertiary,
    );
    return _SheetFrame(
      title: stringsOf(context).clubOpsTimeEdit,
      sheetKey: const Key('topic-ops-time-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          0,
          CyTokens.pageX,
          CyTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_soldLockHint, style: hintStyle),
            ClubOpsCard(
              children: <Widget>[
                _pickerRow(
                  key: const Key('topic-ops-time-date'),
                  label: stringsOf(context).clubOpsTimeDate,
                  value: _date.isEmpty ? stringsOf(context).clubOpsTimeChooseDate : _date,
                  onTap: _submitting ? null : () => _pickDate(),
                ),
                _pickerRow(
                  key: const Key('topic-ops-time-time'),
                  label: stringsOf(context).clubOpsTimeTime,
                  value: _time.isEmpty ? stringsOf(context).clubOpsTimeChooseTime : _time,
                  onTap: _submitting ? null : () => _pickTime(),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space3),
            Text(_effectHint, style: hintStyle),
            const SizedBox(height: CyTokens.space4),
            Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    key: const Key('topic-ops-time-cancel'),
                    label: stringsOf(context).clubOpsTimeCancel,
                    role: CyNativeButtonRole.secondary,
                    width: double.infinity,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: CyNativeButton(
                    key: const Key('topic-ops-time-save'),
                    label: _submitting ? stringsOf(context).clubOpsTimeSubmitting : stringsOf(context).clubOpsTimeSave,
                    width: double.infinity,
                    onPressed: _submitting ? null : _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _topicStatusLabel(BuildContext context, ClubTopicStatus status) => switch (status) {
  ClubTopicStatus.reviewing => stringsOf(context).clubTopicStatusReviewing,
  ClubTopicStatus.rejected => stringsOf(context).clubTopicStatusRejected,
  ClubTopicStatus.confirmed => stringsOf(context).clubTopicStatusConfirmed,
  ClubTopicStatus.preparing => stringsOf(context).clubTopicStatusPreparing,
  ClubTopicStatus.running => stringsOf(context).clubTopicStatusRunning,
  ClubTopicStatus.selfRun => stringsOf(context).clubTopicStatusRunning,
  ClubTopicStatus.ended => stringsOf(context).clubTopicStatusEnded,
};

String _topicPrimaryLabel(BuildContext context, ClubTopicStatus status) => switch (status) {
  ClubTopicStatus.reviewing => stringsOf(context).clubTopicAwaitReview,
  ClubTopicStatus.rejected => stringsOf(context).clubTopicResubmit,
  ClubTopicStatus.confirmed => stringsOf(context).clubTopicPrepareAction,
  ClubTopicStatus.preparing => stringsOf(context).clubTopicStartAction,
  ClubTopicStatus.running => stringsOf(context).clubTopicEndAction,
  ClubTopicStatus.selfRun => stringsOf(context).clubTopicEndAction,
  ClubTopicStatus.ended => stringsOf(context).clubTopicSettlementReport,
};
