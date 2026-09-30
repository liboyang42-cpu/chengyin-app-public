/// 章节点位上的 AI 角色(`/api/merchant/chapter-node/npc/*`)。
///
/// ★★ 与**门店**形象(`/api/merchant/npc/*`)是两套独立的东西:
///   · 门店形象挂在 merchant 上,玩家在店铺主页点开对话;
///   · 节点角色挂在 chapter-node 上,主题/漫游里某个点位有自己的角色。
///   后端明确「节点 NPC 不得复用门店形象端点」(node-npc-form.test.js:132),
///   所以这里不去复用 [MerchantNpcProfile]。
class ChapterNodeNpc {
  const ChapterNodeNpc({
    this.name = '',
    this.avatar = '',
    this.greeting = '',
    this.voiceStatus,
    this.voiceSample,
  });

  final String name;

  /// 形象图 URL。空 = 没配过形象。
  final String avatar;

  final String greeting;

  /// 后端四态:**0 未配置 / 1 生成中 / 2 已就绪 / 3 上次生成失败**。
  ///
  /// ★ 缺席保持 null(点位不存在/未绑定节点时后端不回这个字段)——
  ///   不兜成 0,那会把「没读到」说成「未配置」。
  final int? voiceStatus;

  /// 已生效的录音地址(就绪后才有)。
  final String? voiceSample;

  /// 配过形象才算「有这个角色」。★ 判据用 avatar 而不是 name:
  ///   node-npc-form 的判断就是 `hasProfile: !!avatar`
  ///   (components/cy/node-npc-form/index.js:120)。
  bool get configured => avatar.trim().isNotEmpty;

  bool get isVoiceUnset => voiceStatus == 0;
  bool get isVoiceGenerating => voiceStatus == 1;
  bool get isVoiceReady => voiceStatus == 2;
  bool get isVoiceFailed => voiceStatus == 3;

  /// 声音四态文案。逐字对齐小程序 node-npc-form/index.js:420-424。
  /// ★ 未知值不猜:说「状态未知」比把失败说成已就绪安全得多。
  String get voiceLabel {
    switch (voiceStatus) {
      case 0:
        return '未配置(可选)';
      case 1:
        return '声音生成中…(稍后自动刷新)';
      case 2:
        return '声音已就绪';
      case 3:
        return '上次生成失败,可以重新生成';
      default:
        return '声音状态未知';
    }
  }

  ChapterNodeNpc copyWith({
    String? name,
    String? avatar,
    String? greeting,
    int? voiceStatus,
    String? voiceSample,
  }) => ChapterNodeNpc(
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    greeting: greeting ?? this.greeting,
    voiceStatus: voiceStatus ?? this.voiceStatus,
    voiceSample: voiceSample ?? this.voiceSample,
  );

  /// 保存的闸:名字必填(与 node-npc-form/index.js:265 的 `_fail('请填写角色名字')` 同判据)。
  String? get saveBlocker {
    if (name.trim().isEmpty) return '请填写角色名字';
    if (avatar.trim().isEmpty) return '请先选一张形象照片';
    return null;
  }

  factory ChapterNodeNpc.fromJson(Map<String, dynamic> json) => ChapterNodeNpc(
    name: (json['name'] as String?) ?? '',
    avatar: (json['avatar'] as String?) ?? '',
    greeting: (json['greeting'] as String?) ?? '',
    voiceStatus: json['voiceStatus'] == null
        ? null
        : int.tryParse('${json['voiceStatus']}'),
    voiceSample: json['voiceSample'] as String?,
  );

  static const ChapterNodeNpc empty = ChapterNodeNpc();
}
