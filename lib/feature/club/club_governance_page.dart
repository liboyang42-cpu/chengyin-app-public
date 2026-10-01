import 'club_customer_labels.dart';
import '../../l10n/strings.dart';
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
        _error = '';
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
    if (_mode == 'appeal') return stringsOf(context).clubGovAppealTitle;
    if (_mode == 'report') {
      return switch (_reportTargetType) {
        'CLUB' => stringsOf(context).clubGovClubReport,
        'ACTIVITY' => stringsOf(context).clubGovActivityReport,
        _ => stringsOf(context).clubGovMemberReport,
      };
    }
    return stringsOf(context).clubGovTitle;
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
          _error = stringsOf(context).clubGovWrongClub;
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
          _error = stringsOf(context).clubGovOwnerOnly;
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
        _error = clubOpsErrorMessage(error, stringsOf(context).clubGovAccessUnavailable);
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
          _error = stringsOf(context).clubGovRecordsUnavailable;
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
        preselectedName = clubMemberDisplayName(context, selectable.firstWhere((ClubMember m) => m.memberId == preselected));
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
        _error = clubOpsErrorMessage(error, stringsOf(context).clubGovRecordsUnavailable);
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
          _error = stringsOf(context).clubGovCasesUnavailable;
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
        _error = clubOpsErrorMessage(error, stringsOf(context).clubGovCasesUnavailable);
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
      CyNativeNotice.show(context, stringsOf(context).clubGovReasonRequired, isError: true);
      return null;
    }
    return reason;
  }

  Future<void> _banSelectedMember() async {
    if (_actingKey.isNotEmpty) return;
    final int? memberId = _selectedMemberId;
    if (memberId == null) {
      CyNativeNotice.show(context, stringsOf(context).clubGovMemberRequired, isError: true);
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
      CyNativeNotice.show(context, stringsOf(context).clubGovMemberChanged, isError: true);
      return;
    }
    final String? reason = await _promptReason(
      title: stringsOf(context).clubGovBanTitle(clubMemberDisplayName(context, member)),
      placeholder: stringsOf(context).clubGovBanReason,
      confirmText: stringsOf(context).clubGovConfirmBan,
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
      CyNativeNotice.show(context, stringsOf(context).clubGovBanned);
      setState(() => _selectedMemberId = null);
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubGovBanFailed),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _unbanMember(GovernanceBan row) async {
    if (_actingKey.isNotEmpty) return;
    final String? reason = await _promptReason(
      title: stringsOf(context).clubGovUnbanTitle(row.targetNickname),
      placeholder: stringsOf(context).clubGovReviewReason,
      confirmText: stringsOf(context).clubGovUnbanAction,
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
      CyNativeNotice.show(context, stringsOf(context).clubGovUnbanned);
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubGovUnbanFailed),
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
      CyNativeNotice.show(context, stringsOf(context).clubGovMemberRequired, isError: true);
      return;
    }
    final String? reason = await _promptReason(
      title: stringsOf(context).clubGovTransferTitle(clubMemberDisplayName(context, member)),
      placeholder: stringsOf(context).clubGovTransferReason,
      confirmText: stringsOf(context).clubGovConfirmTransfer,
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
      CyNativeNotice.show(context, stringsOf(context).clubGovTransferred);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubGovTransferFailed),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  Future<void> _submitCase({required bool appeal}) async {
    if (_actingKey.isNotEmpty) return;
    final String? reason = await _promptReason(
      title: appeal ? stringsOf(context).clubGovSubmitAppeal : stringsOf(context).clubGovSubmitReport,
      placeholder: appeal ? stringsOf(context).clubGovAppealReason : stringsOf(context).clubGovReportFacts,
      confirmText: stringsOf(context).clubGovSubmitPlatform,
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
      CyNativeNotice.show(context, stringsOf(context).clubGovSubmitted);
      await _loadMyCases();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubGovSubmitFailed),
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
      _selectedMemberName = clubMemberDisplayName(context, picked);
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
          stringsOf(context).clubGovSelectMember,
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
            title: clubMemberDisplayName(context, member),
            leading: CyAvatar(
              url: member.avatar,
              fallback: clubMemberDisplayName(context, member),
              size: 36,
            ),
            trailing: Text(
              _selectedMemberId == member.memberId ? stringsOf(context).clubGovSelected : stringsOf(context).clubGovSelect,
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
              stringsOf(context).clubGovSelectDuration,
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
                title: stringsOf(context).clubGovDuration(option.days),
                trailing: Text(
                  _selectedDurationDays == option.days ? stringsOf(context).clubGovSelected : stringsOf(context).clubGovSelect,
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
    setState(() {
      _selectedDurationDays = days;
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
        message: stringsOf(context).clubGovLogin,
        onSignedIn: _mode == 'appeal' ? _loadMyCases : _load,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).clubGovDenied,
          sub: _error.isEmpty ? stringsOf(context).clubGovDeniedBody : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).clubGovNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _mode == 'appeal' ? _loadMyCases : _load,
        );
      case ClubOpsLoadState.error:
        if (_mode == 'report' && _reportTargetId == null) {
          return StatusView(
            message: stringsOf(context).clubGovInvalidTarget,
            sub: _error,
            icon: CupertinoIcons.exclamationmark_triangle,
            large: true,
          );
        }
        return StatusView(
          message: stringsOf(context).clubGovUnavailable,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _mode == 'appeal' ? _loadMyCases : _load,
        );
      case ClubOpsLoadState.ready:
        if (_empty) {
          return StatusView(
            message: stringsOf(context).clubGovEmptyMembers,
            sub: stringsOf(context).clubGovEmptyMembersBody,
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
            title: stringsOf(context).clubGovPlatformReport,
            note: stringsOf(context).clubGovPlatformReportBody,
            buttonLabel: stringsOf(context).clubGovWriteFacts,
            buttonKey: 'governance-report',
            onPressed: () => _submitCase(appeal: false),
          ),
        if (_mode == 'appeal')
          _platformActionSection(
            title: stringsOf(context).clubGovActiveAppeal,
            note:
                stringsOf(context).clubGovAppealExplanation,
            buttonLabel: stringsOf(context).clubGovWriteAppeal,
            buttonKey: 'governance-appeal',
            onPressed: () => _submitCase(appeal: true),
          ),
        if (_mode == 'manage')
          ClubOpsSection(
            title: stringsOf(context).clubGovRecords,
            children: <Widget>[
              if (_bans.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                  child: StatusView(
                    message: stringsOf(context).clubGovNoRecords,
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
            title: stringsOf(context).clubGovMemberActions,
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  CyCell(
                    key: const Key('governance-pick-member'),
                    title: stringsOf(context).clubGovSelectMember,
                    trailing: Text(
                      _selectedMemberName.isEmpty ? stringsOf(context).clubGovUnselected : _selectedMemberName,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: palette.textTertiary,
                      ),
                    ),
                    onTap: _pickMember,
                  ),
                  CyCell(
                    key: const Key('governance-pick-duration'),
                    title: stringsOf(context).clubGovSelectDuration,
                    trailing: Text(
                      stringsOf(context).clubGovDuration(_selectedDurationDays),
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: palette.textTertiary,
                      ),
                    ),
                    onTap: _pickDuration,
                  ),
                  ClubOpsRow(
                    key: const Key('governance-ban'),
                    title: stringsOf(context).clubGovBanReasonLabel,
                    enabled: _selectedMemberId != null && _actingKey.isEmpty,
                    trailing: Text(
                      stringsOf(context).clubGovWriteBan,
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
                      title: stringsOf(context).clubGovTransfer,
                      meta: stringsOf(context).clubGovTransferWarning,
                      enabled: _selectedMemberId != null && _actingKey.isEmpty,
                      trailing: Text(
                        stringsOf(context).clubGovTransferSelected,
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
            title: stringsOf(context).clubGovMyCases,
            children: <Widget>[
              if (_cases.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                  child: StatusView(
                    message: stringsOf(context).clubGovNoCases,
                    icon: CupertinoIcons.tray,
                  ),
                )
              else
                ClubOpsCard(
                  children: _cases
                      .map(
                        (GovernanceCase item) => ClubOpsRow(
                          key: Key('governance-case-${item.id}'),
                          title: _caseTypeLabel(item.typeText),
                          meta: _caseMeta(item),
                          metaLines: 3,
                          value: _caseStatusLabel(item.status),
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
        '${ban.sourceType == 'PLATFORM' ? stringsOf(context).clubGovPlatformSource : stringsOf(context).clubGovClubSource} · ${ban.bannedAtText} · ${ban.expiresText}'
        '${ban.status == 'ACTIVE' && ban.sourceType == 'PLATFORM' ? stringsOf(context).clubGovOnlyPlatform : ''}';
    final String meta = ban.unbanReason.isEmpty
        ? desc
        : stringsOf(context).clubGovUnbanNote(desc, ban.unbanReason);
    return ClubOpsRow(
      key: Key('governance-ban-${ban.id}'),
      title: stringsOf(context).clubGovMemberTitle(ban.targetNickname),
      meta: meta,
      metaLines: 3,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _banStatusLabel(ban.status),
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: _banStatusColor(ban.status, palette),
            ),
          ),
          if (ban.canClubUnban)
            ClubOpsRowLink(
              key: Key('governance-unban-${ban.id}'),
              label: stringsOf(context).clubGovUnban,
              enabled: _actingKey.isEmpty,
              onTap: () => _unbanMember(ban),
            ),
        ],
      ),
    );
  }

  String _caseMeta(GovernanceCase item) {
    final StringBuffer buffer = StringBuffer(item.reason);
    buffer.write(stringsOf(context).clubGovSubmittedAt(item.createTimeText));
    if (item.decisionReason.isNotEmpty) {
      buffer.write(stringsOf(context).clubGovPlatformNote(item.decisionReason));
    }
    return buffer.toString();
  }

  String _banStatusLabel(String status) => switch (status) {
    'ACTIVE' => stringsOf(context).clubGovActive,
    'EXPIRED' => stringsOf(context).clubGovExpired,
    'UNBANNED' => stringsOf(context).clubGovLifted,
    _ => status,
  };

  String _caseStatusLabel(String status) => switch (status) {
    'PENDING' => stringsOf(context).clubGovCasePending,
    'APPROVED' => stringsOf(context).clubGovCaseApproved,
    'REJECTED' => stringsOf(context).clubGovCaseRejected,
    _ => status,
  };

  String _caseTypeLabel(String type) => switch (type) {
    '封禁申诉' => stringsOf(context).clubGovAppealTitle,
    '俱乐部举报' => stringsOf(context).clubGovClubReport,
    '活动举报' => stringsOf(context).clubGovActivityReport,
    '成员举报' => stringsOf(context).clubGovMemberReport,
    _ => type,
  };

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
