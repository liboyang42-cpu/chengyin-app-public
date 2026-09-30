/// 门店 NPC 形象与对话。对齐后端 `ApiMerchantNpcController` 与 `/api/ai/npc/merchant-chat`。
library;

/// 商家自己那条形象(含待审 / 被驳回)。
///
/// ★ 与玩家侧在店铺主页看到的 `data.npc` 不是同一个东西:
///   这条是**商家自己的**,包含还没过审的版本;玩家侧只看得到已过审已启用的。
class MerchantNpcProfile {
  const MerchantNpcProfile({
    this.configured = false,
    this.profileId,
    this.name = '',
    this.avatar,
    this.greeting,
    this.persona = '',
    this.knowledge,
    this.auditStatus,
    this.enabled,
    this.statusText,
    this.hasVoice = false,
    this.modelUrl,
  });

  /// 有没有配过。★ 后端在「没配过」时回的是 `{configured:false}` 空壳而不是 null ——
  /// 客户端因此不必去区分「接口失败」和「还没配过」。
  final bool configured;

  final int? profileId;
  final String name;
  final String? avatar;
  final String? greeting;
  final String persona;
  final String? knowledge;

  /// 0=审核中 1=已过审 2=未通过。
  final int? auditStatus;
  final int? enabled;

  /// 状态文案由**后端下发**,客户端不自己拼 ——
  /// 两端各写一套的话,同一个状态会出现两种说法。
  final String? statusText;

  /// 有没有克隆过声音。★ 后端只回布尔不回 voiceId ——
  /// voiceId 是供应商侧标识,客户端拿它没用,回它只会扩大出参面。
  final bool hasVoice;

  /// 3D 形象 glb 地址。★ null = 没有 3D,客户端**退回 avatar 静态图** ——
  /// 这是常态,不是错误(生成还没开通、还没生成过、生成失败都会是 null)。
  final String? modelUrl;

  bool get isPending => auditStatus == null || auditStatus == 0;
  bool get isApproved => auditStatus == 1;
  bool get isRejected => auditStatus == 2;

  factory MerchantNpcProfile.fromJson(Map<String, dynamic> json) {
    String? s(String key) {
      final String v = (json[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return MerchantNpcProfile(
      configured: json['configured'] == true,
      profileId: (json['profileId'] as num?)?.toInt(),
      name: s('name') ?? '',
      avatar: s('avatar'),
      greeting: s('greeting'),
      persona: s('persona') ?? '',
      knowledge: s('knowledge'),
      auditStatus: (json['auditStatus'] as num?)?.toInt(),
      enabled: (json['enabled'] as num?)?.toInt(),
      statusText: s('statusText'),
      hasVoice: json['hasVoice'] == true,
      modelUrl: s('modelUrl'),
    );
  }

  MerchantNpcProfile copyWith({
    String? name,
    Object? avatar = _unset,
    Object? greeting = _unset,
    String? persona,
    Object? knowledge = _unset,
  }) {
    return MerchantNpcProfile(
      configured: configured,
      profileId: profileId,
      name: name ?? this.name,
      avatar: avatar == _unset ? this.avatar : avatar as String?,
      greeting: greeting == _unset ? this.greeting : greeting as String?,
      persona: persona ?? this.persona,
      knowledge: knowledge == _unset ? this.knowledge : knowledge as String?,
      auditStatus: auditStatus,
      enabled: enabled,
      statusText: statusText,
      hasVoice: hasVoice,
      modelUrl: modelUrl,
    );
  }

  static const Object _unset = Object();

  /// 还差哪一条。null = 可以提交。与后端 `validate()` 同口径,
  /// 但**后端那道才算数** —— 这里只是让商家不必提交完才知道缺什么。
  String? get blocker {
    if (name.trim().isEmpty) return '请给形象起个名字';
    if (name.trim().length > 20) return '名字不超过 20 字';
    if ((avatar ?? '').trim().isEmpty) return '请上传形象头像';
    if ((greeting ?? '').trim().length > 60) return '招呼语不超过 60 字';
    if (persona.trim().isEmpty) return '请填写形象的说话风格(人设)';
    if (persona.trim().length > 1000) return '人设不超过 1000 字';
    if ((knowledge ?? '').trim().length > 2000) return '店铺知识不超过 2000 字';
    return null;
  }

  bool get canSubmit => blocker == null;
}

/// 一次对话的结果。对齐后端 `NpcChatResp`。
///
/// ★★ 后端**从不返回未经审核的原文**:`safeText` 已经过出参内容安全。
///   客户端直接显示它,不要再对它做任何"看起来更像 AI"的加工。
class NpcChatResult {
  const NpcChatResult({
    required this.status,
    this.safeText,
    this.errorCode,
    this.retryable = false,
    this.retryAfterSeconds,
    this.audioUrl,
  });

  /// PROCESSING / SUCCEEDED / REJECTED / FAILED。
  final String status;
  final String? safeText;
  final String? errorCode;

  /// 能不能重试。★ 这条决定 UI 给不给重试按钮 ——
  ///   身份/合规类拒绝重试永远不会成功,给按钮等于让人一直点。
  final bool retryable;
  final int? retryAfterSeconds;

  /// 合成语音地址。★ **null 是常态,不是错误** ——
  /// 没克隆过声音、供应商未开通、合成失败都会是 null,那时只显示文字。
  final String? audioUrl;

  bool get succeeded => status == 'SUCCEEDED';

  /// 还在处理中(同一 requestId 的并发重放)。客户端应稍后重试同一个 requestId。
  bool get inProgress => status == 'PROCESSING';

  /// 给用户看的那句话。后端在任何终态都会给一句安全文案,
  /// 兜底只是为了 null 安全,正常不会走到。
  String get displayText => (safeText ?? '').trim().isNotEmpty
      ? safeText!.trim()
      : '现在有点忙,请稍后再试。';

  factory NpcChatResult.fromJson(Map<String, dynamic> json) {
    return NpcChatResult(
      status: (json['outcomeStatus'] ?? 'FAILED').toString(),
      safeText: json['safeText'] as String?,
      errorCode: json['errorCode'] as String?,
      retryable: json['retryable'] == true,
      retryAfterSeconds: (json['retryAfterSeconds'] as num?)?.toInt(),
      audioUrl: (json['audioUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['audioUrl'] as String).trim(),
    );
  }
}


/// 声音克隆要念的脚本 + 供应商可用性。
///
/// ★★ [consentIndex] 那一句是**授权声明**,UI 必须单独标出来 ——
///   那段录音本身就是「本人同意用自己的声音」的证据,不能让人以为只是随便一句话。
class VoiceEnrollScript {
  const VoiceEnrollScript({
    this.available = false,
    this.lines = const <String>[],
    this.consentIndex = 0,
  });

  /// 供应商接没接。★ false 时不显示录音入口,而不是让人录完才失败。
  final bool available;

  final List<String> lines;

  /// 哪一句是授权声明。
  final int consentIndex;

  bool isConsentLine(int index) => index == consentIndex;

  factory VoiceEnrollScript.fromJson(Map<String, dynamic> json) {
    return VoiceEnrollScript(
      available: json['available'] == true,
      lines: <String>[
        for (final Object? line in (json['script'] as List<dynamic>?) ?? const <dynamic>[])
          if ((line?.toString() ?? '').trim().isNotEmpty) line!.toString().trim(),
      ],
      consentIndex: (json['consentIndex'] as num?)?.toInt() ?? 0,
    );
  }
}


/// 3D 形象生成的一次任务。对齐后端 `npc_avatar_job`。
class NpcAvatarJob {
  const NpcAvatarJob({
    required this.jobId,
    required this.status,
    this.style = 'realistic',
    this.modelUrl,
    this.thumbUrl,
    this.failReason,
  });

  final int jobId;

  /// PENDING / SUCCEEDED / FAILED。
  ///
  /// ★★ PENDING 与 FAILED 的差别是「会不会再变」——
  /// 客户端据此决定**还要不要继续轮询**。把认不出的状态当 PENDING 会让它转到天荒地老。
  final String status;

  final String style;
  final String? modelUrl;
  final String? thumbUrl;

  /// 失败原因。★ 后端给的是**安全文案**,不是供应商原文,可以直接显示。
  final String? failReason;

  bool get pending => status == 'PENDING';
  bool get succeeded => status == 'SUCCEEDED';

  /// 还要不要接着轮询。★ 只有明确的 PENDING 才继续 ——
  /// 认不出的状态按「不再轮询」,宁可让人手动刷新,也不要一个永远转的圈。
  bool get shouldKeepPolling => pending;

  factory NpcAvatarJob.fromJson(Map<String, dynamic> json) {
    String? s(String key) {
      final String v = (json[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return NpcAvatarJob(
      jobId: (json['jobId'] as num?)?.toInt() ?? 0,
      // 缺省按 FAILED 而不是 PENDING:认不出的终态不该让人一直等。
      status: s('status') ?? 'FAILED',
      style: s('style') ?? 'realistic',
      modelUrl: s('modelUrl'),
      thumbUrl: s('thumbUrl'),
      failReason: s('failReason'),
    );
  }
}

/// 3D 形象生成的可用性 + 最近一次任务。
class NpcAvatarStatus {
  const NpcAvatarStatus({
    this.available = false,
    this.styles = const <String>[],
    this.job,
  });

  /// 供应商接没接。★ false 时不显示生成入口。
  final bool available;

  final List<String> styles;

  /// 最近一次任务;没提交过是 null。
  final NpcAvatarJob? job;

  factory NpcAvatarStatus.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? job = json['job'] as Map<String, dynamic>?;
    return NpcAvatarStatus(
      available: json['available'] == true,
      styles: <String>[
        for (final Object? s in (json['styles'] as List<dynamic>?) ?? const <dynamic>[])
          if ((s?.toString() ?? '').trim().isNotEmpty) s!.toString().trim(),
      ],
      job: job == null ? null : NpcAvatarJob.fromJson(job),
    );
  }
}

/// 声音克隆的生成状态:`POST /api/merchant/npc/voice/status`。
///
/// 四态与小程序 `pages/merchant/decor/ai-npc/index.js:506-520` 一致:
/// 0 未配置 / 1 生成中 / 2 已就绪 / 3 上次生成失败。
///
/// ★ 为什么要有它:录音提交是**异步**的 —— 录完只说明「提交成功」,
///   供应商那边的克隆还在跑。没有这条,商家提交完就再也看不到进度,
///   只能靠「过几天看有没有声音」猜。
class NpcVoiceStatus {
  const NpcVoiceStatus({required this.voiceStatus, this.voiceSample});

  final int voiceStatus;
  final String? voiceSample;

  bool get isUnset => voiceStatus == 0;
  bool get isGenerating => voiceStatus == 1;
  bool get isReady => voiceStatus == 2;
  bool get isFailed => voiceStatus == 3;

  /// 状态文案。逐字对齐小程序 ai-npc 页的 voiceStatusText。
  String get label {
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

  factory NpcVoiceStatus.fromJson(Map<String, dynamic> json) => NpcVoiceStatus(
    voiceStatus: int.tryParse('${json['voiceStatus']}') ?? 0,
    voiceSample: (json['voiceSample'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['voiceSample'] as String).trim(),
  );
}
