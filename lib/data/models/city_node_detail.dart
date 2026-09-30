import 'validation_method_labels.dart';

/// 玩家侧据点(POI)详情。对齐后端 `CityNodeVO`(/api/city/nodes/{id})。
class CityNodeDetail {
  const CityNodeDetail({
    required this.poiId,
    this.name = '',
    this.description,
    this.lat,
    this.lng,
    this.radiusM,
    this.nodeLevel,
    this.tags,
    this.coverImg,
    this.status,
    this.merchantId,
    this.merchantName,
    this.merchantLogo,
    this.merchantAddress,
    this.templateTitle,
    this.interactionType,
    this.validationMethod,
    this.couponId,
    this.questionName,
    this.questionA,
    this.questionB,
    this.questionC,
    this.questionD,
    this.completed = false,
    this.favorited = false,
  });

  final int poiId;
  final String name;
  final String? description;
  final double? lat;
  final double? lng;

  /// 打卡半径(米)。后端校验用,客户端只展示。
  final int? radiusM;
  final int? nodeLevel;
  final String? tags;
  final String? coverImg;

  /// 1 已上线(公开可见)。不是 1 时「完成打卡」等动作全部禁用。
  final int? status;
  final int? merchantId;
  final String? merchantName;
  final String? merchantLogo;
  final String? merchantAddress;

  final String? templateTitle;
  final String? interactionType;

  /// 1 文字作答 / 2 拍照打卡 / 3 选项问答 / 4 到店扫码 / 5 GPS 到达 /
  /// 6 偏好题组 / 7 传感器挑战;空与其它值按 GPS 到达处理(后端「以到店定位为准」)。
  final int? validationMethod;

  /// 到店券节点(非空表示完成打卡后要出示据点核销码给商家扫)。
  final int? couponId;

  final String? questionName;
  final String? questionA;
  final String? questionB;
  final String? questionC;
  final String? questionD;

  /// 玩家侧状态(登录时由 markUserState 标记;游客恒 false)。
  final bool completed;
  final bool favorited;

  /// 到店验证方式。5/空/其它都算「GPS 到达」——与后端分支一致,
  /// 客户端不能自己再造一个第六档。
  int get effectiveMethod => validationMethod ?? 5;

  /// 是不是到店券据点:完成打卡后要走「玩家出码 → 商家扫码发券」。
  bool get hasCoupon => couponId != null && couponId! > 0;

  /// 可互动 = 已上线 && 没完成过 && 有坐标(没坐标后端必拒,按钮该直接禁用)。
  bool get canInteract =>
      status == 1 &&
      !completed &&
      lat != null &&
      lng != null;

  /// 验证方式文案(与全 App 共用一份 0–7 码表)。
  /// 空值仍是「到店完成」;认不出的码明确回落「其他」。
  String get methodLabel => validationMethodLabel(validationMethod) ?? '到店完成';

  /// 选项问答的候选项(选项文本 + 提交值)。选项没配好的返回空表
  /// —— 后端必拒空答案,客户端应先禁用而不是点下去撞错。
  List<CityNodeChoice> get choices {
    final raw = <(String, String?)>[
      ('A', questionA),
      ('B', questionB),
      ('C', questionC),
      ('D', questionD),
    ];
    return raw
        .where((c) => (c.$2 ?? '').trim().isNotEmpty)
        .map((c) => CityNodeChoice(letter: c.$1, text: c.$2!.trim()))
        .toList();
  }

  /// 选项问答是不是「没配好」:一个选项都没有。这时互动按钮禁用,
  /// 文案说清原因(对齐小程序「这道题还没配好选项」)。
  bool get choicesNotConfigured =>
      effectiveMethod == 3 && choices.isEmpty;

  factory CityNodeDetail.fromJson(Map<String, dynamic> json) {
    return CityNodeDetail(
      poiId: (json['poiId'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      radiusM: (json['radiusM'] as num?)?.toInt(),
      nodeLevel: (json['nodeLevel'] as num?)?.toInt(),
      tags: json['tags'] as String?,
      coverImg: json['coverImg'] as String?,
      status: (json['status'] as num?)?.toInt(),
      merchantId: (json['merchantId'] as num?)?.toInt(),
      merchantName: json['merchantName'] as String?,
      merchantLogo: json['merchantLogo'] as String?,
      merchantAddress: json['merchantAddress'] as String?,
      templateTitle: json['templateTitle'] as String?,
      interactionType: json['interactionType'] as String?,
      validationMethod: (json['validationMethod'] as num?)?.toInt(),
      couponId: (json['couponId'] as num?)?.toInt(),
      questionName: json['questionName'] as String?,
      questionA: json['questionA'] as String?,
      questionB: json['questionB'] as String?,
      questionC: json['questionC'] as String?,
      questionD: json['questionD'] as String?,
      completed: json['completed'] == true,
      favorited: json['favorited'] == true,
    );
  }
}

/// 选项问答的单个选项:展示字母 + 提交值(后端只认 A-D 字母)。
class CityNodeChoice {
  const CityNodeChoice({required this.letter, required this.text});

  final String letter;
  final String text;

  String get display => '$letter. $text';
}

/// 完成打卡的结果。对齐 `/api/city/nodes/{id}/complete` 返回 data。
class CityNodeCompleteResult {
  const CityNodeCompleteResult({
    this.needRedeem = false,
    this.alreadyClaimed = false,
  });

  /// 有券节点:完成后要引导玩家出示据点核销码给商家扫码领券。
  final bool needRedeem;

  /// 已完成过(幂等拦截):「你已完成过该据点」,不是打卡失败。
  final bool alreadyClaimed;

  factory CityNodeCompleteResult.fromJson(Map<String, dynamic> json) {
    return CityNodeCompleteResult(
      needRedeem: json['needRedeem'] == true,
      alreadyClaimed: json['alreadyClaimed'] == true,
    );
  }
}

/// 据点核销码(玩家出码)。对齐 `/api/verify/citynode/issue` 返回 data。
class CityNodeVoucher {
  const CityNodeVoucher({
    this.code = '',
    this.qrcodeUrl = '',
    this.ttlMs = 0,
  });

  final String code;
  final String qrcodeUrl;

  /// 时效(毫秒)。0/缺失时按小程序默认 300000ms 处理。
  final int ttlMs;

  bool get hasCode => code.isNotEmpty;

  /// 倒计时秒数。ttl 没下发时兜底 300s,下发的是负值当 0 处理
  /// (立刻过期会触发自动重出码,不渲染负倒计时)。
  int get countdownSeconds {
    final ttl = ttlMs > 0 ? ttlMs : 300000;
    return ttl ~/ 1000;
  }

  factory CityNodeVoucher.fromJson(Map<String, dynamic> json) {
    return CityNodeVoucher(
      code: (json['code'] as String?) ?? '',
      qrcodeUrl: (json['qrcodeUrl'] as String?) ?? '',
      ttlMs: (json['ttlMs'] as num?)?.toInt() ?? 0,
    );
  }
}
