/// NPC 出场信息。
class NpcProfile {
  final int profileId;
  final String name;
  final String? avatar;
  final int scopeType; // 1=剧本角色 2=门店分身 3=全局NPC
  final int sort;
  final String? greeting;

  const NpcProfile({
    required this.profileId,
    required this.name,
    this.avatar,
    required this.scopeType,
    this.sort = 0,
    this.greeting,
  });

  factory NpcProfile.fromJson(Map<String, dynamic> json) {
    return NpcProfile(
      profileId: (json['profileId'] as num).toInt(),
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String?,
      scopeType: (json['scopeType'] as num?)?.toInt() ?? 1,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
      greeting: json['greeting'] as String?,
    );
  }
}

/// 事件冒泡话术。
class NpcLine {
  final int profileId;
  final String? name;
  final String? avatar;
  final String line;

  const NpcLine({
    required this.profileId,
    this.name,
    this.avatar,
    required this.line,
  });

  factory NpcLine.fromJson(Map<String, dynamic> json) {
    return NpcLine(
      profileId: (json['profileId'] as num).toInt(),
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
      line: json['line'] as String? ?? '',
    );
  }
}

/// NPC 事件类型: 对应后端 event_type。
enum NpcEventType {
  enter,
  checkinSuccess,
  answerWrong,
  answerRight,
  nearMerchant,
  activityFinish,
}

extension NpcEventTypeExt on NpcEventType {
  String get apiValue {
    switch (this) {
      case NpcEventType.enter:
        return 'enter';
      case NpcEventType.checkinSuccess:
        return 'checkin_success';
      case NpcEventType.answerWrong:
        return 'answer_wrong';
      case NpcEventType.answerRight:
        return 'answer_right';
      case NpcEventType.nearMerchant:
        return 'near_merchant';
      case NpcEventType.activityFinish:
        return 'activity_finish';
    }
  }
}
