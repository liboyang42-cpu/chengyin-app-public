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
  String _ownerName = '主理人';
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
          _error = '角色权限暂时不可用';
        });
        return;
      }
      if (!access.active || !access.canManageRoles) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = '仅俱乐部主理人可管理角色';
        });
        return;
      }
      if (access.clubId != widget.clubId) {
        setState(() {
          _state = ClubOpsLoadState.error;
          _error = '角色权限暂时不可用';
        });
        return;
      }
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, '角色权限暂时不可用');
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
          _error = '角色目录暂时不可用';
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
          .map((ClubMember m) => m.displayName)
          .followedBy(<String>['主理人'])
          .first;
      final int? requested = widget.memberId;
      final int? preselected =
          requested != null &&
              selectable.any((ClubMember m) => m.memberId == requested)
          ? requested
          : null;
      final String preselectedName = preselected == null
          ? ''
          : selectable
                .firstWhere((ClubMember m) => m.memberId == preselected)
                .displayName;
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
        _error = clubOpsErrorMessage(error, '角色目录暂时不可用');
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
            key: Key('roles-member-${member.memberId}'),
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
          '选择角色',
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
              _selectedRoleCode == role.roleCode ? '已选' : '选择',
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
      CyNativeNotice.show(context, '先选择一位成员', isError: true);
      return;
    }
    if (roleCode.isEmpty) {
      CyNativeNotice.show(context, '先选择一个角色', isError: true);
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
      CyNativeNotice.show(context, '该角色不适用于当前范围', isError: true);
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
      CyNativeNotice.show(context, '角色已分配');
      setState(() => _selectedRoleCode = '');
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      if (error is! ClubOpsConflictException && _isClientFailure(error)) {
        _requestIds.remove(intentKey);
      }
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '分配失败'),
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
      title: '撤销 ${assignment.memberName} 的「${assignment.roleName}」？',
      content: '撤销后该成员立即失去对应入口。此操作不可撤销。',
      confirmText: '撤销角色',
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
      CyNativeNotice.show(context, '角色已撤销');
      await _loadManagement();
    } catch (error) {
      if (!mounted) return;
      if (_isClientFailure(error)) _requestIds.remove(intentKey);
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '撤销失败'),
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
              const CyPageTitle('角色与权限'),
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
        message: '登录后查看角色与权限',
        onSignedIn: _load,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: '你没有管理角色的权限',
          sub: _error.isEmpty
              ? '只有主理人可以分配角色。想帮忙管角色,让主理人先把你提为主理人。'
              : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: '网络连接失败',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: '角色管理暂时不可用',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.ready:
        if (_members.isEmpty) {
          return const StatusView(
            message: '还没有可委派的成员',
            sub: '先邀请成员加入俱乐部，再为他们分配运营角色。',
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
          title: '当前委派',
          children: <Widget>[
            ClubOpsCard(
              children: <Widget>[
                ClubOpsRow(
                  title: _ownerName,
                  meta: '全部权限，不可撤销',
                  value: '主理人',
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
                      label: '撤销',
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
          title: '分配固定角色',
          caption: '选择成员后，从下方分配一个固定角色',
          children: <Widget>[
            ClubOpsCard(
              children: <Widget>[
                CyCell(
                  key: const Key('roles-pick-member'),
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
                  key: const Key('roles-pick-role'),
                  title: '角色',
                  trailing: Text(
                    _selectedRoleName.isEmpty ? '未选择' : _selectedRoleName,
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
                label: '分配',
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
            '撤销角色要二次确认；撤销后该成员立即失去对应入口。',
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
