import 'dart:convert';

import '../../core/network/dio_client.dart';

/// 行为埋点批量上报:`POST /api/analytics/events/batch`。
///
/// ★★ 后端的校验是**整批同拒**:50 条里有一条不合规,**整批都不落库**,
///   而且只回一句错。所以三道闸必须**搬到客户端发送前**,
///   否则一条拼错的事件名会把同批 49 条正常埋点一起弄丢,还查不出是哪条。
///
/// 三道闸:
///   ① 事件名必须在白名单里(后端 48 个);
///   ② 属性 JSON 不得含敏感键(手机号/坐标/token/文本内容 等);
///   ③ 漫游 AI 表面事件**不得带 bizId 和属性**(隐私口径:只记"露出过",不记内容)。
///
/// ★ 埋点失败**永远不该打断用户** —— API 把失败交还 Tracker 回队列，
/// Tracker 静默处理，不让页面调用链感知。
class AnalyticsApi {
  AnalyticsApi(this._client);
  final DioClient _client;

  static const int maxBatchSize = 50;
  static const int maxPropertiesLength = 4000;

  /// 后端 ALLOWED_EVENTS 的逐字副本。
  ///
  /// ⚠️ 这是**第二份清单**,天然会漂。所以有一条测试拿后端源码比对它 ——
  ///   后端加了新事件而这里没同步时会红。
  static const Set<String> allowedEvents = <String>{
    'search_submit',
    'content_view',
    'community_post_impression',
    'community_post_open',
    'community_post_qualified_view',
    'community_media_result',
    'content_like',
    'content_favorite',
    'content_share',
    'signup_start',
    'signup_submit',
    'payment_success',
    'coupon_receive',
    'coupon_verify',
    'topic_publish_success',
    'activity_publish_success',
    'template_reuse',
    'mission_complete',
    'withdrawal_submit',
    'solo_ticket_purchase',
    'play_arrive_success',
    'play_arrive_fallback',
    'node_abandon',
    'drop_shown',
    'citymap_view',
    'citymap_share',
    'track_record_start',
    'track_record_finish',
    'track_to_topic',
    'xp_alloc_done',
    'become_leader_cta',
    'play_rec_swap',
    'play_rec_accept',
    'finish_route_recommendation_shown',
    'finish_route_recommendation_click',
    'roam_start',
    'roam_poi_found',
    'roam_finish',
    'roam_discover_reward_click',
    'roam_exploreday_reco_shown',
    'roam_exploreday_reco_click',
    'roam_share_channel',
    'roam_route_story_shown',
    'roam_poi_meaning_shown',
    'roam_footprint_hint_shown',
    'roam_footprint_hint_dismissed',
    'npc_profile_loaded',
    'npc_bubble_impression',
    'npc_chat_open',
    'npc_chat_submit',
    'npc_chat_complete',
    'npc_chat_cancel',
  };

  /// 这四个事件**不得关联业务对象、不得带属性**。
  /// 隐私口径:只记录"这个 AI 表面露出过",不记录它说了什么、关于哪个点。
  static const Set<String> roamAiSurfaceEvents = <String>{
    'roam_route_story_shown',
    'roam_poi_meaning_shown',
    'roam_footprint_hint_shown',
    'roam_footprint_hint_dismissed',
  };

  /// 后端 SENSITIVE_PROPERTY_KEYS 的逐字副本。
  static const Set<String> sensitiveKeys = <String>{
    'phone',
    'mobile',
    'bank',
    'card',
    'identity',
    'idcard',
    'realname',
    'name',
    'email',
    'address',
    'location',
    'latitude',
    'longitude',
    'openid',
    'unionid',
    'session',
    'token',
    'keyword',
    'content',
    'comment',
    'message',
    'text',
    'title',
    'description',
  };

  /// 校验一条事件。返回 null = 合规,否则是**拒绝的理由**。
  ///
  /// ★ 与后端 validate 同口径。客户端先挡,是为了不让一条坏事件
  ///   把同批的好事件一起拖掉。
  static String? validate(AnalyticsEvent e) {
    if (e.eventName.isEmpty) return '事件名称不能为空';
    if (!allowedEvents.contains(e.eventName)) {
      return '不支持的埋点事件:${e.eventName}';
    }
    final String? json = e.propertiesJson;
    if (json != null && json.length > maxPropertiesLength) {
      return '事件属性过长';
    }
    if (json != null && _hasSensitive(json)) {
      return '事件属性不得包含敏感个人信息';
    }
    if (roamAiSurfaceEvents.contains(e.eventName)) {
      final bool minimal =
          (e.bizId == null || e.bizId == 0) && _isEmptyProperties(json);
      if (!minimal) return '漫游 AI 表面埋点不得关联业务对象或携带属性';
    }
    return null;
  }

  /// 上报一批。**不合规的会被就地剔除**,合规的照常发 ——
  /// 这正是客户端先挡的意义:坏的那条不拖累好的。
  ///
  /// 返回被剔除的事件与原因(调用方可在 debug 下打出来)。网络、HTTP 或
  /// AjaxResult 业务失败会抛出，让 Tracker 把整批恢复到队首。
  Future<Map<String, String>> report(List<AnalyticsEvent> events) async {
    final Map<String, String> rejected = <String, String>{};
    final List<AnalyticsEvent> ok = <AnalyticsEvent>[];
    for (final AnalyticsEvent e in events) {
      final String? why = validate(e);
      if (why != null) {
        rejected[e.eventName] = why;
      } else {
        ok.add(e);
      }
    }
    // 超批就切片发,别指望后端收 51 条。
    for (int i = 0; i < ok.length; i += maxBatchSize) {
      final List<AnalyticsEvent> slice = ok.sublist(
        i,
        (i + maxBatchSize).clamp(0, ok.length),
      );
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/analytics/events/batch',
        data: <String, dynamic>{
          'events': slice.map((AnalyticsEvent e) => e.toJson()).toList(),
        },
      );
      final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
      final Object? rawCode = body['code'];
      final int? code = rawCode is num
          ? rawCode.toInt()
          : int.tryParse(rawCode?.toString() ?? '');
      if (code != 200) {
        throw AnalyticsDeliveryException((body['msg'] as String?) ?? '埋点上报失败');
      }
    }
    return rejected;
  }
}

class AnalyticsDeliveryException implements Exception {
  const AnalyticsDeliveryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 一条埋点事件。字段对齐后端 `AnalyticsEventDTO`。
class AnalyticsEvent {
  const AnalyticsEvent({
    required this.eventName,
    this.anonymousId,
    this.sessionId,
    this.source,
    this.pagePath,
    this.bizType,
    this.bizId,
    this.cityCode,
    this.properties,
    this.idempotencyKey,
    this.actorScope,
    this.occurredAt,
  });

  final String eventName;
  final String? anonymousId;
  final String? sessionId;
  final String? source;
  final String? pagePath;
  final String? bizType;
  final int? bizId;
  final String? cityCode;

  /// 属性。序列化成 propertiesJson 发出去。
  final Map<String, dynamic>? properties;

  final String? idempotencyKey;
  final String? actorScope;
  final DateTime? occurredAt;

  String? get propertiesJson =>
      properties == null || properties!.isEmpty ? null : jsonEncode(properties);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventName': eventName,
    'anonymousId': ?anonymousId,
    'sessionId': ?sessionId,
    'source': ?source,
    'pagePath': ?pagePath,
    'bizType': ?bizType,
    'bizId': ?bizId,
    'cityCode': ?cityCode,
    'propertiesJson': ?propertiesJson,
    'idempotencyKey': ?idempotencyKey,
    'actorScope': ?actorScope,
    'occurredAt': ?occurredAt?.toIso8601String(),
  };
}

/// 与后端 `containsSensitiveProperties` 同口径。
///
/// ★★ 三条容易漏的(我第一版就漏了全部三条):
///   ① 键要**先剥掉非字母数字再小写**才比 —— `user_name` / `user-name`
///      归一化成 `username`,含 `name` ⇒ 拒。只按原样比会漏掉带下划线的写法。
///   ② **嵌套容器一律拒**(`value.isContainerNode()`)——
///      不是"检查里面",是直接拒。属性必须是扁平的标量。
///   ③ **值本身**也查:手机号 / 邮箱 / 15~19 位数字(卡号)⇒ 拒,
///      哪怕键名完全无辜。
bool _hasSensitive(String propertiesJson) {
  if (propertiesJson.trim().isEmpty) return false;
  try {
    final Object? root = jsonDecode(propertiesJson);
    // 后端:`root == null || !root.isObject()` 即视为敏感(fail-closed)。
    if (root is! Map<String, dynamic>) return true;
    for (final MapEntry<String, dynamic> e in root.entries) {
      final String normalized = e.key
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toLowerCase();
      if (AnalyticsApi.sensitiveKeys.any(normalized.contains)) return true;
      final Object? v = e.value;
      // ② 嵌套容器直接拒。
      if (v is Map || v is List) return true;
      // ③ 值本身像手机号/邮箱/卡号也拒。
      if (v is String && _isSensitiveValue(v)) return true;
    }
    return false;
  } catch (_) {
    // 解析不了当它有问题 —— 与后端 catch 分支一致。
    return true;
  }
}

final RegExp _phone = RegExp(r'^1[3-9]\d{9}$');
final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _cardNo = RegExp(r'^\d{15,19}$');

bool _isSensitiveValue(String v) =>
    _phone.hasMatch(v) || _email.hasMatch(v) || _cardNo.hasMatch(v);

bool _isEmptyProperties(String? propertiesJson) {
  if (propertiesJson == null || propertiesJson.trim().isEmpty) return true;
  try {
    final Object? root = jsonDecode(propertiesJson);
    if (root is Map) return root.isEmpty;
    return false;
  } catch (_) {
    return false;
  }
}
