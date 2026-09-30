/// 合作邀约表单。对齐后端 `ApiCoopController.invite`(/api/coop/invite)。
///
/// ★ 后端有**五道校验闸**(:197-215),前端能挡的先挡,别让用户填完才被拒:
///   1. inviteType 只能是 0/1        → 用枚举,压根构造不出别的值
///   2. toId + toType 必填            → 没选受邀方不给提交
///   3. topicId 必填                  → 没选主题不给提交
///   4. 不能邀请自己                  → 候选列表里过滤掉自己
///   5. 只能为自己发布的主题发起合作  → 主题列表本就只列我发布的
///   第 4、5 条**服务端仍会兜底**,前端挡只是省一次往返。
enum CoopInviteType {
  /// 邀请商家。
  merchant,

  /// 邀请俱乐部。
  club,
}

extension CoopInviteTypeX on CoopInviteType {
  /// 后端 inviteType:0 商家 / 1 俱乐部。
  int get wire => this == CoopInviteType.merchant ? 0 : 1;

  /// 后端 toType 字符串。
  String get toType => this == CoopInviteType.merchant ? 'merchant' : 'club';

  String get label => this == CoopInviteType.merchant ? '商家' : '俱乐部';
}

/// 普通合作邀约的现役报酬模式。
///
/// 后端虽然保留 `shareMode=1` 分成字段，但普通 `/api/coop/invite`
/// 会明确拒绝分成型；分成只能走官方邀约入口。因此这里不暴露一个
/// 看似可选、提交后必然被驳回的假选项。
enum CoopShareMode { traffic, fixed }

extension CoopShareModeX on CoopShareMode {
  int get wire => this == CoopShareMode.traffic ? 0 : 2;
}

/// 一个受邀对象。
class CoopInviteTarget {
  const CoopInviteTarget({required this.toId, required this.name});

  final int toId;
  final String name;
}

/// 邀约表单状态。
class CoopInviteForm {
  const CoopInviteForm({
    this.type = CoopInviteType.merchant,
    this.topicId,
    this.topicName,
    this.targets = const <CoopInviteTarget>[],
    this.message = '',
    this.shareMode = CoopShareMode.traffic,
    this.fixedFee,
    this.originApplyId,
    this.scope,
  });

  final CoopInviteType type;
  final int? topicId;
  final String? topicName;

  /// 可多选。
  final List<CoopInviteTarget> targets;
  final String message;
  final CoopShareMode shareMode;
  final double? fixedFee;

  /// 俱乐部先申请、主办方再发 type1 邀约时的可信溯源。
  final int? originApplyId;

  /// 归属标记。★ 商家**员工**代 owner 的主题发邀约时,行上带着 `MERCHANT`
  /// (来自 `/api/coop/pool/received` 的行),必须原样带进提交体 ——
  /// 小程序 `pages/coop/invite/index.js:526` 就是这句
  /// `if (data.operationScope) payload.scope = data.operationScope;`,
  /// 漏了会被判成无权处理,而报错只说"失败"。
  final String? scope;

  bool get canSubmit =>
      topicId != null &&
      targets.isNotEmpty &&
      (shareMode != CoopShareMode.fixed || (fixedFee != null && fixedFee! > 0));

  /// 不能提交时**说出缺什么** —— 不给灰按钮让用户猜。
  String? get blocker {
    if (topicId == null) return '请先选择要合作的主题';
    if (targets.isEmpty) return '请至少选择一个${type.label}';
    if (shareMode == CoopShareMode.fixed &&
        (fixedFee == null || fixedFee! <= 0)) {
      return '请填写大于 0 的固定合作费';
    }
    return null;
  }

  /// 提交体。★ 一次邀约一个对象 —— 多选时由调用方逐个提交,
  ///   因为后端 invite 接口一次只收一个 toId。
  Map<String, dynamic> toJson(CoopInviteTarget target) {
    if (!canSubmit) {
      throw StateError(blocker ?? '邀约参数不完整');
    }
    final String content = message.trim().isNotEmpty
        ? message.trim()
        : (type == CoopInviteType.club ? '邀请贵俱乐部来参加活动' : '邀请贵店承接本主题合作');
    return <String, dynamic>{
      'inviteType': type.wire,
      'toType': type.toType,
      'toId': target.toId,
      'topicId': topicId,
      'shareMode': shareMode.wire,
      'message': content,
      if (shareMode == CoopShareMode.fixed) 'fixedFee': fixedFee,
      if (type == CoopInviteType.club && originApplyId != null)
        'originApplyId': originApplyId,
      if (scope != null && scope!.isNotEmpty) 'scope': scope,
    };
  }

  CoopInviteForm copyWith({
    CoopInviteType? type,
    int? topicId,
    String? topicName,
    List<CoopInviteTarget>? targets,
    String? message,
    CoopShareMode? shareMode,
    double? fixedFee,
    bool clearFixedFee = false,
    int? originApplyId,
    String? scope,
  }) {
    final nextType = type ?? this.type;
    return CoopInviteForm(
      type: nextType,
      topicId: topicId ?? this.topicId,
      topicName: topicName ?? this.topicName,
      // ★ 换了邀请类型必须清空已选 —— 商家 id 和俱乐部 id 是**两套 id 空间**,
      //   留着会把商家 id 当俱乐部 id 发出去。
      targets: type != null && type != this.type
          ? const <CoopInviteTarget>[]
          : (targets ?? this.targets),
      message: message ?? this.message,
      shareMode: shareMode ?? this.shareMode,
      fixedFee: clearFixedFee ? null : (fixedFee ?? this.fixedFee),
      // originApplyId 只能跟 type1 俱乐部 id 空间。换类型必须一起清。
      originApplyId: type != null && type != this.type
          ? null
          : (originApplyId ?? this.originApplyId),
      // ★ copyWith 是逐字段重建的:漏一个字段,用户改一下留言就把它丢了。
      scope: scope ?? this.scope,
    );
  }
}
