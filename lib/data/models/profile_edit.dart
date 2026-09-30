/// 个人资料编辑表单。对齐后端 `UmsMemberUpdateDTO` 与 /api/user/update。
class ProfileEditForm {
  const ProfileEditForm({
    this.name = '',
    this.avatar = '',
    this.introduction = '',
    this.wechat = '',
    this.casePics = const <String>[],
    this.tagIds = const <int>[],
  });

  final String name;
  final String avatar;
  final String introduction;
  final String wechat;

  /// 探索作品(路线照片,最多 9 张)。★ 必须回传:`/api/user/update` 是
  ///   整字段覆盖(`umsMember.setCasePics(request.getCasePics())`),
  ///   不带这一项 = 把用户在别处存的路线照片**清空**。
  final List<String> casePics;

  /// 路线偏好(`tagIds`,逗号分隔)。
  final List<int> tagIds;

  ProfileEditForm copyWith({
    String? name,
    String? avatar,
    String? introduction,
    String? wechat,
    List<String>? casePics,
    List<int>? tagIds,
  }) {
    return ProfileEditForm(
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      introduction: introduction ?? this.introduction,
      wechat: wechat ?? this.wechat,
      casePics: casePics ?? this.casePics,
      tagIds: tagIds ?? this.tagIds,
    );
  }

  /// 昵称必填 —— ★ 后端**不校验**(updateUserInfo 直接 setName),
  ///   空昵称会真的存进库,然后在全站评论里显示成一片空白。
  bool get canSubmit => name.trim().isNotEmpty;

  String? get blocker => name.trim().isEmpty ? '昵称不能为空' : null;

  /// 与已有资料相比有没有真的改动。★ 没改动时提交是纯粹的浪费,
  ///   而且会白白触发一次内容安全审核(可能因为历史文案被拒)。
  bool changedFrom(ProfileEditForm original) =>
      name.trim() != original.name.trim() ||
      avatar != original.avatar ||
      introduction.trim() != original.introduction.trim() ||
      wechat.trim() != original.wechat.trim() ||
      !_sameList(casePics, original.casePics) ||
      !_sameList(tagIds, original.tagIds);

  static bool _sameList<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.every(b.contains);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.trim(),
    'avatar': avatar,
    'introduction': introduction.trim(),
    'wechat': wechat.trim(),
    'casePics': casePics.join(';'),
    'tagIds': tagIds.join(','),
  };
}

/// 资料更新失败的原因。
///
/// ★ 后端会跑**微信内容安全审核**(checkText 覆盖昵称/简介/微信号/网址/地址),
///   命中违规直接拒。这跟网络故障是两回事:
///   - 内容被拒 → 让用户改文字,**重试没用**
///   - 网络故障 → 重试有用
///   统统说成「保存失败,请重试」,用户会一直重试一段永远过不了的文案。
bool isContentRejected(String message) {
  const marks = <String>['内容', '违规', '敏感', '含有', '不合规', '审核'];
  // 「请稍后重试」「网络」这类明确的故障词优先排除,避免误判。
  if (message.contains('网络') || message.contains('稍后重试')) return false;
  return marks.any(message.contains);
}
