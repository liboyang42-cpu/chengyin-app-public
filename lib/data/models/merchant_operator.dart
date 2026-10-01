enum MerchantOperatorRole {
  manager('MERCHANT_MANAGER', '店长'),
  checkin('MERCHANT_CHECKIN', '核销员'),
  marketing('MERCHANT_MARKETING', '运营'),
  finance('MERCHANT_FINANCE', '财务');

  const MerchantOperatorRole(this.wire, this.label);

  final String wire;
  final String label;

  static MerchantOperatorRole parse(Object? value) => values.firstWhere(
    (MerchantOperatorRole role) => role.wire == value,
    orElse: () => throw const FormatException('未知的员工岗位'),
  );
}

enum MerchantOperatorStatus {
  active('ACTIVE'),
  revoked('REVOKED');

  const MerchantOperatorStatus(this.wire);
  final String wire;

  static MerchantOperatorStatus parse(Object? value) => values.firstWhere(
    (MerchantOperatorStatus status) => status.wire == value,
    orElse: () => throw const FormatException('未知的员工状态'),
  );
}

enum MerchantInviteStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  expired('EXPIRED'),
  revoked('REVOKED');

  const MerchantInviteStatus(this.wire);
  final String wire;

  static MerchantInviteStatus parse(Object? value) => values.firstWhere(
    (MerchantInviteStatus status) => status.wire == value,
    orElse: () => throw const FormatException('未知的邀请状态'),
  );
}

enum MerchantMutationState {
  exactResult('EXACT_RESULT'),
  laterAuthoritative('LATER_AUTHORITATIVE');

  const MerchantMutationState(this.wire);
  final String wire;

  static MerchantMutationState parse(Object? value) => values.firstWhere(
    (MerchantMutationState state) => state.wire == value,
    orElse: () => throw const FormatException('员工操作回执状态无效'),
  );
}

class MerchantOperatorAccess {
  const MerchantOperatorAccess({
    required this.active,
    required this.merchantId,
    required this.merchantName,
    this.hasMerchantNameFallback = false,
    required this.merchantLogo,
    required this.roleCode,
    required this.permissions,
    required this.canManageOperators,
  });

  factory MerchantOperatorAccess.fromJson(Map<String, dynamic> json) {
    final bool active = _requiredBool(json['active'], '经营身份状态');
    final Set<String> permissions = _stringSet(json['permissions'], '岗位权限');
    if (!active) {
      if (json['merchant'] != null || json['roleCode'] != null) {
        throw const FormatException('未激活经营身份不应携带门店信息');
      }
      return MerchantOperatorAccess(
        active: false,
        merchantId: null,
        merchantName: null,
        merchantLogo: null,
        roleCode: null,
        permissions: permissions,
        canManageOperators: false,
      );
    }
    final Map<String, dynamic> merchant = _object(json['merchant'], '门店信息');
    final String roleCode = _requiredText(json['roleCode'], '当前岗位');
    final bool canManage = _requiredBool(json['canManageOperators'], '员工管理权限');
    if (canManage != permissions.contains('merchant:operator:manage')) {
      throw const FormatException('员工管理权限回执不一致');
    }
    return MerchantOperatorAccess(
      active: true,
      merchantId: _positiveInt(merchant['id'], '门店 ID'),
      merchantName: _optionalText(merchant['name']) ?? '门店',
      hasMerchantNameFallback: _optionalText(merchant['name']) == null,
      merchantLogo: _optionalText(merchant['logo']),
      roleCode: roleCode,
      permissions: permissions,
      canManageOperators: canManage,
    );
  }

  /// True only when parsing supplied a local placeholder.
  final bool hasMerchantNameFallback;

  final bool active;
  final int? merchantId;
  final String? merchantName;
  final String? merchantLogo;
  final String? roleCode;
  final Set<String> permissions;
  final bool canManageOperators;

  String get roleLabel => switch (roleCode) {
    'MERCHANT_OWNER' => '店主',
    'MERCHANT_MANAGER' => '店长',
    'MERCHANT_CHECKIN' => '核销员',
    'MERCHANT_MARKETING' => '运营',
    'MERCHANT_FINANCE' => '财务',
    _ => '未知岗位',
  };
}

class MerchantAssignableRole {
  const MerchantAssignableRole({
    required this.role,
    required this.name,
    this.hasNameFallback = false,
    required this.permissions,
  });

  factory MerchantAssignableRole.fromJson(Map<String, dynamic> json) {
    final MerchantOperatorRole role = MerchantOperatorRole.parse(
      json['roleCode'],
    );
    return MerchantAssignableRole(
      role: role,
      name: _optionalText(json['name']) ?? role.label,
      hasNameFallback: _optionalText(json['name']) == null,
      permissions: _stringSet(json['permissions'], '岗位权限'),
    );
  }

  final MerchantOperatorRole role;
  /// True only when parsing supplied a local placeholder.
  final bool hasNameFallback;

  final String name;
  final Set<String> permissions;

  String get permissionText {
    final List<String> labels = <String>[];
    if (permissions.contains('merchant:project:manage')) labels.add('项目');
    if (permissions.contains('merchant:verify')) labels.add('核销');
    if (permissions.contains('merchant:crm:read')) labels.add('客户');
    if (permissions.contains('merchant:marketing:write')) labels.add('营销');
    if (permissions.contains('merchant:finance:read')) labels.add('财务');
    return labels.isEmpty ? '基础经营信息' : labels.join('、');
  }
}

class MerchantOperator {
  const MerchantOperator({
    required this.id,
    required this.nickname,
    this.hasNicknameFallback = false,
    required this.avatar,
    required this.role,
    required this.status,
    required this.acceptedAt,
    required this.version,
  });

  factory MerchantOperator.fromJson(Map<String, dynamic> json) =>
      MerchantOperator(
        id: _positiveInt(json['id'], '员工 ID'),
        nickname: _optionalText(json['nickname']) ?? '未设置昵称',
        hasNicknameFallback: _optionalText(json['nickname']) == null,
        avatar: _optionalText(json['avatar']),
        role: MerchantOperatorRole.parse(json['roleCode']),
        status: MerchantOperatorStatus.parse(json['status']),
        acceptedAt: _requiredDate(json['acceptedAt'], '加入时间'),
        version: _version(json['version']),
      );

  /// True only when parsing supplied a local placeholder.
  final bool hasNicknameFallback;

  final int id;
  final String nickname;
  final String? avatar;
  final MerchantOperatorRole role;
  final MerchantOperatorStatus status;
  final DateTime acceptedAt;
  final int version;
}

class MerchantOperatorInvite {
  const MerchantOperatorInvite({
    required this.id,
    required this.role,
    required this.status,
    required this.expiresAt,
    required this.version,
  });

  factory MerchantOperatorInvite.fromJson(Map<String, dynamic> json) =>
      MerchantOperatorInvite(
        id: _positiveInt(json['id'], '邀请 ID'),
        role: MerchantOperatorRole.parse(json['roleCode']),
        status: MerchantInviteStatus.parse(json['status']),
        expiresAt: _requiredDate(json['expiresAt'], '邀请失效时间'),
        version: _version(json['version']),
      );

  final int id;
  final MerchantOperatorRole role;
  final MerchantInviteStatus status;
  final DateTime expiresAt;
  final int version;
}

class MerchantTeam {
  const MerchantTeam({required this.operators, required this.invites});

  factory MerchantTeam.fromJson(Map<String, dynamic> json) {
    final List<dynamic> operators = _list(json['operators'], '团队成员');
    final List<dynamic> invites = _list(json['invites'], '团队邀请');
    return MerchantTeam(
      operators: operators
          .map(
            (Object? value) => MerchantOperator.fromJson(_object(value, '员工')),
          )
          .toList(growable: false),
      invites: invites
          .map(
            (Object? value) =>
                MerchantOperatorInvite.fromJson(_object(value, '邀请')),
          )
          .toList(growable: false),
    );
  }

  final List<MerchantOperator> operators;
  final List<MerchantOperatorInvite> invites;

  List<MerchantOperator> get activeOperators => operators
      .where(
        (MerchantOperator row) => row.status == MerchantOperatorStatus.active,
      )
      .toList(growable: false);
  List<MerchantOperatorInvite> get pendingInvites => invites
      .where(
        (MerchantOperatorInvite row) =>
            row.status == MerchantInviteStatus.pending,
      )
      .toList(growable: false);
}

class MerchantInviteCreation {
  const MerchantInviteCreation({required this.invite, required this.token});

  factory MerchantInviteCreation.fromJson(Map<String, dynamic> json) {
    final String token = _requiredText(json['token'], '邀请凭证');
    if (token.length < 16 || token.length > 256) {
      throw const FormatException('邀请凭证回执无效');
    }
    return MerchantInviteCreation(
      invite: MerchantOperatorInvite.fromJson(_object(json['invite'], '邀请')),
      token: token,
    );
  }

  final MerchantOperatorInvite invite;
  final String token;
}

class MerchantOperatorReceipt {
  const MerchantOperatorReceipt({
    required this.operator,
    required this.mutationState,
  });

  factory MerchantOperatorReceipt.fromJson(
    Map<String, dynamic> json, {
    required int expectedId,
    required int minimumVersion,
    MerchantOperatorStatus? expectedStatus,
    MerchantOperatorRole? expectedRole,
  }) {
    final MerchantOperator operator = MerchantOperator.fromJson(json);
    final MerchantMutationState mutationState = MerchantMutationState.parse(
      json['mutationState'],
    );
    if (operator.id != expectedId || operator.version < minimumVersion) {
      throw const FormatException('员工操作回执与目标不匹配');
    }
    if (expectedStatus != null && operator.status != expectedStatus) {
      throw const FormatException('员工操作回执状态不匹配');
    }
    if (expectedRole != null && operator.role != expectedRole) {
      throw const FormatException('员工操作回执岗位不匹配');
    }
    return MerchantOperatorReceipt(
      operator: operator,
      mutationState: mutationState,
    );
  }

  final MerchantOperator operator;
  final MerchantMutationState mutationState;
}

class MerchantInviteReceipt {
  const MerchantInviteReceipt({
    required this.invite,
    required this.mutationState,
  });

  factory MerchantInviteReceipt.fromJson(
    Map<String, dynamic> json, {
    required int expectedId,
    required int minimumVersion,
    required MerchantInviteStatus expectedStatus,
  }) {
    final MerchantOperatorInvite invite = MerchantOperatorInvite.fromJson(json);
    final MerchantMutationState state = MerchantMutationState.parse(
      json['mutationState'],
    );
    if (invite.id != expectedId ||
        invite.version < minimumVersion ||
        invite.status != expectedStatus) {
      throw const FormatException('邀请操作回执与目标不匹配');
    }
    return MerchantInviteReceipt(invite: invite, mutationState: state);
  }

  final MerchantOperatorInvite invite;
  final MerchantMutationState mutationState;
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field回执缺失');
}

List<dynamic> _list(Object? value, String field) {
  if (value is List<dynamic>) return value;
  throw FormatException('$field回执缺失');
}

Set<String> _stringSet(Object? value, String field) {
  final List<dynamic> list = _list(value, field);
  final Set<String> result = <String>{};
  for (final Object? item in list) {
    if (item is! String || item.trim().isEmpty) {
      throw FormatException('$field回执无效');
    }
    result.add(item.trim());
  }
  if (result.length != list.length) throw FormatException('$field回执重复');
  return Set<String>.unmodifiable(result);
}

bool _requiredBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('$field回执无效');
}

int _positiveInt(Object? value, String field) {
  final int? parsed = switch (value) {
    final int number => number,
    final num number when number == number.roundToDouble() => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
  if (parsed == null || parsed <= 0) throw FormatException('$field回执无效');
  return parsed;
}

int _version(Object? value) {
  final int? parsed = switch (value) {
    final int number => number,
    final num number when number == number.roundToDouble() => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
  if (parsed == null || parsed < 0) throw const FormatException('版本回执无效');
  return parsed;
}

String _requiredText(Object? value, String field) {
  final String? text = _optionalText(value);
  if (text == null) throw FormatException('$field回执无效');
  return text;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('文本回执无效');
  final String text = value.trim();
  return text.isEmpty ? null : text;
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String && value is! num) throw FormatException('$field回执无效');
  final DateTime? parsed = DateTime.tryParse(
    value.toString().replaceFirst(' ', 'T'),
  );
  if (parsed == null) throw FormatException('$field回执无效');
  return parsed;
}
