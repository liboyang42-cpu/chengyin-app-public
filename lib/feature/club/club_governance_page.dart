import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_ops_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_ops.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

const List<({int days, String label})> _kDurationOptions =
    <({int days, String label})>[
      (days: 7, label: '7 天'),
      (days: 30, label: '30 天'),
      (days: 90, label: '90 天'),
    ];

/// 成员治理。对齐小程序 `pages/club/governance`(@90e66d70)三模式:
/// - `manage`(默认):治理记录 + 对成员执行(封禁 / 解封 / 转让主理人);
/// - `report`:向平台提交治理举报(需带 targetType/targetId);
/// - `appeal`:对当前有效封禁提出申诉(不查俱乐部权限,只拉我的工单)。
///
/// ★ 两个铁律照抄小程序:①封禁/解封/转让/举报/申诉全是「填写理由 → 提交」,
///   理由缺失就中止;②解封按钮只在 `status=ACTIVE && sourceType=CLUB` 时出现
///   (平台封禁仅平台可解)。
class ClubGovernancePage extends ConsumerStatefulWidget {
  const ClubGovernancePage({
    super.key,
    required this.clubId,
    this.mode = 'manage',
    this.targetType,
    this.targetId,
    this.memberId,
  });

  final int clubId;
  final String mode;
  final String? targetType;
  final int? targetId;
  final int? memberId;

  @override
  ConsumerState<ClubGovernancePage> createState() => _ClubGovernancePageState();
}

class _ClubGovernancePageState extends ConsumerState<ClubGovernancePage> {
  ClubOpsLoadState _state = ClubOpsLoadState.loading;
  String _error = '';

  /// 401(没登录)与 403(登录了但没权限)必须分开:前者可恢复,后者不是。
  bool _loginRequired = false;
  String _mode = 'manage';
  String? _reportTargetType;
  int? _reportTargetId;
  List<ClubMember> _members = <ClubMember>[];
  List<GovernanceBan> _bans = <GovernanceBan>[];
  List<GovernanceCase> _cases = <GovernanceCase>[];
  bool _isOwner = false;
  int? _selectedMemberId;
  String _selectedMemberName = '';
  int _selectedDurationDays = 30;
  String _selectedDurationLabel = '30 天';
  String _actingKey = '';
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    final String requested = widget.mode;
    _mode = (requested == 'appeal' || requested == 'report')
        ? requested
        : 'manage';
    if (_mode == 'report') {
      String type = (widget.targetType ?? '').toUpperCase();
      int? targetId = widget.targetId;
      final int? legacyMemberId = widget.memberId;
      if (type.isEmpty && legacyMemberId != null && legacyMemberId > 0) {
        type = 'MEMBER';
      }
      if ((targetId == null || targetId <= 0) &&
          legacyMemberId != null &&
          legacyMemberId > 0) {
        targetId = legacyMemberId;
      }
      if (type == 'CLUB' && (targetId == null || targetId <= 0)) {
        targetId = widget.clubId;
      }
      const List<String> allowed = <String>['CLUB', 'ACTIVITY', 'MEMBER'];
      if (!allowed.contains(type) || targetId == null || targetId <= 0) {
        _state = ClubOpsLoadState.error;
        _error = '缺少合法的举报目标';
        return;
      }
      _reportTargetType = type;
      _reportTargetId = targetId;
    }
    if (_mode == 'appeal') {
      _loadMyCases();
    } else {
      _load();
    }
  }

  String get _pageTitle {
    if (_mode == 'appeal') return '封禁申诉';
    if (_mode == 'report') {
      return '${GovernanceCase.reportTargetText(_reportTargetType ?? '')}举报';
    }
    return '成员治理';
  }

  Future<void> _load() async {
    setState(() {
      _state = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
      _members = <ClubMember>[];
      _bans = <GovernanceBan>[];
      _empty = false;
      _selectedMemberId = null;
      _selectedMemberName = '';
    });
    try {
      final ClubOpsAccess access = await ref
          .read(clubOpsApiProvider)
          .access(clubId: widget.clubId);
      if (!mounted) return;
      if (!access.active || access.clubId != widget.clubId) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = '当前账号不属于该俱乐部';
        });
        return;
      }
      if (_mode == 'report') {
        await _loadMyCases();
        return;
      }
      if (!access.has(kClubMemberManage)) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = '仅主理人与副主理人可进行成员治理';
        });
        return;
      }
      _isOwner = access.isOwner;
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, '治理权限暂时不可用');
      });
    }
  }

  Future<void> _loadManagement() async {
    try {
      final List<ClubMember> members = await ref
          .read(clubApiProvider)
          .members(widget.clubId);
      if (!mounted) return;
      final List<GovernanceBan>? bans = await ref
          .read(clubOpsApiProvider)
          .governanceBans(clubId: widget.clubId);
      if (!mounted) return;
      if (bans == null) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = '治理记录暂时不可用';
        });
        return;
      }
      final List<ClubMember> selectable = members
          .where((ClubMember m) => !m.isOwner && m.memberId > 0)
          .toList();
      final int? requested = widget.memberId;
      final int? preselected =
          requested != null &&
              selectable.any((ClubMember m) => m.memberId == requested)
          ? requested
          : null;
      String preselectedName = '';
      if (preselected != null) {
        preselectedName = selectable
            .firstWhere((ClubMember m) => m.memberId == preselected)
            .displayName;
      }
      setState(() {
        _members = selectable;
        _bans = bans;
        _selectedMemberId = preselected;
        _selectedMemberName = preselectedName;
        _empty = selectable.isEmpty && bans.isEmpty;
        _state = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, '治理记录暂时不可用');
      });
    }
  }

  Future<void> _loadMyCases() async {
    setState(() {
      _state = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
      _cases = <GovernanceCase>[];
    });
    try {
      final List<GovernanceCase>? cases = await ref
          .read(clubOpsApiProvider)
          .governanceCasesMine(clubId: widget.clubId);
      if (!mounted) return;
      if (cases == null) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = '治理工单暂时不可用';
        });
        return;
      }
      setState(() {
        _cases = cases;
        _state = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, '治理工单暂时不可用');
      });
    }
  }

  String _apiDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  Future<String?> _promptReason({
    required String title,
    required String placeholder,
    required String confirmText,
    bool reasonRequired = true,
  }) async {
    final String? value = await showCySystemTextInputAlert(
      context: context,
      title: title,
      placeholder: placeholder,
      confirmText: confirmText,
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (!mounted || value == null) return null;
    final String reason = value.trim();
    if (reasonRequired && reason.isEmpty) {
      CyNativeNotice.show(context, '请填写理由', isError: true);
      return null;
    }
    return reason;
  }

  Future<void> _banSelectedMember() async {
    if (_actingKey.isNotEmpty) return;
    final int? memberId = _selectedMemberId;
    if (memberId == null) {
      CyNativeNotice.show(context, '先选择一位成员', isError: true);
      return;
    }
    ClubMember? member;
    for (final ClubMember candidate in _members) {
      if (candidate.memberId == memberId) {
        member = candidate;
        break;
      }
    }
    if (member == null) {
      CyNativeNotice.show(context, '成员状态已变化，请刷新', isError: true);
      return;
    }
    final String? reason = await _promptReason(
      title: '确认封禁 ${member.displayName}',
      placeholder: '填写封禁原因（必填）',
      confirmText: '确认封禁',
    );
    if (reason == null) return;
    final String key = 'ban:$memberId';
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .banMember(
            clubId: widget.clubId,
            targetMemberId: memberId,
            reason: reason,
            expiresAt: _apiDate(
              DateTime.now().add(Duration(days: _selectedDurationDays)),
            ),
            requestId: ClubOpsApi.newRequestId('cgb'),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '已封禁并移出俱乐部');
      setState(() => _selectedMemberId = null);
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '封禁失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _unbanMember(GovernanceBan row) async {
    if (_actingKey.isNotEmpty) return;
    final String? reason = await _promptReason(
      title: '解除 ${row.targetNickname} 的封禁',
      placeholder: '填写复核说明（可选）',
      confirmText: '解除封禁',
      reasonRequired: false,
    );
    if (reason == null) return;
    final String key = 'unban:${row.id}';
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .unbanMember(
            clubId: widget.clubId,
            banId: row.id,
            version: row.version,
            reason: reason,
            requestId: ClubOpsApi.newRequestId('cgu'),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '已解除封禁');
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '解封失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _transferSelectedOwner() async {
    if (_actingKey.isNotEmpty || !_isOwner) return;
    final int? memberId = _selectedMemberId;
    ClubMember? member;
    if (memberId != null) {
      for (final ClubMember candidate in _members) {
        if (candidate.memberId == memberId) {
          member = candidate;
          break;
        }
      }
    }
    if (member == null) {
      CyNativeNotice.show(context, '先选择一位成员', isError: true);
      return;
    }
    final String? reason = await _promptReason(
      title: '转让主理人给 ${member.displayName}',
      placeholder: '填写交接原因（必填）',
      confirmText: '确认转让',
    );
    if (reason == null) return;
    final String key = 'transfer:$memberId';
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .transferOwner(
            clubId: widget.clubId,
            targetMemberId: memberId!,
            reason: reason,
            requestId: ClubOpsApi.newRequestId('cgt'),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '主理人已转让');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '转让失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _submitCase({required bool appeal}) async {
    if (_actingKey.isNotEmpty) return;
    final String? reason = await _promptReason(
      title: appeal ? '提交封禁申诉' : '提交治理举报',
      placeholder: appeal ? '说明申诉理由与事实（必填）' : '说明具体事实（必填）',
      confirmText: '提交平台',
    );
    if (reason == null) return;
    final String key =
        '${appeal ? 'appeal' : 'report'}:${appeal ? widget.clubId : _reportTargetId}';
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .submitGovernanceCase(
            clubId: widget.clubId,
            appeal: appeal,
            targetType: _reportTargetType,
            targetId: _reportTargetId,
            reason: reason,
            requestId: ClubOpsApi.newRequestId(appeal ? 'cga' : 'cgr'),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '已提交平台处理');
      await _loadMyCases();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '提交失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _pickMember() async {
    final ClubMember? picked = await showCupertinoSheet<ClubMember>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          _memberPicker(controller),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedMemberId = picked.memberId;
      _selectedMemberName = picked.displayName;
    });
  }

  Widget _memberPicker(ScrollController controller) {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space6,
      ),
      children: <Widget>[
        Text(
          '选择成员',
          style: TextStyle(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        ..._members.map(
          (ClubMember member) => ClubOpsRow(
            key: Key('governance-member-${member.memberId}'),
            title: member.displayName,
            leading: CyAvatar(
              url: member.avatar,
              fallback: member.displayName,
              size: 36,
            ),
            trailing: Text(
              _selectedMemberId == member.memberId ? '已选' : '选择',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: _selectedMemberId == member.memberId
                    ? palette.brand
                    : palette.textTertiary,
              ),
            ),
            onTap: () => Navigator.of(context).pop(member),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDuration() async {
    final int? days = await showCupertinoSheet<int>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) {
        final CyPalette palette = CyPalette.of(context);
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space6,
          ),
          children: <Widget>[
            Text(
              '选择期限',
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            ..._kDurationOptions.map(
              (({int days, String label}) option) => ClubOpsRow(
                key: Key('governance-duration-${option.days}'),
                title: option.label,
                trailing: Text(
                  _selectedDurationDays == option.days ? '已选' : '选择',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: _selectedDurationDays == option.days
                        ? palette.brand
                        : palette.textTertiary,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(option.days),
              ),
            ),
          ],
        );
      },
    );
    if (days == null || !mounted) return;
    // 期限只认 7/30/90:别的值服务端会拒,这里先挡住。
    if (days != 7 && days != 30 && days != 90) return;
    final String label = _kDurationOptions
        .firstWhere((({int days, String label}) o) => o.days == days)
        .label;
    setState(() {
      _selectedDurationDays = days;
      _selectedDurationLabel = label;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(_pageTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(_pageTitle),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 游客先登录:401 说成「你没有成员治理的权限」会让人去查自己的角色,
    // 而真因只是没登录 —— 登录后原地重取,人留在这一页。
    if (_loginRequired) {
      return ClubLoginGate(
        message: '登录后查看成员治理',
        onSignedIn: _mode == 'appeal' ? _loadMyCases : _load,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: '你没有成员治理的权限',
          sub: _error.isEmpty ? '成员治理只开给主理人与副主理人。' : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: '网络连接失败',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _mode == 'appeal' ? _loadMyCases : _load,
        );
      case ClubOpsLoadState.error:
        if (_mode == 'report' && _reportTargetId == null) {
          return StatusView(
            message: '缺少合法的举报目标',
            sub: _error,
            icon: CupertinoIcons.exclamationmark_triangle,
            large: true,
          );
        }
        return StatusView(
          message: '治理功能暂时不可用',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _mode == 'appeal' ? _loadMyCases : _load,
        );
      case ClubOpsLoadState.ready:
        if (_empty) {
          return const StatusView(
            message: '暂无可治理成员',
            sub: '成员加入后可在这里进行安全治理；历史记录也会保留。',
            icon: Icons.shield_outlined,
            large: true,
          );
        }
        return _readyBody();
    }
  }

  Widget _readyBody() {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        if (_mode == 'report')
          _platformActionSection(
            title: '向平台提交治理举报',
            note: '请只提交可核实的具体事实。平台审核前，不会自动认定违规或执行封禁。',
            buttonLabel: '填写事实并提交平台',
            buttonKey: 'governance-report',
            onPressed: () => _submitCase(appeal: false),
          ),
        if (_mode == 'appeal')
          _platformActionSection(
            title: '对当前有效封禁提出申诉',
            note:
                '申诉进入平台治理队列；俱乐部主理人和副主理人不能裁决。'
                '申诉通过后解除封禁，但不会自动恢复成员身份。',
            buttonLabel: '填写理由并提交申诉',
            buttonKey: 'governance-appeal',
            onPressed: () => _submitCase(appeal: true),
          ),
        if (_mode == 'manage')
          ClubOpsSection(
            title: '治理记录',
            children: <Widget>[
              if (_bans.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                  child: StatusView(
                    message: '暂无治理记录',
                    icon: Icons.shield_outlined,
                  ),
                )
              else
                ClubOpsCard(
                  children: _bans
                      .map((GovernanceBan ban) => _banRow(ban, palette))
                      .toList(),
                ),
            ],
          ),
        if (_mode == 'manage' && _members.isNotEmpty)
          ClubOpsSection(
            title: '对成员执行',
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  CyCell(
                    key: const Key('governance-pick-member'),
                    title: '选择成员',
                    trailing: Text(
                      _selectedMemberName.isEmpty ? '未选择' : _selectedMemberName,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: palette.textTertiary,
                      ),
                    ),
                    onTap: _pickMember,
                  ),
                  CyCell(
                    key: const Key('governance-pick-duration'),
                    title: '选择期限',
                    trailing: Text(
                      _selectedDurationLabel,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: palette.textTertiary,
                      ),
                    ),
                    onTap: _pickDuration,
                  ),
                  ClubOpsRow(
                    key: const Key('governance-ban'),
                    title: '封禁原因',
                    enabled: _selectedMemberId != null && _actingKey.isEmpty,
                    trailing: Text(
                      '填写原因并封禁',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        fontWeight: FontWeight.w600,
                        color: (_selectedMemberId != null && _actingKey.isEmpty)
                            ? CyTokens.statusDanger
                            : palette.textDisabled,
                      ),
                    ),
                    onTap: _banSelectedMember,
                  ),
                  if (_isOwner)
                    ClubOpsRow(
                      key: const Key('governance-transfer'),
                      title: '转让主理人',
                      meta: '转让后你将失去主理人权限',
                      enabled: _selectedMemberId != null && _actingKey.isEmpty,
                      trailing: Text(
                        '转让给所选成员',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          fontWeight: FontWeight.w600,
                          color:
                              (_selectedMemberId != null && _actingKey.isEmpty)
                              ? CyTokens.statusWarning
                              : palette.textDisabled,
                        ),
                      ),
                      onTap: _transferSelectedOwner,
                    ),
                ],
              ),
            ],
          ),
        if (_mode != 'manage')
          ClubOpsSection(
            title: '我的平台工单',
            children: <Widget>[
              if (_cases.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                  child: StatusView(
                    message: '暂无已提交工单',
                    icon: CupertinoIcons.tray,
                  ),
                )
              else
                ClubOpsCard(
                  children: _cases
                      .map(
                        (GovernanceCase item) => ClubOpsRow(
                          key: Key('governance-case-${item.id}'),
                          title: item.typeText,
                          meta: _caseMeta(item),
                          metaLines: 3,
                          value: item.statusText,
                          valueColor: _caseStatusColor(item.status),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
      ],
    );
  }

  Widget _platformActionSection({
    required String title,
    required String note,
    required String buttonLabel,
    required String buttonKey,
    required VoidCallback onPressed,
  }) {
    return ClubOpsSection(
      title: title,
      note: note,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space3),
          child: CyNativeButton(
            key: Key(buttonKey),
            label: buttonLabel,
            role: CyNativeButtonRole.secondary,
            width: double.infinity,
            onPressed: _actingKey.isEmpty ? onPressed : null,
          ),
        ),
      ],
    );
  }

  Widget _banRow(GovernanceBan ban, CyPalette palette) {
    final String desc =
        '${ban.sourceText} · ${ban.bannedAtText} · ${ban.expiresText}'
        '${ban.status == 'ACTIVE' && ban.sourceType == 'PLATFORM' ? ' · 仅平台可解封' : ''}';
    final String meta = ban.unbanReason.isEmpty
        ? desc
        : '$desc\n解封说明：${ban.unbanReason}';
    return ClubOpsRow(
      key: Key('governance-ban-${ban.id}'),
      title: '成员「${ban.targetNickname}」',
      meta: meta,
      metaLines: 3,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            ban.statusText,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: _banStatusColor(ban.status, palette),
            ),
          ),
          if (ban.canClubUnban)
            ClubOpsRowLink(
              key: Key('governance-unban-${ban.id}'),
              label: '解封',
              enabled: _actingKey.isEmpty,
              onTap: () => _unbanMember(ban),
            ),
        ],
      ),
    );
  }

  String _caseMeta(GovernanceCase item) {
    final StringBuffer buffer = StringBuffer(item.reason);
    buffer.write('\n提交于 ${item.createTimeText}');
    if (item.decisionReason.isNotEmpty) {
      buffer.write('\n平台说明：${item.decisionReason}');
    }
    return buffer.toString();
  }

  Color _banStatusColor(String status, CyPalette palette) {
    switch (status) {
      case 'ACTIVE':
        return CyTokens.statusDanger;
      case 'EXPIRED':
        return CyTokens.statusWarning;
      default:
        return palette.textTertiary;
    }
  }

  Color _caseStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return CyTokens.statusInfo;
      case 'APPROVED':
        return CyTokens.statusSuccess;
      default:
        return CyTokens.statusWarning;
    }
  }
}
