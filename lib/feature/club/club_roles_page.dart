import 'club_customer_labels.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_ops_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_ops.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

/// 角色与权限(仅主理人可进)。对齐小程序 `pages/club/roles`(@90e66d70):
/// - 裁决真源是回执里的 `canManageRoles`,不是「是不是管理员」;
/// - 「回执坏了」与「没权限」是两回事:active 不是布尔 → 错误态(给重试),
///   明确 false / canManageRoles !== true → 无权限态(重试也没用);
/// - 撤销走二次确认 + 结果反馈,requestId 在会话内保持稳定(失败可安全重试);
/// - 4xx 明确失败才丢弃 requestId 重开一条意图。
class ClubRolesPage extends ConsumerStatefulWidget {
  const ClubRolesPage({
    super.key,
    required this.clubId,
    this.activityId,
    this.memberId,
  });

  final int clubId;
  final int? activityId;
  final int? memberId;

  @override
  ConsumerState<ClubRolesPage> createState() => _ClubRolesPageState();
}

class _ClubRolesPageState extends ConsumerState<ClubRolesPage> {
  ClubOpsLoadState _state = ClubOpsLoadState.loading;
  String _error = '';
  bool _loginRequired = false;
  List<ClubMember> _members = <ClubMember>[];
  List<RoleOption> _roles = <RoleOption>[];
  List<RoleAssignment> _assignments = <RoleAssignment>[];
  String _ownerName = '';
  int? _selectedMemberId;
  String _selectedMemberName = '';
  String _selectedRoleCode = '';
  String _selectedRoleName = '';
  String _actingKey = '';
  final Map<String, String> _requestIds = <String, String>{};

  int? get _activityId =>
      (widget.activityId != null && widget.activityId! > 0)
      ? widget.activityId
      : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
      _members = <ClubMember>[];
      _roles = <RoleOption>[];
      _assignments = <RoleAssignment>[];
      _selectedMemberId = null;
      _selectedMemberName = '';
    });
    try {
      final ClubOpsAccess access = await ref
          .read(clubOpsApiProvider)
          .access(clubId: widget.clubId, activityId: _activityId);
      if (!mounted) return;
      // 「响应坏了」→ 错误态;「后端明确说不行」→ 无权限态。
      if (!access.activeDeclared) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = stringsOf(context).clubRolesAccessUnavailable;
        });
        return;
      }
      if (!access.active || !access.canManageRoles) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = stringsOf(context).clubRolesOwnerOnly;
        });
        return;
      }
      if (access.clubId != widget.clubId) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = stringsOf(context).clubRolesAccessUnavailable;
        });
        return;
      }
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubRolesAccessUnavailable);
      });
    }
  }

  Future<void> _loadManagement() async {
    try {
      final RoleScopeData? data = await ref
          .read(clubOpsApiProvider)
          .rolesList(clubId: widget.clubId, activityId: _activityId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = stringsOf(context).clubRolesDirectoryUnavailable;
        });
        return;
      }
      final List<ClubMember> all = await ref
          .read(clubApiProvider)
          .members(widget.clubId);
      if (!mounted) return;
      final List<ClubMember> selectable = all
          .where((ClubMember m) => !m.isOwner && m.memberId > 0)
          .toList();
      final String ownerName = all
          .where((ClubMember m) => m.isOwner)
          .map((ClubMember m) => clubMemberDisplayName(context, m))
          .followedBy(<String>[stringsOf(context).clubRolesOwner])
          .first;
      final int? requested = widget.memberId;
      final int? preselected =
          requested != null &&
              selectable.any((ClubMember m) => m.memberId == requested)
          ? requested
          : null;
      final String preselectedName = preselected == null
          ? ''
          : clubMemberDisplayName(context, selectable.firstWhere((ClubMember m) => m.memberId == preselected));
      setState(() {
        _roles = data.roles;
        _assignments = data.assignments;
        _members = selectable;
        _ownerName = ownerName;
        _selectedMemberId = preselected;
        _selectedMemberName = preselectedName;
        _state = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubRolesDirectoryUnavailable);
      });
    }
  }

  Future<void> _pickMember() async {
    final ClubMember? picked = await showCupertinoSheet<ClubMember>(
      context: context,
      showDragHandle: true,
      scrollableBuilder:
          (BuildContext context, ScrollController controller) => _memberPicker(
            controller,
          ),
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
          stringsOf(context).clubRolesSelectMember,
          style: TextStyle(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        ..._members.map(
          (ClubMember member) => ClubOpsRow(
            key: Key('roles-member-${member.memberId}'),
            title: clubMemberDisplayName(context, member),
            leading: CyAvatar(
              url: member.avatar,
              fallback: clubMemberDisplayName(context, member),
              size: 36,
            ),
            trailing: Text(
              _selectedMemberId == member.memberId ? stringsOf(context).clubRolesSelected : stringsOf(context).clubRolesSelect,
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

  Future<void> _pickRole() async {
    final RoleOption? picked = await showCupertinoSheet<RoleOption>(
      context: context,
      showDragHandle: true,
      scrollableBuilder:
          (BuildContext context, ScrollController controller) => _rolePicker(
            controller,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedRoleCode = picked.roleCode;
      _selectedRoleName = picked.name;
    });
  }

  Widget _rolePicker(ScrollController controller) {
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
          stringsOf(context).clubRolesSelectRole,
          style: TextStyle(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        ..._roles.map(
          (RoleOption role) => ClubOpsRow(
            key: Key('roles-role-${role.roleCode}'),
            title: role.name,
            meta: role.summary,
            metaLines: 2,
            trailing: Text(
              _selectedRoleCode == role.roleCode ? stringsOf(context).clubRolesSelected : stringsOf(context).clubRolesSelect,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: _selectedRoleCode == role.roleCode
                    ? palette.brand
                    : palette.textTertiary,
              ),
            ),
            onTap: () => Navigator.of(context).pop(role),
          ),
        ),
      ],
    );
  }

  Future<void> _assignRole() async {
    if (_actingKey.isNotEmpty) return;
    final int? memberId = _selectedMemberId;
    final String roleCode = _selectedRoleCode;
    if (memberId == null) {
      CyNativeNotice.show(context, stringsOf(context).clubRolesMemberRequired, isError: true);
      return;
    }
    if (roleCode.isEmpty) {
      CyNativeNotice.show(context, stringsOf(context).clubRolesRoleRequired, isError: true);
      return;
    }
    RoleOption? role;
    for (final RoleOption candidate in _roles) {
      if (candidate.roleCode == roleCode) {
        role = candidate;
        break;
      }
    }
    if (role == null || !RoleOption.allowed(roleCode, eventScoped: _activityId != null)) {
      CyNativeNotice.show(context, stringsOf(context).clubRolesInvalidScope, isError: true);
      return;
    }
    final String key = 'assign:$memberId:$roleCode';
    final String intentKey = '$key:${widget.clubId}:${_activityId ?? 'club'}';
    final String requestId =
        _requestIds[intentKey] ?? ClubOpsApi.newRequestId('club-role');
    _requestIds[intentKey] = requestId;
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .assignRole(
            clubId: widget.clubId,
            activityId: role.scopeType == 'EVENT' ? _activityId : null,
            targetMemberId: memberId,
            roleCode: roleCode,
            requestId: requestId,
          );
      if (!mounted) return;
      _requestIds.remove(intentKey);
      CyNativeNotice.show(context, stringsOf(context).clubRolesAssigned);
      setState(() => _selectedRoleCode = '');
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      if (error is! ClubOpsConflictException && _isClientFailure(error)) {
        _requestIds.remove(intentKey);
      }
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubRolesAssignFailed),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  bool _isClientFailure(Object error) {
    return error is ClubOpsConflictException ||
        error is ClubOpsRejectedException;
  }

  Future<void> _revokeRole(RoleAssignment assignment) async {
    if (_actingKey.isNotEmpty) return;
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).clubRolesRevokeTitle(assignment.memberName, assignment.roleName),
      content: stringsOf(context).clubRolesRevokeBody,
      confirmText: stringsOf(context).clubRolesRevokeAction,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final String key = 'revoke:${assignment.id}';
    final String intentKey = '$key:${widget.clubId}:${assignment.version}';
    final String requestId =
        _requestIds[intentKey] ?? ClubOpsApi.newRequestId('club-role');
    _requestIds[intentKey] = requestId;
    setState(() => _actingKey = key);
    try {
      await ref
          .read(clubOpsApiProvider)
          .revokeRole(
            clubId: widget.clubId,
            activityId: assignment.scopeType == 'EVENT'
                ? assignment.scopeId
                : null,
            assignmentId: assignment.id,
            version: assignment.version,
            reason: '主理人在角色管理页撤销',
            requestId: requestId,
          );
      if (!mounted) return;
      _requestIds.remove(intentKey);
      CyNativeNotice.show(context, stringsOf(context).clubRolesRevoked);
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      if (_isClientFailure(error)) _requestIds.remove(intentKey);
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubRolesRevokeFailed),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingKey = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubRolesTitle),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 游客先登录:401 说成「你没有管理角色的权限」会让人去查自己的角色,
    // 而真因只是没登录 —— 登录后原地重取,人留在这一页。
    if (_loginRequired) {
      return ClubLoginGate(
        message: stringsOf(context).clubRolesLogin,
        onSignedIn: _load,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).clubRolesDenied,
          sub: _error.isEmpty
              ? stringsOf(context).clubRolesDeniedHelp
              : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).clubRolesNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: stringsOf(context).clubRolesUnavailable,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.ready:
        if (_members.isEmpty) {
          return StatusView(
            message: stringsOf(context).clubRolesEmpty,
            sub: stringsOf(context).clubRolesEmptyBody,
            icon: Icons.group_add_outlined,
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
        ClubOpsSection(
          title: stringsOf(context).clubRolesCurrent,
          children: <Widget>[
            ClubOpsCard(
              children: <Widget>[
                ClubOpsRow(
                  title: _ownerName.isEmpty ? stringsOf(context).clubRolesOwner : _ownerName,
                  meta: stringsOf(context).clubRolesOwnerAccess,
                  value: stringsOf(context).clubRolesOwner,
                  valueColor: palette.textPrimary,
                ),
                ..._assignments.map(
                  (RoleAssignment item) => ClubOpsRow(
                    key: Key('roles-assignment-${item.id}'),
                    title: item.memberName,
                    meta: item.roleSummary,
                    metaLines: 2,
                    value: item.roleName,
                    valueColor: palette.textPrimary,
                    trailing: ClubOpsRowLink(
                      key: Key('roles-revoke-${item.id}'),
                      label: stringsOf(context).clubRolesRevoke,
                      enabled: _actingKey.isEmpty,
                      onTap: () => _revokeRole(item),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ClubOpsSection(
          title: stringsOf(context).clubRolesFixed,
          caption: stringsOf(context).clubRolesFixedBody,
          children: <Widget>[
            ClubOpsCard(
              children: <Widget>[
                CyCell(
                  key: const Key('roles-pick-member'),
                  title: stringsOf(context).clubRolesSelectMember,
                  trailing: Text(
                    _selectedMemberName.isEmpty ? stringsOf(context).clubRolesUnselected : _selectedMemberName,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: palette.textTertiary,
                    ),
                  ),
                  onTap: _pickMember,
                ),
                CyCell(
                  key: const Key('roles-pick-role'),
                  title: stringsOf(context).clubRolesRole,
                  trailing: Text(
                    _selectedRoleName.isEmpty ? stringsOf(context).clubRolesUnselected : _selectedRoleName,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: palette.textTertiary,
                    ),
                  ),
                  onTap: _pickRole,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: CyNativeButton(
                key: const Key('roles-assign'),
                label: stringsOf(context).clubRolesAssign,
                width: double.infinity,
                onPressed:
                    (_selectedMemberId == null ||
                        _selectedRoleCode.isEmpty ||
                        _actingKey.isNotEmpty)
                    ? null
                    : _assignRole,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            0,
          ),
          child: Text(
            stringsOf(context).clubRolesRevokeExplanation,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              height: 1.5,
              color: palette.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
