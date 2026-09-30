import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/page_parity_api.dart';
import 'team_nearby_page.dart';

String _text(dynamic value, [String fallback = '']) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

int? _id(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');

/// 队伍状态文案。★ 对齐小程序 `pages/team/detail/index.js` 的
/// `STATUS_TEXT = ['招募中','已满员','进行中','已结束','已解散']` ——
/// 是**五档**,少一档就会把「进行中」和「已解散」都写成「已结束」,
/// 而这两种状态对用户要做的事完全不同(一个还能退队,一个已经没了)。
const List<String> _kTeamStatusText = <String>[
  '招募中',
  '已满员',
  '进行中',
  '已结束',
  '已解散',
];

String _teamStatusText(int status) =>
    status >= 0 && status < _kTeamStatusText.length
    ? _kTeamStatusText[status]
    : '状态未知';

/// 「场次开始」。★ 小程序读的是 `team.expireTime` 并过一遍它自己的
/// `formatTime`(`M月D日 HH:mm`)。App 之前读 `startTime` —— 后端不下发这个
/// 字段,于是这格永远是「待定」,而小程序有值。
String _teamExpireText(dynamic value) {
  final String raw = _text(value);
  if (raw.isEmpty) return '待定';
  final DateTime? at = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  // 解析不出来就照原样显示(小程序 formatTime 也是这个回退),别把
  // 「有值但格式没见过」悄悄说成「待定」。
  if (at == null) return raw;
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${at.month}月${at.day}日 ${two(at.hour)}:${two(at.minute)}';
}

List<Map<String, dynamic>> _rows(dynamic value) =>
    (value is List ? value : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

/// 读取失败的文案合同。★ 真源 `pages/team/detail/index.js` / `join/index.js`
/// 把失败分成两个互斥终态:传输层 `fail()` 一律「网络没连上 / 检查网络连接后
/// 重试」,服务端回了非 200 才是那一页的「暂时不可用」+ 服务端 msg
/// (`app.getRequestErrorMessage(res, 兜底)`)。
///
/// ⚠️ 异常原文一句都不许上屏:`DioException.toString()` 是英文 + 请求 URL,
///   甩给用户等于让他们去「修服务端」(§9.3 D3「错态说人话」)。
///
/// `icon` 走真源 `cy-empty` 的同一档 glyph:`network → warning`(线性 ⚠)、
/// `data → info`(线性 ⓘ)。三态不能只靠文字堆在一块黑屏上。
({String title, String sub, IconData icon}) _loadFault(
  Object error, {
  required String dataTitle,
  required String dataFallbackSub,
}) {
  if (error is PageParityApiException) {
    // 「请求失败」是网络层在**没有**服务端 msg 时填的占位,不是给用户看的话。
    return (
      title: dataTitle,
      sub: error.message == '请求失败' ? dataFallbackSub : error.message,
      icon: CupertinoIcons.info_circle,
    );
  }
  return (
    title: '网络没连上',
    sub: '检查网络连接后重试',
    icon: CupertinoIcons.exclamationmark_triangle,
  );
}

/// 写动作(移队/退队/解散/改加入方式)的失败文案。★ 口径与读取不同:真源
/// `action()` 的 `fail()` 一律「网络异常，请重试」,服务端 msg 优先、没有才用
/// 那一页的兜底词。同样不吃异常原文。
String _actionFault(Object error, {required String dataFallback}) {
  if (error is PageParityApiException) {
    return error.message == '请求失败' ? dataFallback : error.message;
  }
  return '网络异常，请重试';
}

/// 重拉时页顶那一行「正在核对…」(真源 `.team-sync`:label 字号 +
/// 次要色 + aria-role=status)。⚠️ 与整页骨架互斥 —— 已有数据时不清屏,
/// 只在这一行上表示「正在核」,否则用户以为页面被重置了。
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Row(
        children: <Widget>[
          const CupertinoActivityIndicator(),
          const SizedBox(width: CyTokens.space2),
          Text(
            text,
            style: CyType.caption1.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

typedef TeamInfoLoader =
    Future<Map<String, dynamic>> Function({int? teamId, String? inviteCode});

typedef TeamJoinLoader = Future<Map<String, dynamic>> Function(String code);

class TeamDetailPage extends ConsumerStatefulWidget {
  const TeamDetailPage({super.key, required this.teamId, this.loadTeam});
  final int teamId;
  final TeamInfoLoader? loadTeam;

  @override
  ConsumerState<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends ConsumerState<TeamDetailPage> {
  Map<String, dynamic>? _team;
  List<Map<String, dynamic>> _members = const <Map<String, dynamic>>[];
  bool _joined = false;
  bool _leader = false;
  bool _loading = true;
  bool _busy = false;
  ({String title, String sub, IconData icon})? _fault;

  bool get _missingTeamId => widget.teamId <= 0;

  @override
  void initState() {
    super.initState();
    if (_missingTeamId) {
      _loading = false;
      _fault = (
        title: '队伍链接不完整',
        sub: '请从活动、订单或队长分享的邀请重新进入',
        icon: CupertinoIcons.info_circle,
      );
      return;
    }
    _load();
  }

  void _leaveMissingLink() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/clubs');
    }
  }

  /// 回读服务端事实。**返回是否真的读到了** —— 调用方据此决定能不能播
  /// 「已改为…」那句回执:读不到却照播,就是拿期望值冒充服务端值。
  Future<bool> _load() async {
    setState(() {
      _loading = true;
      _fault = null;
    });
    try {
      final Map<String, dynamic> data = widget.loadTeam == null
          ? await ref
                .read(pageParityApiProvider)
                .teamInfo(teamId: widget.teamId)
          : await widget.loadTeam!(teamId: widget.teamId);
      if (!mounted) return false;
      setState(() {
        _team = data['team'] is Map<String, dynamic>
            ? data['team'] as Map<String, dynamic>
            : null;
        _members = _rows(data['members']);
        _joined = data['joined'] == true;
        _leader = data['leader'] == true;
        _loading = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _loading = false);
      if (_team != null) {
        // 已有队伍信息时不清屏:真源 `autoErrorToast: hasTeam` —— 失败弹一句,
        // 上一份确认过的队伍留着看。整页错误壳只给「什么都没有」那一档。
        CyNativeNotice.show(context, '队伍状态暂未更新', isError: true);
        return false;
      }
      setState(
        () => _fault = _loadFault(
          e,
          dataTitle: '队伍暂时不可用',
          dataFallbackSub: '请稍后重新加载',
        ),
      );
      return false;
    }
  }

  Future<void> _setJoinMode(bool inviteOnly) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(teamMapApiProvider)
          .setJoinMode(teamId: widget.teamId, inviteOnly: inviteOnly);
      if (!mounted) return;
      // 切完读回服务端事实,不本地取反 —— 失败时取反会让开关和服务端对不上。
      // 读不回就不播回执:开关仍停在上一份确认过的值,失败已由 `_load` 弹过。
      if (await _load() && mounted) {
        // ★ 播的是**读回来的**那一档(真源 `cyToast(applied === 2 ? ...)`)。
        CyNativeNotice.show(
          context,
          _id(_team?['joinMode']) == 2 ? '已改为公开招募' : '已改为仅邀请',
        );
      }
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          _actionFault(e, dataFallback: '切换失败，请重试'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final String code = _text(_team?['inviteCode']);
    if (code.isEmpty) {
      CyNativeNotice.show(context, '邀请已失效', isError: true);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        title: _text(_team?['title'], '来和我一起组队出发'),
        text: '城瘾队伍邀请码：$code',
      ),
    );
  }

  /// 危险动作:确认 → 提交 → 回执。★ 四段文案逐字取自真源
  /// `utils/danger-actions.js`(`team.kick` / `team.quit` / `team.disband`)。
  /// 真源的 `alt`(解散 → 改为退出队伍)这一档 App 侧落不了地:`cyConfirm`
  /// 只有确认/取消两枚按钮,共用层加第三枚之前不自己造弹层(见本轮报告)。
  Future<void> _action(
    String action,
    Map<String, dynamic> body, {
    required String title,
    required String confirmText,
    required String content,
    required String done,
  }) async {
    final bool ok = await cyConfirm(
      context,
      title: title,
      content: content,
      confirmText: confirmText,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(pageParityApiProvider).teamAction(action, body);
      if (!mounted) return;
      CyNativeNotice.show(context, done);
      await _load();
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          _actionFault(e, dataFallback: '操作失败'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? team = _team;
    final List<Map<String, dynamic>> members = _members;
    final int status = _id(team?['status']) ?? 0;
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: SafeArea(
        bottom: false,
        child: _loading && team == null
            ? const LoadingView()
            : _fault != null && team == null
            // 状态壳走共用层 StatusView(= 小程序 cy-state-shell):主标说
            // 「缺什么 / 发生了什么」,动作说下一步。两档的文案都由 `_fault`
            // 一处给(_missingTeamId 走 initState 那份,失败走 `_loadFault`)。
            ? StatusView(
                message: _fault!.title,
                sub: _fault!.sub,
                icon: _fault!.icon,
                large: true,
                onRetry: _missingTeamId ? _leaveMissingLink : _load,
                retryLabel: _missingTeamId ? '返回上一页' : '重新加载',
              )
            : Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const CyPageTitle('队伍详情'),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          CyTokens.pageX,
                          CyTokens.space1,
                          CyTokens.pageX,
                          CyTokens.space6,
                        ),
                        children: <Widget>[
                          // 重拉(切加入方式、动完危险动作之后回读)时不清屏,
                          // 页顶给一行「正在核对…」= 真源 `.team-sync`。
                          if (_loading) const _SyncLine(text: '正在核对队伍状态…'),
                          // 胶囊走共用层 CyTag:小程序 `.team-status.live`
                          // (status < 2 = 招募中 / 已满员)是 brand-soft 底,
                          // 其余走中性底 —— 这一档就是 CyTag 的 brand 位。
                          // ⚠️ 用 Row 而不是 Align 包住:CyTag 内部带
                          //   `alignment`,在有界宽约束下会**撑满整行**;
                          //   Row 的非弹性子项拿的是无界主轴约束,才会缩成胶囊。
                          Row(
                            children: <Widget>[
                              CyTag(
                                label: _teamStatusText(status),
                                brand: status < 2,
                              ),
                            ],
                          ),
                          const SizedBox(height: CyTokens.space2),
                          Text(
                            _text(team?['title'], '一起出发的玩家队伍'),
                            style: CyType.title1.copyWith(
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space1),
                          Text(
                            // ★ 加入方式写死「邀请制队伍」会把公开招募的队说成
                            //   「只有链接能进」—— 队长正是靠这一句决定要不要在这里
                            //   等陌生人申请。真源按 joinMode 分两档。
                            '${_id(team?['joinMode']) == 2 ? '公开招募 · 陌生人可在附近队伍里申请' : '仅邀请 · 只能通过邀请链接加入'} · 组队与否不影响活动举行',
                            style: CyType.footnote.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space4),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _Metric(
                                  // 当前成员数用服务端的 joinedCount:成员列表在
                                  // 移出/加入后可能还没重新拉,用列表长度会少报一个
                                  // —— 而这一格正是用户判断「还差几个人」的依据。
                                  '${_id(team?['joinedCount']) ?? members.length}'
                                  ' / ${_id(team?['maxMembers']) ?? '-'}',
                                  '当前成员',
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  _teamExpireText(team?['expireTime']),
                                  '场次开始',
                                ),
                              ),
                            ],
                          ),
                          if (status == 0) ...<Widget>[
                            const SizedBox(height: CyTokens.space4),
                            CyNativeButton(
                              label: '邀请队友',
                              width: double.infinity,
                              loading: _busy,
                              onPressed: _busy ? null : _share,
                            ),
                            if (!_joined)
                              CyNativeButton(
                                label: '加入队伍',
                                width: double.infinity,
                                role: CyNativeButtonRole.secondary,
                                onPressed: () => context.push(
                                  '/team/join?code=${Uri.encodeQueryComponent(_text(team?['inviteCode']))}'
                                  '&fromTeamId=${widget.teamId}',
                                ),
                              ),
                          ],
                          // ★ 队长收窄队伍的入口(`POST /api/team/join-mode`)。
                          //   快照 `components/cy/scene-member-order-detail/index.wxml:106-110`
                          //   的注释原话:「后端有 POST /api/team/join-mode(队长可随时切),
                          //   但全仓没有任何前端调用点 —— 队伍详情页还没接这个控件」。
                          //   这里补上这「第二次机会」。
                          // ⚠️ **只在服务端下发了 joinMode 时才画开关**:拿不到当前值
                          //   就盲切,会把「改回公开」也做成「改成仅邀请」
                          //   (team_map_api.dart `setJoinMode` 的同一条警告)。
                          // ⚠️ 并且**只在招募中(status=0)画** —— 真源 `index.wxml:33`
                          //   的原话:「满员/进行中/已结束的队伍已不在「附近的队伍」里,
                          //   切了也无处生效」。给一个不生效的开关等于给一个会失败的按钮。
                          if (_leader &&
                              status == 0 &&
                              _id(team?['joinMode']) != null) ...<Widget>[
                            const SizedBox(height: CyTokens.space4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.space3,
                                vertical: CyTokens.space2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.bgSurface,
                                border: Border.all(
                                  color: palette.cardBorder,
                                ),
                                borderRadius: BorderRadius.circular(
                                  CyTokens.radiusLg,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          // 真源这一行的名字是「公开招募」,
                                          // 开关的**开**=公开(joinMode=2)。
                                          // 反过来写成「仅邀请可加入」看着等价,
                                          // 实际把默认档说反了:没下发 joinMode
                                          // 时真源按「仅邀请」渲染,那句标签会
                                          // 变成「没开 = 公开」的反话。
                                          '公开招募',
                                          style: CyType.body.copyWith(
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                      ),
                                      CupertinoSwitch(
                                        value: _id(team?['joinMode']) == 2,
                                        onChanged: _busy
                                            ? null
                                            : (bool value) =>
                                                  _setJoinMode(!value),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _id(team?['joinMode']) == 2
                                        ? '陌生人可在附近队伍里申请加入'
                                        : '只有拿到邀请链接的人能加入',
                                    style: CyType.caption1.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: CyTokens.space4),
                          const CySectionTitle('队伍成员'),
                          const SizedBox(height: CyTokens.space2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space3,
                            ),
                            decoration: BoxDecoration(
                              color: palette.bgSurface,
                              border: Border.all(color: palette.cardBorder),
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusLg,
                              ),
                            ),
                            // 空态 = 小程序 `<cy-empty>` → App 的共用层 StatusView。
                            child: members.isEmpty
                                ? const StatusView(
                                    message: '还没有队员',
                                    sub: '把邀请发给同行的朋友，他们加入后会出现在这里',
                                  )
                                : Column(
                                    children: members.map((
                                      Map<String, dynamic> member,
                                    ) {
                                      final int? memberId = _id(
                                        member['memberId'],
                                      );
                                      final bool isCaptain =
                                          _id(member['role']) == 1;
                                      // 小程序 `.team-member:last-child
                                      // { border-bottom: 0 }` —— 末行再画一条
                                      // 会和卡片自身的底边叠成双线。
                                      final bool isLast = identical(
                                        member,
                                        members.last,
                                      );
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: CyTokens.space2,
                                        ),
                                        decoration: isLast
                                            ? null
                                            : BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: palette
                                                        .borderSubtle,
                                                  ),
                                                ),
                                              ),
                                        child: Row(
                                          children: <Widget>[
                                            ClipOval(
                                              child: SizedBox(
                                                width: 40,
                                                height: 40,
                                                // ★ 兜底走共用层,不指向 asset:
                                                //   之前写的
                                                //   `assets/home/home-profile-default.png`
                                                //   仓里根本没有,真机上是加载失败的空白
                                                //   (测试里直接抛 Unable to load asset)。
                                                //   小程序那边是 `/images/d_profile.png`,
                                                //   App 侧统一用「人像图标 + 主题底」。
                                                child: CyNetImage(
                                                  _text(
                                                    member['memberAvatar'],
                                                  ),
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                  fallback: Icon(
                                                    CupertinoIcons.person_fill,
                                                    size: 22,
                                                    color: CyPalette.of(
                                                      context,
                                                    ).textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: CyTokens.space2,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    _text(
                                                      member['memberName'],
                                                      '城瘾玩家',
                                                    ),
                                                    style: CyType.headline
                                                        .copyWith(
                                                          color: palette
                                                              .textPrimary,
                                                        ),
                                                  ),
                                                  Text(
                                                    isCaptain ? '队长' : '队员',
                                                    style: CyType.caption1
                                                        .copyWith(
                                                          color: palette
                                                              .textSecondary,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (_leader &&
                                                !isCaptain &&
                                                memberId != null)
                                              CupertinoButton(
                                                padding: EdgeInsets.zero,
                                                // 触达区:CupertinoButton 默认
                                                // kMinInteractiveDimensionCupertino
                                                // (44pt),padding 归零仍达标。
                                                // 文字色:小程序 .team-member-op
                                                // 是 danger 红(破坏性动作)。
                                                onPressed: _busy
                                                    ? null
                                                    : () => _action(
                                                        'kick',
                                                        <String, dynamic>{
                                                          'teamId':
                                                              widget.teamId,
                                                          'memberId': memberId,
                                                        },
                                                        // 真源 `team.kick`:标题点名
                                                        // 是谁,后果三条逐字搬。
                                                        title:
                                                            '把「${_text(member['memberName'], '这名队员')}」移出队伍?',
                                                        confirmText: '移出队员',
                                                        content:
                                                            '· 对方会收到站内通知,并失去队伍群聊入口\n'
                                                            '· 移出不同步退票,对方的票仍然有效\n'
                                                            '· 此操作不可撤销;被移出的人不能用邀请码回来,需要重新申请加入',
                                                        done:
                                                            '队员已移出，对方已收到站内通知。',
                                                      ),
                                                child: Text(
                                                  '移出',
                                                  style: CyType.caption1
                                                      .copyWith(
                                                        color: palette
                                                            .statusDanger,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          if (_joined && status < 2) ...<Widget>[
                            const SizedBox(height: CyTokens.space3),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: CyNativeButton(
                                    label: _leader ? '退出并移交队长' : '退出队伍',
                                    role: CyNativeButtonRole.secondary,
                                    onPressed: _busy
                                        ? null
                                        : () => _action(
                                            'quit',
                                            <String, dynamic>{
                                              'teamId': widget.teamId,
                                            },
                                            // 真源 `team.quit`。
                                            title: '退出这支队伍?',
                                            confirmText: '退出队伍',
                                            content:
                                                '退队不会同步退票,你的票仍然有效。\n'
                                                '· 你会失去队伍群聊入口\n'
                                                '· 你是队长的话,队长会移交给最早加入的队员;只剩你一人时队伍直接解散\n'
                                                '· 此操作不可撤销,需要重新被邀请才能回到这支队伍',
                                            done: '已退出队伍，你的票仍然有效,可以自己去核销。',
                                          ),
                                  ),
                                ),
                                if (_leader) ...<Widget>[
                                  const SizedBox(width: CyTokens.space2),
                                  Expanded(
                                    child: CyNativeButton(
                                      label: '解散队伍',
                                      role: CyNativeButtonRole.destructive,
                                      onPressed: _busy
                                          ? null
                                          : () => _action(
                                              'disband',
                                              <String, dynamic>{
                                                'teamId': widget.teamId,
                                              },
                                              // 真源 `team.disband`(它的 `alt`
                                              // 「改为退出队伍」要第三枚按钮,
                                              // `cyConfirm` 现在给不了)。
                                              title: '解散这支队伍?',
                                              confirmText: '解散队伍',
                                              content:
                                                  '队伍解散后群聊关闭,队员各自回到未组队状态。\n'
                                                  '· 全部队员会被移出队伍,队伍群聊同时关闭\n'
                                                  '· 不会触发任何退款;队员各自的票仍然有效,需要自己去核销\n'
                                                  '· 此操作不可撤销,队伍与聊天记录无法恢复',
                                              done: '队伍已解散，队员已收到通知。',
                                            ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          if (_joined) ...<Widget>[
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              '退队不会退款；如需退票，请在订单中单独处理。',
                              style: CyType.caption1.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
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

class TeamJoinPage extends ConsumerStatefulWidget {
  const TeamJoinPage({
    super.key,
    required this.code,
    this.loadTeam,
    this.joinTeam,
  });
  final String code;
  final TeamInfoLoader? loadTeam;
  final TeamJoinLoader? joinTeam;

  @override
  ConsumerState<TeamJoinPage> createState() => _TeamJoinPageState();
}

class _TeamJoinPageState extends ConsumerState<TeamJoinPage> {
  Map<String, dynamic>? _team;
  bool _joined = false;
  bool _loading = true;
  bool _joining = false;
  ({String title, String sub, IconData icon})? _fault;

  /// 加入动作本身的失败(真源 `joinError` → 卡片与按钮之间的 `cy-inline-error`)。
  /// 与「读不到邀请」分开:_fault 是整页没内容,_joinError 是页面在、动作没成。
  String? _joinError;

  bool get _missingInvite => widget.code.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_missingInvite) {
      setState(() {
        _loading = false;
        _fault = (
          title: '邀请链接不完整',
          sub: '请从队长分享的邀请重新进入',
          icon: CupertinoIcons.info_circle,
        );
      });
      return;
    }
    try {
      final data = widget.loadTeam == null
          ? await ref
                .read(pageParityApiProvider)
                .teamInfo(inviteCode: widget.code.trim())
          : await widget.loadTeam!(inviteCode: widget.code.trim());
      if (!mounted) return;
      setState(() {
        _team = data['team'] is Map<String, dynamic>
            ? data['team'] as Map<String, dynamic>
            : data;
        _joined = data['joined'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (_team != null) {
        // 真源 `autoErrorToast: hasTeam`:邀请卡还在,失败只弹一句,不整页翻成错误壳。
        CyNativeNotice.show(context, '邀请状态暂未更新', isError: true);
        return;
      }
      setState(
        () => _fault = _loadFault(
          e,
          dataTitle: '邀请暂时不可用',
          dataFallbackSub: '请让队长重新分享后再试',
        ),
      );
    }
  }

  void _leaveMissingLink() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/clubs');
    }
  }

  int? get _sourceTeamId {
    final GoRouter? router = GoRouter.maybeOf(context);
    return int.tryParse(router?.state.uri.queryParameters['fromTeamId'] ?? '');
  }

  void _goToTeamDetail(int teamId) {
    if (_sourceTeamId == teamId && context.canPop()) {
      context.pop();
      return;
    }
    context.go('/team/$teamId');
  }

  /// 加入动作的失败一句话(真源 `join()`):服务端 msg 优先,没有才用
  /// 「邀请状态可能已变化，请重试」;传输层固定「网络没连上，请检查后重试」。
  String _joinFault(Object error) {
    if (error is PageParityApiException) {
      return error.message == '请求失败'
          ? '邀请状态可能已变化，请重试'
          : error.message;
    }
    return '网络没连上，请检查后重试';
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final data = widget.joinTeam == null
          ? await ref.read(pageParityApiProvider).teamJoin(widget.code.trim())
          : await widget.joinTeam!(widget.code.trim());
      final int? teamId = _id(
        data['teamId'] ?? data['id'] ?? _team?['id'] ?? _team?['teamId'],
      );
      if (!mounted) return;
      CyNativeNotice.show(context, '已加入队伍');
      setState(() {
        _joined = true;
        _joining = false;
      });
      if (teamId != null) _goToTeamDetail(teamId);
    } catch (e) {
      // ★ 失败走卡与按钮之间的 `cy-inline-error`(真源 `joinError`),不是
      //   一闪而过的 toast:这一页的用户下一步就是「重试加入」。
      if (mounted) setState(() => _joinError = _joinFault(e));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: SafeArea(
        child: _loading && _team == null
            ? const LoadingView()
            : _fault != null && _team == null
            // 整页错误壳只给「什么都没读到」那一档;链接不完整与读失败共用
            // 一个壳,差别在主标和下一步动作(真源 errorKind 两档)。
            ? StatusView(
                message: _fault!.title,
                sub: _fault!.sub,
                icon: _fault!.icon,
                large: true,
                onRetry: _missingInvite ? _leaveMissingLink : _load,
                retryLabel: _missingInvite ? '返回上一页' : '重新加载',
              )
            : Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const CyPageTitle('加入队伍'),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          CyTokens.pageX,
                          0,
                          CyTokens.pageX,
                          CyTokens.space6,
                        ),
                        children: <Widget>[
                          // 重拉邀请时保留上一份邀请卡,只在这一行表示「正在核」
                          // (真源 `loading && !team` 才出骨架,`refreshing` 出行)。
                          if (_loading) const _SyncLine(text: '正在核对邀请状态…'),
                          // 眉标:小程序 .team-eyebrow(brand 色 + 700)→ 梯级
                          // Caption1 + Semibold(T3:强调不堆 w800)。
                          Text(
                            'TEAM INVITATION',
                            style: CyType.caption1.copyWith(
                              fontWeight: FontWeight.w600,
                              color: palette.brand,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space2),
                          Text(
                            _text(_team?['title'], '一起出发的玩家队伍'),
                            style: CyType.title1.copyWith(
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space2),
                          Text(
                            '你收到一份组队邀请。组队与否不影响活动举行，入队不会代替报名或购票。',
                            style: CyType.footnote.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space4),
                          Container(
                            padding: const EdgeInsets.all(CyTokens.space3),
                            decoration: BoxDecoration(
                              color: palette.bgSurface,
                              border: Border.all(color: palette.cardBorder),
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusLg,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _Metric(
                                        '${_id(_team?['joinedCount']) ?? 0} / ${_id(_team?['maxMembers']) ?? '-'}',
                                        '当前成员',
                                      ),
                                    ),
                                    const Expanded(
                                      child: _Metric('邀请制', '加入方式'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: CyTokens.space3),
                                Text(
                                  '加入后会进入队伍群聊。退队与退票互不联动。',
                                  style: CyType.caption1.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 加入失败的页内错误条(真源 `cy-inline-error`,
                          // 位置就钉在邀请卡与动作之间)。
                          if (_joinError != null) ...<Widget>[
                            const SizedBox(height: CyTokens.space3),
                            _JoinInlineError(
                              detail: _joinError!,
                              onRetry: _joining ? null : _join,
                            ),
                          ],
                          const SizedBox(height: CyTokens.space3),
                          CyNativeButton(
                            label: _joined
                                ? '查看队伍'
                                : _joining
                                ? '加入中…'
                                : (_id(_team?['status']) ?? 0) == 0
                                ? '接受邀请并加入'
                                : (_id(_team?['status']) ?? 0) == 1
                                ? '队伍已满'
                                : '队伍已结束',
                            width: double.infinity,
                            loading: _joining,
                            // 真源 `pages/team/join/index.wxml:31-39` 的三档:
                            // 「查看队伍」和「接受邀请并加入」都是 `team-action
                            // primary`(白底),只有走不通的那档(队伍已满 /
                            // 队伍已结束)才是 `disabled secondary`。把「查看队伍」
                            // 降成灰的,等于告诉用户这条邀请没用了 —— 而他其实
                            // 已经在这支队伍里。
                            role: _joined || (_id(_team?['status']) ?? 0) == 0
                                ? CyNativeButtonRole.primary
                                : CyNativeButtonRole.secondary,
                            onPressed: _joining
                                ? null
                                : _joined
                                ? () {
                                    final int? teamId = _id(
                                      _team?['id'] ?? _team?['teamId'],
                                    );
                                    if (teamId != null) {
                                      _goToTeamDetail(teamId);
                                    }
                                  }
                                : (_id(_team?['status']) ?? 0) == 0
                                ? _join
                                : null,
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

/// 加入动作的页内错误条。★ 真源 `cy-inline-error`:图标 + 主/副标 + 一个动作,
/// 主标固定「暂时无法加入」,副标是失败原因,动作是「重试加入」。
/// 破坏性不在这里(加入不是不可逆动作),所以不套 `cyConfirm`。
class _JoinInlineError extends StatelessWidget {
  const _JoinInlineError({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 真源 `.inline-error--error`:软红底卡 + 红 ⚠ + 主/副标 + 胶囊动作。
    // 「失败不能穿提示的衣服」(components/cy/inline-error/index.js 的注释),
    // 所以这一档必须是 danger 底,而不是裸在页面背景上的一行字。
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.statusDanger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 状态不只靠颜色(V5):警示形状 + 文字两路一起说。
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 20,
            color: palette.statusDanger,
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '暂时无法加入',
                  style: CyType.headline.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  detail,
                  style: CyType.footnote.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          // 动作是胶囊按钮(.inline-error__action:min-width 72pt、pill、
          // label/600),不是裸文字 —— 裸文字在软红底上看着像说明的一部分。
          // CupertinoButton 给的命中区仍是 44pt(L9)。
          CupertinoButton(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            minimumSize: const Size(72, CyTokens.btnH),
            onPressed: onRetry,
            child: Text(
              '重试加入',
              style: CyType.caption1.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      // ★ 左对齐:真源 `.team-meta-item { flex: 1 }` + `.team-meta-value
      //   { display: block }` 没有任何 text-align,两列数值是**贴着列宽左沿**
      //   排的。Column 默认居中会把这一行推成「居中统计块」—— 那是 AI 排版味,
      //   也不是小程序的排法。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 小程序 .team-meta-value = --cy-type-card-title(32rpx = 16)→ 梯级
        // Callout 16;w800 按 T3 收成 Semibold。
        Text(
          value,
          style: CyType.callout.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          label,
          style: CyType.caption1.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
