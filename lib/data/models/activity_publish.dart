/// 发布活动的表单。对齐后端 `CmsActivityPublishRequest` 与 `/api/activity/publish`。
///
/// ★ 后端有**四道闸**(ApiActivityController:633-660):
///   ① 登录 ② **仅俱乐部主理人可发布活动** ③ 配额 ④ 内容安全审核
///   前两条前端能提前判,后两条只能等后端回。
String? _wireDateTime(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class ActivityPublishForm {
  const ActivityPublishForm({
    this.name = '',
    this.description = '',
    this.imgUrl,
    this.addressName,
    this.address,
    this.longitude,
    this.latitude,
    this.startDate,
    this.endDate,
    this.templateId,
    this.categoryIds = const <int>[],
    this.tickets = const <TicketDraft>[],
    this.collaborators = const <int>[],
  });

  final String name;
  final String description;
  final String? imgUrl;
  final String? addressName;
  final String? address;
  final String? longitude;
  final String? latitude;

  /// 后端 `@NotNull`。
  final DateTime? startDate;
  final DateTime? endDate;

  final int? templateId;
  final List<int> categoryIds;
  final List<TicketDraft> tickets;

  /// 合作者的 memberId。对齐后端 `CmsActivityPublishRequest.collaborators`。
  ///
  /// ⚠️ 后端字段名是 **collaborators**(复数、不带 Ids)——
  ///   专业发布那边叫 collaboratorIds,两个接口不是一个名字,别照抄。
  final List<int> collaborators;

  /// 时间是否自洽。★ 结束必须**晚于**开始 —— 相等也不行,
  ///   零时长的活动没有意义,而后端只校验非空、不校验先后。
  bool get timeValid {
    final s = startDate;
    final e = endDate;
    if (s == null || e == null) return false;
    return e.isAfter(s);
  }

  /// 每张票自身是否有效,且**票的履约窗口不能超出活动窗口**。
  ///
  /// ★ 后端只对票做 @NotNull,**不校验它与活动时间的关系** ——
  ///   票的履约期跑到活动结束之后,就会出现"活动都结束了票还能核销"。
  String? ticketBlocker() {
    for (int i = 0; i < tickets.length; i++) {
      final t = tickets[i];
      final label = t.name.trim().isEmpty ? '第 ${i + 1} 张票' : t.name.trim();
      final own = t.blocker;
      if (own != null) return '$label:$own';
      if (startDate != null && t.startTime!.isBefore(startDate!)) {
        return '$label:履约开始早于活动开始';
      }
      if (endDate != null && t.endTime!.isAfter(endDate!)) {
        return '$label:履约结束晚于活动结束';
      }
    }
    return null;
  }

  bool get canSubmit => blocker == null;

  /// 不能提交时说出缺什么 —— 按用户填写顺序报,不是一次报一堆。
  String? get blocker {
    if (name.trim().isEmpty) return '请填写活动标题';
    if ((addressName ?? '').trim().isEmpty) return '请填写活动地点';
    if (description.trim().isEmpty) return '请填写活动说明';
    if (startDate == null) return '请选择活动开始时间';
    if (endDate == null) return '请选择活动结束时间';
    if (!timeValid) return '结束时间要晚于开始时间';
    if (templateId == null || templateId! <= 0) return '请选择模板';
    if ((imgUrl ?? '').trim().isEmpty) return '请上传活动封面';
    if (categoryIds.isEmpty) return '请选择至少一个活动类型';
    if (tickets.isEmpty) return '至少添加一张票';
    return ticketBlocker();
  }

  ActivityPublishForm copyWith({
    String? name,
    String? description,
    String? imgUrl,
    String? addressName,
    String? address,
    String? longitude,
    String? latitude,
    DateTime? startDate,
    DateTime? endDate,
    int? templateId,
    List<int>? categoryIds,
    List<TicketDraft>? tickets,
    List<int>? collaborators,
  }) {
    return ActivityPublishForm(
      name: name ?? this.name,
      description: description ?? this.description,
      imgUrl: imgUrl ?? this.imgUrl,
      addressName: addressName ?? this.addressName,
      address: address ?? this.address,
      longitude: longitude ?? this.longitude,
      latitude: latitude ?? this.latitude,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      templateId: templateId ?? this.templateId,
      categoryIds: categoryIds ?? this.categoryIds,
      tickets: tickets ?? this.tickets,
      collaborators: collaborators ?? this.collaborators,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.trim(),
    'description': description.trim(),
    'imgUrl': ?imgUrl,
    // 小程序与后端同时保留 imgUrl/imgArr，活动封面两者同值。
    'imgArr': ?imgUrl,
    // 后端 DTO 收逗号分隔字符串，不是 JSON 数组。
    'categoryIds': categoryIds.join(','),
    'addressName': ?addressName,
    'address': ?address,
    'longitude': ?longitude,
    'latitude': ?latitude,
    // 后端 @JsonFormat 是 yyyy-MM-dd HH:mm:ss，与小程序一致。
    'startDate': _wireDateTime(startDate),
    'endDate': _wireDateTime(endDate),
    'templateId': ?templateId,
    'tickets': tickets.map((TicketDraft t) => t.toJson()).toList(),
    // 空列表也发 —— 后端按「传了就覆盖」处理,不发的话改不回「只有我」。
    'collaborators': collaborators,
  };
}

/// 一张票。对齐后端 `ActivityTicketRequest`(五个字段全是 @NotNull/@NotBlank)。
class TicketDraft {
  const TicketDraft({
    this.name = '',
    this.price,
    this.startTime,
    this.endTime,
    this.totalStock,
  });

  final String name;

  /// ★ 用 `double?` 而不是 `double` —— **「还没填价格」与「免费(0)」是两回事**。
  ///   默认成 0 会让用户以为自己设了免费票,其实只是没填。
  final double? price;

  final DateTime? startTime;
  final DateTime? endTime;

  /// 总库存。同理用可空 —— 「没填」不是「0 张」。
  final int? totalStock;

  String? get blocker {
    if (name.trim().isEmpty) return '票种名称不能为空';
    if (price == null) return '请填写价格(免费填 0)';
    if (price! < 0) return '价格不能为负';
    if (startTime == null || endTime == null) return '请选择履约时间';
    if (!endTime!.isAfter(startTime!)) return '履约结束要晚于开始';
    if (totalStock == null) return '请填写总库存';
    if (totalStock! <= 0) return '总库存要大于 0';
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.trim(),
    'price': price,
    'startTime': _wireDateTime(startTime),
    'endTime': _wireDateTime(endTime),
    'totalStock': totalStock,
  };
}
