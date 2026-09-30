import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/device_location.dart';
import '../../core/map/map_scene.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/team_map_api.dart';
import '../../data/models/team_map.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 地图组队 P 方案的接口入口(Riverpod)。
///
/// ⚠️ 放在 feature 而不是 `lib/core/providers.dart`:本线的写集只到
/// `lib/feature/team/**`(共用层刚收口,不许碰);仓内已有先例
/// (`feature/participation/participation_api.dart`)。
final Provider<TeamMapApi> teamMapApiProvider = Provider<TeamMapApi>(
  (ref) => TeamMapApi(ref.watch(dioClientProvider)),
);

/// 失败出口:标题 / 原因 / 最多两个动作,由页面统一弹(半屏里失败也回来弹,
/// 因为半屏自己会先收起)。
typedef _FailHandler =
    Future<void> Function(TeamErrorOutcome outcome, int? activityId);

/// 队伍半屏的**唯一入口**:队长走审批半屏,其他人走队伍卡半屏(申请 / 撤回 /
/// 买票 / 进队)。
///
/// ★ 列表页(`/team/nearby`)与漫游地图 marker 共用这一份 —— marker 那条路
///   由 `lib/feature/roam/roam_team_markers.dart` 调用,状态机不复制第二套。
/// ★ 只提供出口,**不做业务判断**:五态 / errorCode 分支仍在
///   `lib/data/models/team_map.dart`(`decorateTeam`),这里只摆半屏。
Future<void> showTeamMarkerSheet({
  required BuildContext context,
  required TeamMapApi api,
  required Map<String, dynamic> row,
  required void Function(Map<String, Object?> patch) onPatch,
  required VoidCallback onDrop,
  required void Function(int teamId) onOpenTeam,
  required void Function(int activityId) onOpenActivity,
  Future<bool> Function()? onRefresh,
}) async {
  final int? teamId = decorateTeam(row).teamId;
  if (teamId == null) return;
  Future<void> fail(TeamErrorOutcome outcome, int? activityId) =>
      showTeamFailOutcome(
        context,
        outcome,
        activityId: activityId,
        onOpenActivity: onOpenActivity,
      );
  if (decorateTeam(row).card.mode == 'leader') {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          _LeaderSheet(
            controller: controller,
            row: row,
            api: api,
            onFail: fail,
            onRefresh: onRefresh ?? () async => true,
          ),
    );
    return;
  }
  await showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        _TeamCardSheet(
          controller: controller,
          row: row,
          api: api,
          onPatch: onPatch,
          onDrop: onDrop,
          onFail: fail,
          onOpenTeam: onOpenTeam,
          onOpenActivity: onOpenActivity,
        ),
  );
}

/// 失败合同(唯一一份):标题来自 errorCode 分支(没码就是兜底标题),msg 只当
/// 原因;动作最多两个,主动作才带得走(买票)。
Future<void> showTeamFailOutcome(
  BuildContext context,
  TeamErrorOutcome outcome, {
  int? activityId,
  void Function(int activityId)? onOpenActivity,
}) async {
  if (!context.mounted) return;
  final bool confirmed = await cyConfirm(
    context,
    title: outcome.title,
    content: outcome.why,
    confirmText: outcome.primary.isNotEmpty ? outcome.primary : '知道了',
    cancelText: outcome.secondary.isNotEmpty ? outcome.secondary : '取消',
    showCancel: outcome.secondary.isNotEmpty,
  );
  if (!context.mounted || !confirmed) return;
  if (outcome.primaryAction == 'buy' && activityId != null) {
    onOpenActivity?.call(activityId);
  }
}

/// 漫游地图「附近的队伍」(Figma txQoyVyK 590:1014 · P1–P6)。
///
/// ★ 小程序把 P1–P6 做在 `subpackageRoam/nearby` 的地图上:marker = 队伍点位,
///   点 marker 开半屏;App 这边的地图页归漫游线(`lib/feature/roam/**`,不在本线
///   写集),所以本线按同一份真源把 **7 条接口 + 卡片状态机 + 三条产品判据**
///   接成一张「附近的队伍」页:顶部计数条 + 范围/我的队伍两枚控件 + 队伍行,
///   点行开半屏做申请 / 撤回 / 买票 / 进队 / 审批 / 我的队伍。
///   地图图层(点位/marker)在 `lib/feature/roam/roam_team_markers.dart`:同一份
///   `decorateTeam` 输出 + 同一份 [showTeamMarkerSheet] 半屏,两处不各算一套状态。
///
/// ★ 卡片状态、文案、errorCode 分支的唯一真源是 `lib/data/models/team_map.dart`
///   (小程序 `utils/map-team.js` 的直译),本页只接线,不做业务判断。
class TeamNearbyPage extends ConsumerStatefulWidget {
  const TeamNearbyPage({
    super.key,
    this.api,
    this.locate,
    this.openTeam,
    this.openActivity,
  });

  /// 测试 / 快照注入;为空时走 [teamMapApiProvider]。
  final TeamMapApi? api;

  /// 定位注入(GCJ-02)。为空时走系统定位。
  final Future<MapCoordinate> Function()? locate;

  /// 跳转注入;为空时走 `/team/:teamId` 与 `/activity/:id`。
  final void Function(int teamId)? openTeam;
  final void Function(int activityId)? openActivity;

  @override
  ConsumerState<TeamNearbyPage> createState() => _TeamNearbyPageState();
}

class _TeamNearbyPageState extends ConsumerState<TeamNearbyPage> {
  /// 首屏范围 = 1 km。快照 `subpackageRoam/nearby/index.js:17`:稿 591:1020 的
  /// 角控件写死「范围 1 km」,**不取** `/api/team/nearby` 的 3000 缺省。
  static const int _kInitialRadiusM = 1000;

  int _radiusM = _kInitialRadiusM;
  List<Map<String, dynamic>> _teams = const <Map<String, dynamic>>[];
  List<MyTeamRow> _myRows = const <MyTeamRow>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 游客两条接口都读不了,别发注定 401 的请求(打了只会被 dio 的 401 收口
    // 静默弹回登录页)。出口在 [_loginGate]。
    if (!ref.read(authControllerProvider).isLoggedIn) {
      _loading = false;
      return;
    }
    unawaited(_load());
    // 角控件计数靠它:onLoad 静默拉一次(快照 index.js:450)。
    unawaited(_loadMyTeams(showFail: false));
  }

  TeamMapApi get _api => widget.api ?? ref.read(teamMapApiProvider);

  Future<MapCoordinate> _location() {
    final Future<MapCoordinate> Function()? injected = widget.locate;
    if (injected != null) return injected();
    return DeviceLocation().current();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MapCoordinate center = await _location();
      final List<Map<String, dynamic>> rows = await _api.nearby(
        lat: center.latitude,
        lng: center.longitude,
        radiusM: _radiusM,
      );
      if (!mounted) return;
      setState(() {
        _teams = rows;
        _loading = false;
      });
    } on LocationUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      // 异常原文只进日志;上屏的是真源那句「地图还在,队伍这次没读到」。
      debugPrint('[team-nearby] 拉附近队伍失败: $e');
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e, fallback: '地图还在，队伍这次没读到');
      });
    }
  }

  /// P6 两条并行拉:两条都读不到才报失败,只读到一条就先显示那一条
  /// (快照 index.js:450 `loadMyTeams`)。
  Future<void> _loadMyTeams({required bool showFail}) async {
    List<Map<String, dynamic>>? joined;
    List<Map<String, dynamic>>? applications;
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          joined = await _api.myTeams();
        } catch (_) {}
      }(),
      () async {
        try {
          applications = await _api.myApplications();
        } catch (_) {}
      }(),
    ]);
    if (!mounted) return;
    final List<MyTeamRow> rows = myTeamRows(
      joined ?? const <Map<String, dynamic>>[],
      applications ?? const <Map<String, dynamic>>[],
    );
    setState(() => _myRows = rows);
    if (showFail && joined == null && applications == null) {
      await _showFail(resolveTeamError('my', null), null);
    }
  }

  /// 失败合同:标题来自 errorCode 分支(没码就是兜底标题),msg 只当原因;
  /// 动作最多两个,主动作才带得走(买票)。
  Future<void> _showFail(TeamErrorOutcome outcome, int? activityId) async {
    await showTeamFailOutcome(
      context,
      outcome,
      activityId: activityId,
      onOpenActivity: _openActivity,
    );
  }

  void _openTeam(int teamId) {
    final void Function(int teamId)? injected = widget.openTeam;
    if (injected != null) {
      injected(teamId);
      return;
    }
    unawaited(context.push('/team/$teamId'));
  }

  void _openActivity(int activityId) {
    final void Function(int activityId)? injected = widget.openActivity;
    if (injected != null) {
      injected(activityId);
      return;
    }
    unawaited(context.push('/activity/$activityId'));
  }

  Map<String, dynamic>? _teamRow(int? teamId) {
    if (teamId == null) return null;
    for (final Map<String, dynamic> row in _teams) {
      if (decorateTeam(row).teamId == teamId) return row;
    }
    return null;
  }

  void _patchTeam(int teamId, Map<String, Object?> patch) {
    setState(() {
      _teams = <Map<String, dynamic>>[
        for (final Map<String, dynamic> row in _teams)
          if (decorateTeam(row).teamId == teamId)
            <String, dynamic>{...row, ...patch}
          else
            row,
      ];
    });
  }

  /// 满员 / 开场 / 审核中 / 邀请制:从列表里撤下(快照 `_dropCurrent`)。
  void _dropTeam(int teamId) {
    setState(() {
      _teams = _teams
          .where(
            (Map<String, dynamic> row) => decorateTeam(row).teamId != teamId,
          )
          .toList();
    });
  }

  void _cycleRadius() {
    setState(() => _radiusM = teamNextRadius(_radiusM));
    unawaited(_load());
  }

  Future<void> _openTeamSheet(int teamId) async {
    final Map<String, dynamic>? row = _teamRow(teamId);
    if (row == null) return;
    await showTeamMarkerSheet(
      context: context,
      api: _api,
      row: row,
      onPatch: (Map<String, Object?> patch) => _patchTeam(teamId, patch),
      onDrop: () => _dropTeam(teamId),
      onOpenTeam: _openTeam,
      onOpenActivity: _openActivity,
      // 同意会让人数变、满员会让队伍从地图消失 —— 以服务端为准重拉;
      // 队伍不在了就把半屏收掉(快照 `_syncTeams` 的 closeSheet)。
      onRefresh: () async {
        await _load();
        return _teamRow(teamId) != null;
      },
    );
  }

  Future<void> _openMyTeamsSheet() async {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          _MyTeamsSheet(
            controller: controller,
            api: _api,
            onFail: _showFail,
            onOpenTeam: _openTeam,
            onCount: (List<MyTeamRow> rows) {
              if (mounted) setState(() => _myRows = rows);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 游客:队伍行带 viewerStatus、角控件带「我的队伍」计数,两样都要登录
    // (生产实测 2026-09-18:GET /api/team/nearby 与 POST /api/team/my 对无 token
    // 一律返 401)。原先游客落地就在这儿空转 —— 列表永远读不出来,又不给登录
    // 出口(B1 模拟器报告 P1-1)。路由那边刻意不拦这条深链,解释与出口都放在
    // 这一屏(同 roam 集邮册 / club 各页的既有口径)。
    final bool signedIn = ref.watch(authControllerProvider).isLoggedIn;
    return CupertinoPageScaffold(
      // ★ N-1(b1-sim-team-3):冷启动深链直达时栈底就是本页 —— 框架只在
      //   `ModalRoute.canPop` 为真时渲染返回箭头,登录态 + 列表非空那一支
      //   又没有 StatusView 的「回首页」兜底,整屏零出口(写法同 /roam/nearby
      //   的 N2 修复:「回首页恒在,返回按栈深出」)。
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        leading: (ModalRoute.of(context)?.canPop ?? false)
            ? const CupertinoNavigationBarBackButton()
            : GoRouter.maybeOf(context) == null
            ? null
            : CupertinoButton(
                key: const Key('team-nearby-home-exit'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: () => GoRouter.of(context).go(kHomeRoute),
                child: const Text('回首页'),
              ),
      ),
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('附近的队伍'),
              if (!signedIn)
                Expanded(child: _loginGate(context))
              else ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    0,
                    CyTokens.pageX,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          teamHeaderText(_teams.length),
                          style: CyType.caption1.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                      CyChip(
                        label: teamRangeText(_radiusM),
                        selected: false,
                        onTap: _cycleRadius,
                      ),
                      const SizedBox(width: CyTokens.space2),
                      CyChip(
                        label: teamMyTeamsText(teamMyTeamsCount(_myRows)),
                        selected: false,
                        onTap: () => unawaited(_openMyTeamsSheet()),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 游客登录门:不是转不完的圈,也不是一句「没能读到」。
  ///
  /// 队伍行带 viewerStatus、「我的队伍」计数,两条接口都要登录(生产实测
  /// 2026-09-18:无 token 时 `GET /api/team/nearby` 与 `POST /api/team/my`
  /// 一律 401)。不做静默弹窗 —— 深链直接盖一层 sheet 同样像「链接坏了」;
  /// 也不在路由表拦这条深链(会被静默弹回首页)。文案与出口同 roam 集邮册。
  Widget _loginGate(BuildContext context) {
    return StatusView(
      key: const Key('team-nearby-login-gate'),
      message: '登录后查看附近的队伍',
      sub: '队伍点位和你的申请都跟着账号走,登录完就回来。',
      icon: CupertinoIcons.lock,
      large: true,
      retryLabel: '去登录',
      onRetry: () async {
        if (!await requireLogin(context, ref)) return;
        if (!mounted) return;
        // 登完留在原页,就地重拉(不是让用户退出重进)。
        unawaited(_load());
        unawaited(_loadMyTeams(showFail: false));
      },
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _teams.isEmpty) {
      // LoadingView = 带 liveRegion「正在加载」的转圈(共用层)。
      return const LoadingView();
    }
    if (_error != null && _teams.isEmpty) {
      return StatusView(
        message: '附近的队伍没能读到',
        sub: _error!,
        large: true,
        onRetry: _load,
      );
    }
    if (_teams.isEmpty) {
      return const StatusView(
        message: '这一片还没有队伍',
        sub: '把范围拉远一点,或过一会儿再来',
        large: true,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        for (final Map<String, dynamic> row in _teams) _teamCell(row),
      ],
    );
  }

  Widget _teamCell(Map<String, dynamic> row) {
    final TeamNearbyCard card = decorateTeam(row);
    final int? teamId = card.teamId;
    // 行标题是**队名**(短、不截断),副标题给场次,行尾是**短状态胶囊**
    // (胶囊文案全部取自快照:已加入 / 申请中 / 队长未同意 = `myTeamRows` 的
    //  badge,我的队伍 = `decorateTeam` 的 plate 前缀,招募中 =
    //  `pages/team/detail/index.js` STATUS_TEXT 的第一档)。
    // 完整状态与说明仍以半屏里的 `TeamCardState` 为准。
    return CyCell(
      leading: _TeamAvatar(url: card.faces.isEmpty ? '' : card.faces.first),
      title: card.name,
      subtitle: card.heading,
      trailing: CyTag(label: _rowBadge(card)),
      onTap: teamId == null ? null : () => unawaited(_openTeamSheet(teamId)),
    );
  }
}

/// 列表行的短状态胶囊(文案见 [_teamCell] 注释)。
String _rowBadge(TeamNearbyCard card) {
  return switch (card.card.mode) {
    'leader' => '我的队伍',
    'joined' => '已加入',
    'pending' => '申请中',
    'rejected' => '队长未同意',
    _ => '招募中',
  };
}

/// 队伍头像(第一张成员头像;没有就人像图标兜底,不留空白)。
class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({required this.url, this.size = 40});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClipOval(
      child: CyNetImage(
        url,
        width: size,
        height: size,
        fallback: Container(
          width: size,
          height: size,
          color: palette.bgSurfaceStrong,
          alignment: Alignment.center,
          child: Icon(
            CupertinoIcons.person_fill,
            size: size * 0.55,
            color: palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

Color _noticeColor(CyPalette palette, String tone) {
  return switch (tone) {
    'ok' => palette.statusSuccess,
    'wait' => palette.statusWarning,
    'bad' => palette.statusDanger,
    _ => palette.textSecondary,
  };
}

/// 半屏自己的底。
///
/// `showCupertinoSheet` 的路由不画背景(内容自带背景是 Flutter 的约定),
/// 少这一层时下层页面的文字会直接透上来叠字(B1 报告 P1-2)。
Widget _sheetSurface(BuildContext context, Widget child) =>
    ColoredBox(color: CyPalette.of(context).bgPage, child: child);

/// 队伍卡半屏(P2–P4):notice / 主次按钮 / foot 全来自 [TeamCardState]。
class _TeamCardSheet extends StatefulWidget {
  const _TeamCardSheet({
    required this.controller,
    required this.row,
    required this.api,
    required this.onPatch,
    required this.onDrop,
    required this.onFail,
    required this.onOpenTeam,
    required this.onOpenActivity,
  });

  final ScrollController controller;
  final Map<String, dynamic> row;
  final TeamMapApi api;
  final void Function(Map<String, Object?> patch) onPatch;
  final VoidCallback onDrop;
  final _FailHandler onFail;
  final void Function(int teamId) onOpenTeam;
  final void Function(int activityId) onOpenActivity;

  @override
  State<_TeamCardSheet> createState() => _TeamCardSheetState();
}

class _TeamCardSheetState extends State<_TeamCardSheet> {
  late Map<String, dynamic> _row = widget.row;
  bool _busy = false;

  void _patch(Map<String, Object?> patch) {
    setState(() => _row = <String, dynamic>{..._row, ...patch});
    widget.onPatch(patch);
  }

  Future<void> _apply() async {
    final TeamNearbyCard card = decorateTeam(_row);
    final int? teamId = card.teamId;
    if (_busy || teamId == null) return;
    setState(() => _busy = true);
    try {
      // 回执带 applyExpireTime(真实失效 = min(申请+24h, 场次开始)),回填卡片,
      // foot 立刻说真实剩余时间(快照 `index.js:391-392`)。
      final Object? applyExpireTime = await widget.api.apply(teamId);
      if (!mounted) return;
      setState(() => _busy = false);
      // 成功 = 申请已发出:卡片打成 PENDING,只剩「撤回申请」。
      _patch(<String, Object?>{
        'viewerStatus': 'PENDING',
        'applyExpireTime': applyExpireTime,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final TeamErrorOutcome outcome = resolveTeamError(
        'apply',
        teamErrorBody(e),
      );
      if (outcome.dropTeam) {
        widget.onDrop();
        if (mounted) Navigator.of(context).maybePop();
        await widget.onFail(outcome, card.activityId);
        return;
      }
      final Map<String, Object?>? patch = outcome.patch;
      if (patch != null) _patch(patch);
      await widget.onFail(outcome, card.activityId);
    }
  }

  Future<void> _withdraw() async {
    final int? teamId = decorateTeam(_row).teamId;
    if (_busy || teamId == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.withdraw(teamId);
      if (!mounted) return;
      setState(() => _busy = false);
      // 撤回成功 → 回到「有票就能申请」的态(有票出「申请加入」,没票出「去买票」)。
      _patch(<String, Object?>{'viewerStatus': 'NONE'});
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final TeamErrorOutcome outcome = resolveTeamError(
        'withdraw',
        teamErrorBody(e),
      );
      await widget.onFail(outcome, decorateTeam(_row).activityId);
    }
  }

  void _onPrimary(TeamCardButton button) {
    final TeamNearbyCard card = decorateTeam(_row);
    switch (button.action) {
      case 'buy':
        final int? activityId = card.activityId;
        if (activityId != null) widget.onOpenActivity(activityId);
      case 'apply':
        unawaited(_apply());
      case 'enter':
        final int? teamId = card.teamId;
        if (teamId != null) widget.onOpenTeam(teamId);
    }
  }

  void _onSecondary(TeamCardButton button) {
    if (button.action == 'withdraw') unawaited(_withdraw());
  }

  @override
  Widget build(BuildContext context) {
    final TeamNearbyCard card = decorateTeam(_row);
    final CyPalette palette = CyPalette.of(context);
    final TeamCardNotice? notice = card.card.notice;
    final TeamCardButton? primary = card.card.primary;
    final TeamCardButton? secondary = card.card.secondary;
    return _sheetSurface(
      context,
      ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          0,
          CyTokens.pageX,
          CyTokens.space6,
        ),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  card.name,
                  style: CyType.title2.copyWith(color: palette.textPrimary),
                ),
              ),
              CyTag(label: card.plate),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            card.heading,
            style: CyType.body.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            card.sub,
            style: CyType.footnote.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            card.membersLine,
            style: CyType.footnote.copyWith(color: palette.textSecondary),
          ),
          if (card.faces.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                for (final String face in card.faces)
                  Padding(
                    padding: const EdgeInsets.only(right: CyTokens.space1),
                    child: _TeamAvatar(url: face, size: 32),
                  ),
              ],
            ),
          ],
          if (notice != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              notice.text,
              style: CyType.footnote.copyWith(
                color: _noticeColor(palette, notice.tone),
              ),
            ),
          ],
          if (primary != null) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            CyNativeButton(
              label: primary.text,
              width: double.infinity,
              loading: _busy,
              onPressed: _busy ? null : () => _onPrimary(primary),
            ),
          ],
          if (secondary != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            CyNativeButton(
              label: secondary.text,
              width: double.infinity,
              role: CyNativeButtonRole.secondary,
              onPressed: _busy ? null : () => _onSecondary(secondary),
            ),
          ],
          if (card.card.foot.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              card.card.foot,
              style: CyType.caption1.copyWith(color: palette.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// P5 审批半屏:申请列表 + 一行并排的「拒绝(次,左) / 同意(主,右)」。
class _LeaderSheet extends StatefulWidget {
  const _LeaderSheet({
    required this.controller,
    required this.row,
    required this.api,
    required this.onFail,
    required this.onRefresh,
  });

  final ScrollController controller;
  final Map<String, dynamic> row;
  final TeamMapApi api;
  final _FailHandler onFail;

  /// 重拉地图列表;返回该队是否还在(不在 = 满员/开场/审核中,半屏收掉)。
  final Future<bool> Function() onRefresh;

  @override
  State<_LeaderSheet> createState() => _LeaderSheetState();
}

class _LeaderSheetState extends State<_LeaderSheet> {
  List<TeamApplicantRow> _applicants = const <TeamApplicantRow>[];
  bool _loading = true;
  bool _busy = false;

  int? get _teamId => decorateTeam(widget.row).teamId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadApplicants());
  }

  Future<void> _loadApplicants() async {
    final int? teamId = _teamId;
    if (teamId == null) return;
    try {
      final List<Map<String, dynamic>> rows = await widget.api.applications(
        teamId,
      );
      if (!mounted) return;
      setState(() {
        _applicants = teamApplicantRows(rows, DateTime.now());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await widget.onFail(
        resolveTeamError('applications', teamErrorBody(e)),
        null,
      );
    }
  }

  Future<void> _handle(
    TeamApplicantRow applicant, {
    required bool approved,
  }) async {
    final int? teamId = _teamId;
    if (_busy || teamId == null) return;
    setState(() => _busy = true);
    void drop() {
      setState(() {
        _applicants = _applicants
            .where((TeamApplicantRow a) => a.memberId != applicant.memberId)
            .toList();
      });
    }

    try {
      await widget.api.handle(
        teamId: teamId,
        memberId: applicant.memberId,
        approved: approved,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      drop();
      // 同意会让人数变、满员会让队伍从地图消失 —— 以服务端为准重拉。
      if (approved && !await widget.onRefresh() && mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final TeamErrorOutcome outcome = resolveTeamError(
        'handle',
        teamErrorBody(e),
      );
      if (outcome.dropApplicant) drop();
      if (outcome.refresh && !await widget.onRefresh() && mounted) {
        Navigator.of(context).maybePop();
      }
      await widget.onFail(outcome, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TeamNearbyCard card = decorateTeam(widget.row);
    final CyPalette palette = CyPalette.of(context);
    return _sheetSurface(
      context,
      ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          0,
          CyTokens.pageX,
          CyTokens.space6,
        ),
        children: <Widget>[
          Text(
            card.name,
            style: CyType.title2.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            teamLeaderSub(widget.row),
            style: CyType.footnote.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space4),
          if (_loading && _applicants.isEmpty)
            const LoadingView()
          else if (_applicants.isEmpty)
            StatusView(
              message: '还没有人申请',
              sub: '有人申请后会出现在这里,同意满员后队伍就从地图上消失',
              icon: CupertinoIcons.person_2,
            )
          else ...<Widget>[
            CySectionTitle('待处理的申请 · ${_applicants.length}'),
            const SizedBox(height: CyTokens.space1),
            for (final TeamApplicantRow applicant in _applicants)
              Container(
                padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: palette.borderSubtle),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    _TeamAvatar(url: applicant.avatar),
                    const SizedBox(width: CyTokens.space2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            applicant.name,
                            style: CyType.body.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space1),
                          Text(
                            applicant.sub,
                            style: CyType.caption1.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          // 申请留言:与 sub 同档(快照 `.mt-app__msg` = `.mt-app__s` 档),最多两行。
                          if (applicant.messageText.isNotEmpty) ...<Widget>[
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              applicant.messageText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CyType.caption1.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 拒绝(次)在左、同意(主)在右 —— 快照 WXML 契约按位置钉住。
                    CyNativeButton(
                      label: '拒绝',
                      role: CyNativeButtonRole.secondary,
                      width: 76,
                      onPressed: _busy
                          ? null
                          : () =>
                                unawaited(_handle(applicant, approved: false)),
                    ),
                    const SizedBox(width: CyTokens.space2),
                    CyNativeButton(
                      label: '同意',
                      width: 76,
                      onPressed: _busy
                          ? null
                          : () => unawaited(_handle(applicant, approved: true)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: CyTokens.space3),
          Text(
            teamLeaderFoot(widget.row),
            style: CyType.caption1.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// P6 我的队伍:已加入(进入队伍)/ 申请中(撤回)/ 被拒(看附近队伍)。
class _MyTeamsSheet extends StatefulWidget {
  const _MyTeamsSheet({
    required this.controller,
    required this.api,
    required this.onFail,
    required this.onOpenTeam,
    required this.onCount,
  });

  final ScrollController controller;
  final TeamMapApi api;
  final _FailHandler onFail;
  final void Function(int teamId) onOpenTeam;

  /// 把计数回写给角控件(不算被拒)。
  final void Function(List<MyTeamRow> rows) onCount;

  @override
  State<_MyTeamsSheet> createState() => _MyTeamsSheetState();
}

class _MyTeamsSheetState extends State<_MyTeamsSheet> {
  List<MyTeamRow> _rows = const <MyTeamRow>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load(showFail: true));
  }

  Future<void> _load({required bool showFail}) async {
    setState(() => _loading = true);
    List<Map<String, dynamic>>? joined;
    List<Map<String, dynamic>>? applications;
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          joined = await widget.api.myTeams();
        } catch (_) {}
      }(),
      () async {
        try {
          applications = await widget.api.myApplications();
        } catch (_) {}
      }(),
    ]);
    if (!mounted) return;
    final List<MyTeamRow> rows = myTeamRows(
      joined ?? const <Map<String, dynamic>>[],
      applications ?? const <Map<String, dynamic>>[],
    );
    setState(() {
      _rows = rows;
      _loading = false;
    });
    widget.onCount(rows);
    if (showFail && joined == null && applications == null) {
      await widget.onFail(resolveTeamError('my', null), null);
    }
  }

  Future<void> _act(MyTeamRow row) async {
    switch (row.action) {
      case 'enter':
        widget.onOpenTeam(row.teamId);
      case 'nearby':
        if (mounted) Navigator.of(context).maybePop();
      case 'withdraw':
        await _withdraw(row);
    }
  }

  Future<void> _withdraw(MyTeamRow row) async {
    final bool confirmed = await cyConfirm(
      context,
      title: '撤回申请',
      content: '撤回后可以重新申请;队长那边会少一条待处理。',
      confirmText: '撤回',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.api.withdraw(row.teamId);
      if (!mounted) return;
      // 撤回成功只重拉列表,不重开半屏(快照契约钉过)。
      await _load(showFail: false);
    } catch (e) {
      if (!mounted) return;
      final TeamErrorOutcome outcome = resolveTeamError(
        'withdraw',
        teamErrorBody(e),
      );
      if (outcome.refresh) await _load(showFail: false);
      await widget.onFail(outcome, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return _sheetSurface(
      context,
      ListView(
        controller: widget.controller,
        padding: const EdgeInsets.only(bottom: CyTokens.space6),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              0,
              CyTokens.pageX,
              CyTokens.space3,
            ),
            child: Text(
              '我的队伍',
              style: CyType.title2.copyWith(color: palette.textPrimary),
            ),
          ),
          if (_loading && _rows.isEmpty)
            const LoadingView()
          else if (_rows.isEmpty)
            StatusView(
              message: '还没有加入或申请中的队伍',
              sub: '附近的队伍里申请一支,或被队长拉进队伍',
              icon: CupertinoIcons.person_2,
            )
          else
            for (final MyTeamRow row in _rows)
              CyCell(
                title: row.name,
                subtitle: row.sub,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CyTag(label: row.badge),
                    const SizedBox(width: CyTokens.space1),
                    Text(
                      row.actionText,
                      style: CyType.caption1.copyWith(
                        color: row.actionKind == 'primary'
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                onTap: () => unawaited(_act(row)),
              ),
        ],
      ),
    );
  }
}
