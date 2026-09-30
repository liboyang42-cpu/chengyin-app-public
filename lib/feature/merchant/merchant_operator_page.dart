import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_operator_api.dart';
import '../../data/models/merchant_operator.dart';

typedef MerchantInviteShare =
    Future<void> Function(MerchantInviteCreation invite);

Uri merchantOperatorInviteAppLink(String token) {
  final String normalized = token.trim();
  if (normalized.length < 16 || normalized.length > 256) {
    throw ArgumentError.value(token, 'token', '邀请凭证无效');
  }
  return Uri.https(
    'api.example.invalid',
    '/app/merchant/team',
    <String, String>{'invite': normalized},
  );
}

class MerchantOperatorPage extends StatefulWidget {
  const MerchantOperatorPage({
    super.key,
    required this.api,
    this.incomingInviteToken,
    this.onShareInvite,
    this.onOpenWorkbench,
    this.intentStore,
  });

  final MerchantOperatorGateway api;
  final String? incomingInviteToken;
  final MerchantInviteShare? onShareInvite;
  final VoidCallback? onOpenWorkbench;
  final MerchantOperatorIntentStore? intentStore;

  @override
  State<MerchantOperatorPage> createState() => _MerchantOperatorPageState();
}

enum _OperatorPageState { loading, ready, noIdentity, error }

class _MerchantOperatorPageState extends State<MerchantOperatorPage> {
  _OperatorPageState _state = _OperatorPageState.loading;
  MerchantOperatorAccess? _access;
  MerchantTeam? _team;
  List<MerchantAssignableRole> _roles = const <MerchantAssignableRole>[];
  MerchantInviteCreation? _createdInvite;
  Object? _error;
  Object? _rolesError;
  bool _submitting = false;
  bool _incomingInviteConsumed = false;
  int _loadToken = 0;
  int _requestSequence = 0;
  final math.Random _random = math.Random();
  final Map<String, String> _requestIds = <String, String>{};
  late final MerchantOperatorIntentStore _intentStore;

  @override
  void initState() {
    super.initState();
    _intentStore =
        widget.intentStore ??
        SecureMerchantOperatorIntentStore(const FlutterSecureStorage());
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _loadToken += 1;
    super.dispose();
  }

  Future<void> _load() async {
    final int token = ++_loadToken;
    setState(() {
      _state = _OperatorPageState.loading;
      _error = null;
    });
    try {
      final MerchantOperatorAccess access = await widget.api.access();
      if (!mounted || token != _loadToken) return;
      if (!access.active) {
        setState(() {
          _access = access;
          _team = null;
          _roles = const <MerchantAssignableRole>[];
          _state = _OperatorPageState.noIdentity;
        });
        return;
      }
      if (!access.canManageOperators) {
        setState(() {
          _access = access;
          _team = null;
          _roles = const <MerchantAssignableRole>[];
          _state = _OperatorPageState.ready;
        });
        return;
      }
      final Future<({List<MerchantAssignableRole> roles, Object? error})>
      rolesFuture = _loadRolesSafely();
      final MerchantTeam team = await widget.api.team();
      final ({List<MerchantAssignableRole> roles, Object? error}) roleResult =
          await rolesFuture;
      if (!mounted || token != _loadToken) return;
      setState(() {
        _access = access;
        _roles = roleResult.roles;
        _rolesError = roleResult.error;
        _team = team;
        _state = _OperatorPageState.ready;
      });
    } on Object catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = error;
        _state = _OperatorPageState.error;
      });
    }
  }

  Future<void> _reloadTeam() async {
    final MerchantTeam team = await widget.api.team();
    if (mounted) setState(() => _team = team);
  }

  Future<({List<MerchantAssignableRole> roles, Object? error})>
  _loadRolesSafely() async {
    try {
      return (roles: await widget.api.roles(), error: null);
    } on Object catch (error) {
      return (roles: const <MerchantAssignableRole>[], error: error);
    }
  }

  Future<void> _reloadRoles() async {
    final ({List<MerchantAssignableRole> roles, Object? error}) result =
        await _loadRolesSafely();
    if (!mounted) return;
    setState(() {
      _roles = result.roles;
      _rolesError = result.error;
    });
  }

  Future<String> _requestId(String fingerprint, String prefix) async {
    final String? current = _requestIds[fingerprint];
    if (current != null) return current;
    try {
      final String? persisted = await _intentStore.read(fingerprint);
      if (persisted != null) {
        _requestIds[fingerprint] = persisted;
        return persisted;
      }
    } on Object {
      // Recovery storage failure must not block the operation in this session.
    }
    _requestSequence += 1;
    final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
      36,
    );
    final String entropy = _random
        .nextInt(0xFFFFFF)
        .toRadixString(36)
        .padLeft(5, '0');
    final String requestId = '$prefix:$stamp:$entropy:$_requestSequence';
    _requestIds[fingerprint] = requestId;
    try {
      await _intentStore.write(fingerprint, requestId);
    } on Object {
      // The in-memory request id remains authoritative for this page instance.
    }
    return requestId;
  }

  Future<void> _clearIntent(String fingerprint) async {
    _requestIds.remove(fingerprint);
    try {
      await _intentStore.delete(fingerprint);
    } on Object {
      // A confirmed receipt is authoritative even if local cleanup fails.
    }
  }

  Future<void> _clearIntentOnClientError(
    String fingerprint,
    Object error,
  ) async {
    if (error is MerchantOperatorApiException && error.isClientError) {
      await _clearIntent(fingerprint);
    }
  }

  Future<void> _refreshTeamAfterConfirmedWrite(String successMessage) async {
    CyNativeNotice.show(context, successMessage);
    try {
      await _reloadTeam();
    } on Object {
      if (mounted) {
        CyNativeNotice.show(
          context,
          '$successMessage，但团队名单刷新失败，请稍后重试',
          isError: true,
        );
      }
    }
  }

  void _applyOperatorReceipt(MerchantOperator operator) {
    final MerchantTeam? current = _team;
    if (current == null) return;
    final List<MerchantOperator> operators = current.operators
        .where((MerchantOperator row) => row.id != operator.id)
        .toList();
    if (operator.status == MerchantOperatorStatus.active) {
      operators.add(operator);
    }
    setState(
      () =>
          _team = MerchantTeam(operators: operators, invites: current.invites),
    );
  }

  void _applyInvite(MerchantOperatorInvite invite) {
    final MerchantTeam? current = _team;
    if (current == null) return;
    final List<MerchantOperatorInvite> invites = current.invites
        .where((MerchantOperatorInvite row) => row.id != invite.id)
        .toList();
    if (invite.status == MerchantInviteStatus.pending) invites.add(invite);
    setState(
      () =>
          _team = MerchantTeam(operators: current.operators, invites: invites),
    );
  }

  Future<MerchantOperatorRole?> _pickRole({
    required String title,
    MerchantOperatorRole? current,
  }) => showCupertinoModalPopup<MerchantOperatorRole>(
    context: context,
    builder: (BuildContext context) => CupertinoActionSheet(
      title: Text(title),
      message: const Text('岗位决定员工能看到和能操作的经营范围'),
      actions: _roles
          .map(
            (MerchantAssignableRole role) => CupertinoActionSheetAction(
              isDefaultAction: current == role.role,
              onPressed: () => Navigator.of(context).pop(role.role),
              child: Column(
                children: <Widget>[
                  Text(role.name),
                  const SizedBox(height: 3),
                  Text(
                    role.permissionText,
                    style: CyType.caption1.copyWith(
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ),
  );

  Future<void> _createInvite() async {
    if (_submitting || _roles.isEmpty) return;
    final MerchantOperatorRole? role = await _pickRole(title: '选择邀请岗位');
    if (role == null || !mounted) return;
    final String fingerprint = 'invite:${_access?.merchantId}:${role.wire}';
    setState(() => _submitting = true);
    try {
      final MerchantInviteCreation creation = await widget.api.invite(
        role: role,
        requestId: await _requestId(fingerprint, 'merchant-invite'),
      );
      if (!mounted) return;
      await _clearIntent(fingerprint);
      setState(() => _createdInvite = creation);
      _applyInvite(creation.invite);
      await _refreshTeamAfterConfirmedWrite('邀请已创建');
    } on Object catch (error) {
      await _clearIntentOnClientError(fingerprint, error);
      if (mounted) CyNativeNotice.show(context, _message(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _shareInvite() async {
    final MerchantInviteCreation? creation = _createdInvite;
    if (creation == null) return;
    final MerchantInviteShare? callback = widget.onShareInvite;
    if (callback != null) {
      await callback(creation);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        text:
            '邀请你加入${_access?.merchantName ?? '门店'}经营团队\n'
            '${merchantOperatorInviteAppLink(creation.token)}',
      ),
    );
  }

  Future<void> _updateRole(MerchantOperator operator) async {
    if (_submitting) return;
    final MerchantOperatorRole? role = await _pickRole(
      title: '调整岗位',
      current: operator.role,
    );
    if (role == null || role == operator.role || !mounted) return;
    final String fingerprint =
        'role:${operator.id}:${operator.version}:${role.wire}';
    setState(() => _submitting = true);
    try {
      final MerchantOperatorReceipt receipt = await widget.api.updateRole(
        operator: operator,
        role: role,
        requestId: await _requestId(fingerprint, 'merchant-role'),
      );
      if (!mounted) return;
      await _clearIntent(fingerprint);
      _applyOperatorReceipt(receipt.operator);
      await _refreshTeamAfterConfirmedWrite(
        receipt.mutationState == MerchantMutationState.exactResult
            ? '岗位已更新'
            : '岗位后续已变化',
      );
    } on Object catch (error) {
      await _clearIntentOnClientError(fingerprint, error);
      if (mounted) CyNativeNotice.show(context, _message(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 确认弹窗走共用件(S1):iOS 26+ 由系统 Liquid Glass alert 呈现,
  /// 旧系统/插件缺失回退 CupertinoAlertDialog。文案与 destructive 语义不变。
  Future<bool> _confirm(String title, String content) => cyConfirm(
    context,
    title: title,
    content: content,
    confirmText: '确认',
    danger: true,
  );

  Future<void> _remove(MerchantOperator operator) async {
    final bool confirmed = await _confirm(
      '移除团队成员？',
      '移除后，${operator.nickname} 的商家权限会立即失效。',
    );
    if (!confirmed || !mounted || _submitting) return;
    const String reason = '店主在经营团队页移除成员';
    final String fingerprint = 'remove:${operator.id}:${operator.version}';
    setState(() => _submitting = true);
    try {
      final MerchantOperatorReceipt receipt = await widget.api.remove(
        operator: operator,
        reason: reason,
        requestId: await _requestId(fingerprint, 'merchant-remove'),
      );
      if (!mounted) return;
      await _clearIntent(fingerprint);
      _applyOperatorReceipt(receipt.operator);
      await _refreshTeamAfterConfirmedWrite('成员已移除');
    } on Object catch (error) {
      await _clearIntentOnClientError(fingerprint, error);
      if (mounted) CyNativeNotice.show(context, _message(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _revoke(MerchantOperatorInvite invite) async {
    final bool confirmed = await _confirm('撤销这条邀请？', '撤销后，已经发出的邀请凭证会立即失效。');
    if (!confirmed || !mounted || _submitting) return;
    const String reason = '店主在经营团队页撤销邀请';
    final String fingerprint = 'revoke:${invite.id}:${invite.version}';
    setState(() => _submitting = true);
    try {
      final MerchantInviteReceipt receipt = await widget.api.revokeInvite(
        invite: invite,
        reason: reason,
        requestId: await _requestId(fingerprint, 'merchant-revoke-invite'),
      );
      if (!mounted) return;
      await _clearIntent(fingerprint);
      if (_createdInvite?.invite.id == invite.id) _createdInvite = null;
      _applyInvite(receipt.invite);
      await _refreshTeamAfterConfirmedWrite('邀请已撤销');
    } on Object catch (error) {
      await _clearIntentOnClientError(fingerprint, error);
      if (mounted) CyNativeNotice.show(context, _message(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptIncomingInvite() async {
    final String token = _incomingInviteToken;
    if (_submitting || token.isEmpty) return;
    final String fingerprint = 'accept:$token';
    setState(() => _submitting = true);
    try {
      await widget.api.acceptInvite(
        token: token,
        requestId: await _requestId(fingerprint, 'merchant-accept'),
      );
      if (!mounted) return;
      await _clearIntent(fingerprint);
      if (!mounted) return;
      _incomingInviteConsumed = true;
      CyNativeNotice.show(context, '已加入团队');
      await _load();
    } on Object catch (error) {
      await _clearIntentOnClientError(fingerprint, error);
      if (error is MerchantOperatorApiException && error.isClientError) {
        _incomingInviteConsumed = true;
      }
      if (mounted) CyNativeNotice.show(context, _message(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _message(Object error) =>
      error is MerchantOperatorApiException ? error.message : '网络连接失败，请稍后重试';

  String get _incomingInviteToken =>
      _incomingInviteConsumed ? '' : (widget.incomingInviteToken?.trim() ?? '');

  void _openWorkbench() {
    final VoidCallback? callback = widget.onOpenWorkbench;
    if (callback != null) {
      callback();
      return;
    }
    context.go(kMerchantHomeRoute);
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('经营团队')),
    child: SafeArea(top: false, child: _body()),
  );

  Widget _body() => switch (_state) {
    _OperatorPageState.loading => const Center(
      child: CupertinoActivityIndicator(radius: 14),
    ),
    _OperatorPageState.error => StatusView(
      icon: CupertinoIcons.exclamationmark_triangle,
      message: '经营团队没能加载出来',
      sub: _message(_error ?? const MerchantOperatorApiException('加载失败')),
      large: true,
      onRetry: _load,
      retryLabel: '重新加载',
    ),
    _OperatorPageState.noIdentity => _noIdentity(),
    _OperatorPageState.ready => _content(),
  };

  Widget _noIdentity() {
    final bool hasInvite = _incomingInviteToken.isNotEmpty;
    return StatusView(
      icon: hasInvite ? CupertinoIcons.person_add : CupertinoIcons.person_2,
      message: hasInvite ? '加入经营团队' : '还没有经营团队身份',
      sub: hasInvite
          ? '接受后会获得店主分配的固定岗位；每个账号同一时间只能加入一个商家团队。'
          : '请让店主从经营团队页向你发出邀请',
      large: true,
      onRetry: hasInvite ? _acceptIncomingInvite : null,
      retryLabel: '接受邀请',
    );
  }

  Widget _content() {
    final MerchantOperatorAccess access = _access!;
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _storeHeader(access)),
        if (_incomingInviteToken.isNotEmpty)
          SliverToBoxAdapter(child: _incomingInviteBanner()),
        if (!access.canManageOperators)
          SliverToBoxAdapter(child: _selfCard(access))
        else ...<Widget>[
          if (_createdInvite != null)
            SliverToBoxAdapter(child: _createdInviteCard(_createdInvite!)),
          if (_rolesError != null) SliverToBoxAdapter(child: _rolesErrorCard()),
          SliverToBoxAdapter(child: _teamSection()),
          if ((_team?.pendingInvites.length ?? 0) > 0)
            SliverToBoxAdapter(child: _inviteSection()),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _storeHeader(MerchantOperatorAccess access) =>
      CupertinoListSection.insetGrouped(
        children: <Widget>[
          CupertinoListTile(
            leading: _networkAvatar(
              access.merchantLogo,
              fallback: CupertinoIcons.building_2_fill,
            ),
            title: Text(access.merchantName ?? '门店'),
            subtitle: Text('当前岗位 · ${access.roleLabel}'),
          ),
          CupertinoListTile(
            title: Text(
              access.canManageOperators
                  ? '岗位决定员工能看到和能操作的经营范围；离职后权限立即失效。'
                  : '你的工作台入口会按当前岗位自动收起；需要调整时请联系店主。',
              style: CyType.footnote.copyWith(
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ),
        ],
      );

  Widget _incomingInviteBanner() => CupertinoListSection.insetGrouped(
    children: <Widget>[
      CupertinoListTile(
        leading: const Icon(CupertinoIcons.person_add),
        title: const Text('你还有一条团队邀请'),
        subtitle: const Text('接受前会再次校验门店、岗位与账号状态'),
        trailing: CupertinoButton(
          onPressed: _submitting ? null : _acceptIncomingInvite,
          child: const Text('接受'),
        ),
      ),
    ],
  );

  Widget _rolesErrorCard() => CupertinoListSection.insetGrouped(
    children: <Widget>[
      CupertinoListTile(
        leading: const Icon(CupertinoIcons.exclamationmark_triangle),
        title: const Text('岗位列表暂未更新'),
        subtitle: Text(_message(_rolesError!)),
        trailing: CupertinoButton(
          onPressed: _reloadRoles,
          child: const Text('重试'),
        ),
      ),
    ],
  );

  Widget _selfCard(MerchantOperatorAccess access) =>
      CupertinoListSection.insetGrouped(
        header: const Text('你的岗位权限'),
        footer: const Text('岗位调整或离职由店主操作，并在下一次请求时立即生效。'),
        children: <Widget>[
          CupertinoListTile(
            title: Text(
              access.roleLabel,
              style: CyType.title2.copyWith(fontWeight: FontWeight.w600),
            ),
            trailing: CupertinoButton(
              onPressed: _openWorkbench,
              child: const Text('进入工作台'),
            ),
          ),
        ],
      );

  Widget _createdInviteCard(MerchantInviteCreation creation) =>
      CupertinoListSection.insetGrouped(
        children: <Widget>[
          CupertinoListTile(
            title: Text('${creation.invite.role.label}邀请已创建'),
            subtitle: Text(
              '${_date(creation.invite.expiresAt)} 前有效；分享凭证只在本次页面停留期间可用。',
            ),
            trailing: CupertinoButton.filled(
              onPressed: _shareInvite,
              sizeStyle: CupertinoButtonSize.small,
              child: const Text('立即分享'),
            ),
          ),
        ],
      );

  Widget _teamSection() {
    final List<MerchantOperator> operators =
        _team?.activeOperators ?? const <MerchantOperator>[];
    return CupertinoListSection.insetGrouped(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('团队成员'),
              const SizedBox(width: 6),
              Text('${operators.length} 人'),
            ],
          ),
          CupertinoButton(
            onPressed: _submitting || _roles.isEmpty ? null : _createInvite,
            padding: EdgeInsets.zero,
            child: const Text('邀请员工'),
          ),
        ],
      ),
      footer: operators.isEmpty
          ? const Text('还没有员工，先按岗位创建邀请，再通过微信发给员工。')
          : null,
      children: operators
          .map(
            (MerchantOperator operator) => CupertinoListTile(
              leading: _networkAvatar(
                operator.avatar,
                fallback: CupertinoIcons.person_crop_circle,
              ),
              title: Text(operator.nickname),
              subtitle: Text(
                '${operator.role.label} · ${_date(operator.acceptedAt)} 加入',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CupertinoButton(
                    key: Key('operator-role-${operator.id}'),
                    onPressed: _submitting ? null : () => _updateRole(operator),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const Text('改岗'),
                  ),
                  CupertinoButton(
                    key: Key('operator-remove-${operator.id}'),
                    onPressed: _submitting ? null : () => _remove(operator),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const Text(
                      '移除',
                      style: TextStyle(color: CupertinoColors.systemRed),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _inviteSection() {
    final List<MerchantOperatorInvite> invites = _team!.pendingInvites;
    return CupertinoListSection.insetGrouped(
      header: Row(
        children: <Widget>[
          const Text('待接受邀请'),
          const SizedBox(width: 6),
          Text('${invites.length} 条'),
        ],
      ),
      children: invites
          .map(
            (MerchantOperatorInvite invite) => CupertinoListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_plus),
              title: Text('${invite.role.label}邀请'),
              subtitle: Text('${_date(invite.expiresAt)} 失效'),
              trailing: CupertinoButton(
                key: Key('operator-revoke-invite-${invite.id}'),
                onPressed: _submitting ? null : () => _revoke(invite),
                child: const Text(
                  '撤销',
                  style: TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _networkAvatar(String? rawUrl, {required IconData fallback}) {
    final Uri? uri = Uri.tryParse(rawUrl?.trim() ?? '');
    final bool valid =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final Widget fallbackWidget = Icon(fallback, size: 28);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: valid
            ? Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallbackWidget,
              )
            : Center(child: fallbackWidget),
      ),
    );
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}


/// 团队邀请是可公开打开的交接页，但查看岗位和接受邀请仍需登录。
/// 登录 sheet 就地叠加，所以当前 URI 与 invite token 不会丢失。
class MerchantTeamRoutePage extends ConsumerWidget {
  const MerchantTeamRoutePage({super.key, this.incomingInviteToken});

  final String? incomingInviteToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    if (!loggedIn) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('经营团队')),
        child: SafeArea(
          top: false,
          child: StatusView(
            icon: CupertinoIcons.person_add,
            message: '登录后处理团队邀请',
            sub: '登录后才能查看岗位或加入门店',
            large: true,
            retryLabel: '去登录',
            onRetry: () => showLoginSheet(context),
          ),
        ),
      );
    }
    final api = ref.watch(merchantOperatorApiProvider);
    return MerchantOperatorPage(
      api: api,
      incomingInviteToken: incomingInviteToken,
      onOpenWorkbench: () => context.go(kMerchantHomeRoute),
    );
  }
}
