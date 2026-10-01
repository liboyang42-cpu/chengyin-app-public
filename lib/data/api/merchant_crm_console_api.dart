import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/merchant_crm_console.dart';

/// 商家 CRM 运营台的接口异常。message 是**可直接展示**的一句话
/// (后端 msg,或本地兜底文案)。
class MerchantCrmApiException implements Exception {
  const MerchantCrmApiException(this.message, {this.isLocalFallback = false});

  final String message;

  /// True only for app-authored validation, shape, or absent-message errors.
  final bool isLocalFallback;

  @override
  String toString() => message;
}

/// 商家 CRM 运营台 —— 客户名册 / 分群 / 合规触达的接口层。
///
/// ★ 真源 = 小程序只读快照 `master@90e66d70`
///   `pages/merchant/customer/index.js`,每个方法注释带调用点行号;
///   请求体逐键照搬,不编字段。
/// ★ 导出链路(`/api/merchant/crm/exports*`)已在线上的 #71 里落地,
///   这里**不重复实现**。
class MerchantCrmConsoleApi {
  MerchantCrmConsoleApi(this._client);

  final DioClient _client;

  /// 客户名册:`POST /api/merchant/crm/customers/list`。快照 index.js:476。
  ///
  /// 回包 shape 校验在 [CrmCustomerPageData.tryParse] —— 任一畸形行
  /// 整页判格式异常(快照 `_fetch` 的纪律),这里把它转成可展示的异常。
  Future<CrmCustomerPageData> customers(CrmCustomerQuery query) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/customers/list',
      query.toJson(),
      '客户名单加载失败',
    );
    final CrmCustomerPageData? page = CrmCustomerPageData.tryParse(data);
    if (page == null) {
      throw const MerchantCrmApiException('客户名单数据格式异常，请稍后重试', isLocalFallback: true);
    }
    return page;
  }

  /// 批量打标签:`POST /api/merchant/crm/customers/tags/batch`。快照 index.js:750。
  ///
  /// ★ 请求体只有 `{customerMemberIds, tagName, tagColor, requestId}` ——
  ///   不带 merchantId(商家主体由后端从登录态解析),快照单测专门钉过。
  /// ★ [requestId] 幂等,**重试复用同一个值**。
  Future<void> batchTag({
    required List<int> customerMemberIds,
    required String tagName,
    String tagColor = kCrmBatchTagColor,
    required String requestId,
  }) => _post('/api/merchant/crm/customers/tags/batch', <String, dynamic>{
    'customerMemberIds': customerMemberIds,
    'tagName': tagName,
    'tagColor': tagColor,
    'requestId': requestId,
  }, '批量加标签失败');

  /// 换取客户明文号码:`POST /api/merchant/crm/customers/{id}/contact`。
  /// 快照 index.js:734(F15)。
  ///
  /// ★ 列表里的号是服务端脱敏号(138****0000),拿它拨号是打不通的。
  ///   每次联系都要先换明文 —— 权限、归属、同意、日限与访问审计
  ///   都在这一条链上判,所以**不能**缓存复用上一次的号。
  /// [purpose] 是 `call` / `copy`(服务端按用途记审计)。
  Future<String> revealContact(
    int customerMemberId, {
    required String purpose,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/customers/$customerMemberId/contact',
      <String, dynamic>{'purpose': purpose},
      '号码没能取到，请检查网络后重试',
    );
    final String phone = '${data['phone'] ?? ''}'.trim();
    if (phone.isEmpty) {
      throw const MerchantCrmApiException('服务端没有下发可用号码', isLocalFallback: true);
    }
    return phone;
  }

  /// 已保存分群:`GET /api/merchant/crm/segments`。快照 index.js:809。
  Future<List<CrmSavedSegment>> segments() async {
    final Object? data = await _get('/api/merchant/crm/segments', '保存分群加载失败');
    if (data is! List) {
      throw const MerchantCrmApiException('保存分群加载失败', isLocalFallback: true);
    }
    return CrmSavedSegment.parseList(data);
  }

  /// 保存分群:`POST /api/merchant/crm/segments {name, filter, requestId}`。
  /// 快照 index.js:779。
  Future<void> saveSegment({
    required String name,
    required CrmSegmentFilter filter,
    required String requestId,
  }) => _post('/api/merchant/crm/segments', <String, dynamic>{
    'name': name,
    'filter': filter.toJson(),
    'requestId': requestId,
  }, '保存分群失败');

  /// 当前商家有效券:`GET /api/merchant/crm/campaigns/coupons`。快照 index.js:891。
  Future<List<CrmCoupon>> coupons() async {
    final Object? data = await _get(
      '/api/merchant/crm/campaigns/coupons',
      '优惠券加载失败',
    );
    if (data is! List) {
      throw const MerchantCrmApiException('优惠券加载失败', isLocalFallback: true);
    }
    return CrmCoupon.parseList(data);
  }

  /// 触达预览:`POST /api/merchant/crm/campaigns/preview {segmentId, channel}`。
  /// 快照 index.js:926。
  ///
  /// ★★ 请求体**只有** segmentId + channel —— 不提交客户端 memberId 名单,
  ///   也不带 merchantId。快照单测 `merchant-crm-campaign-ui.test.js` 钉过。
  Future<CrmCampaignPreview> previewCampaign({
    required int segmentId,
    required String channel,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/campaigns/preview',
      <String, dynamic>{'segmentId': segmentId, 'channel': channel},
      '触达预览失败',
    );
    final CrmCampaignPreview? preview = CrmCampaignPreview.tryParse(data);
    if (preview == null) {
      throw const MerchantCrmApiException('触达预览失败', isLocalFallback: true);
    }
    return preview;
  }

  /// 创建触达任务:`POST /api/merchant/crm/campaigns`。快照 index.js:962。
  ///
  /// 创建成功只说明任务**已建**;真正发送要再调 [dispatchCampaign]
  /// (快照 `submitCampaign` → `_dispatchCampaign` 两步)。
  Future<CrmCampaignTask> createCampaign({
    required int segmentId,
    required String channel,
    int? couponId,
    required String title,
    required String content,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/campaigns',
      <String, dynamic>{
        'segmentId': segmentId,
        'channel': channel,
        'couponId': couponId,
        'title': title,
        'content': content,
        'requestId': requestId,
      },
      '触达任务创建失败',
    );
    final CrmCampaignTask? task = CrmCampaignTask.tryParse(data);
    if (task == null || task.id == null) {
      throw const MerchantCrmApiException('触达任务创建失败', isLocalFallback: true);
    }
    return task;
  }

  /// 投放:`POST /api/merchant/crm/campaigns/{id}/dispatch`。快照 index.js:988。
  Future<CrmCampaignTask> dispatchCampaign(int campaignId) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/campaigns/$campaignId/dispatch',
      const <String, dynamic>{},
      '触达发送失败，可从任务列表重试',
    );
    final CrmCampaignTask? task = CrmCampaignTask.tryParse(data);
    if (task == null) {
      throw const MerchantCrmApiException('触达发送失败，可从任务列表重试', isLocalFallback: true);
    }
    return task;
  }

  /// 触达历史:`GET /api/merchant/crm/campaigns`。快照 index.js:1015。
  Future<List<CrmCampaignTask>> campaigns() async {
    final Object? data = await _get('/api/merchant/crm/campaigns', '');
    // 快照 index.js:1020 `if (!ok(res) || !Array.isArray(res.data)) return;` ——
    // 回包形状不对时**保留屏上已加载的历史**。这里抛出去,让调用方走
    // 「刷新失败静默降级」那条路;返空列表会把历史当成"没有历史"清掉。
    if (data is! List) {
      throw const MerchantCrmApiException('触达历史加载失败，请稍后重试', isLocalFallback: true);
    }
    return data
        .map(CrmCampaignTask.tryParse)
        .whereType<CrmCampaignTask>()
        .toList(growable: false);
  }

  /// 定向广播预览:`POST /api/merchant/crm/broadcast/preview`。快照 index.js:722。
  ///
  /// ★ 只提交筛选与范围(不提交客户端名单),同意/频控/日限全由服务端重算;
  ///   回包形状不完整就报错,不拿 0 冒充人数。
  Future<CrmBroadcastPreview> previewBroadcast(
    CrmBroadcastPayload payload,
  ) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/broadcast/preview',
      payload.toJson(),
      '可触达人数没算出来，请稍后重试',
      networkFallback: '网络连接失败，人数没核出来',
    );
    final CrmBroadcastPreview? preview = CrmBroadcastPreview.tryParse(data);
    if (preview == null) {
      throw const MerchantCrmApiException('可触达人数没算出来，请稍后重试', isLocalFallback: true);
    }
    return preview;
  }

  /// 定向广播:`POST /api/merchant/crm/broadcast`。快照 index.js:779。
  ///
  /// ★ [content] 是站内消息正文(<=120 字),请求体在 payload 之上加
  ///   `content` + [requestId]。**同一份草稿重试要复用同一个 requestId**
  ///   (后端按它幂等,网络抖动重发不会多发一条);
  ///   网络失败时回的是「点发送可重试（不会重复送达）」,就是这个保证在兜底。
  Future<CrmBroadcastResult> sendBroadcast(
    CrmBroadcastPayload payload, {
    required String content,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/broadcast',
      <String, dynamic>{
        ...payload.toJson(),
        'content': content,
        'requestId': requestId,
      },
      '发送失败，请重试',
      networkFallback: '网络连接失败，点发送可重试（不会重复送达）',
    );
    final CrmBroadcastResult? result = CrmBroadcastResult.tryParse(data);
    if (result == null) {
      throw const MerchantCrmApiException('发送结果异常，请重试并按结果核对', isLocalFallback: true);
    }
    return result;
  }

  /// 单条任务回执:`GET /api/merchant/crm/campaigns/{id}`。快照 index.js:1036。
  Future<CrmCampaignTask> campaignDetail(int campaignId) async {
    final Object? data = await _get(
      '/api/merchant/crm/campaigns/$campaignId',
      '回执加载失败',
    );
    final CrmCampaignTask? task = data is Map<String, dynamic>
        ? CrmCampaignTask.tryParse(data)
        : null;
    if (task == null) throw const MerchantCrmApiException('回执加载失败', isLocalFallback: true);
    return task;
  }

  /// 重试可重试人群:`POST /api/merchant/crm/campaigns/{id}/retry`。快照 index.js:1059。
  Future<CrmCampaignTask> retryCampaign(int campaignId) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/crm/campaigns/$campaignId/retry',
      const <String, dynamic>{},
      '重试失败',
    );
    final CrmCampaignTask? task = CrmCampaignTask.tryParse(data);
    if (task == null) throw const MerchantCrmApiException('重试失败', isLocalFallback: true);
    return task;
  }

  /// code==200 才算成功,取 `data`;失败抛 [MerchantCrmApiException](后端 msg 优先)。
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
    String fallback, {
    String? networkFallback,
  }) async {
    final Object? data = await _send(
      () => _client.dio.post<Map<String, dynamic>>(path, data: body),
      fallback,
      networkFallback: networkFallback,
    );
    if (data is! Map<String, dynamic>) {
      throw MerchantCrmApiException(fallback, isLocalFallback: true);
    }
    return data;
  }

  /// GET 版:`data` 可以是 List(分群 / 券 / 历史),所以返回 Object?。
  /// ★ 快照对 `campaigns` 的刷新失败是**静默降级**(保留屏上旧数据),
  ///   所以 fallback 传空串时,异常由调用方决定是否吞掉。
  Future<Object?> _get(String path, String fallback) async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _client.dio.get<Map<String, dynamic>>(path);
    } on DioException {
      throw MerchantCrmApiException(
        fallback.isEmpty ? '网络连接失败，请稍后重试' : fallback,
        isLocalFallback: true,
      );
    }
    return _unwrap(resp, fallback);
  }

  Future<Object?> _send(
    Future<Response<Map<String, dynamic>>> Function() request,
    String fallback, {
    String? networkFallback,
  }) async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await request();
    } on DioException {
      // 广播这一步要分开说:网络失败**没送达**,而 requestId 幂等保证
      // 重发不会多发一条 —— 两件事都只有网络这一档能说。
      throw MerchantCrmApiException(
        networkFallback ??
            (fallback.isEmpty ? '网络连接失败，请稍后重试' : fallback),
        isLocalFallback: true,
      );
    }
    return _unwrap(resp, fallback);
  }

  Object? _unwrap(Response<Map<String, dynamic>> resp, String fallback) {
    final Map<String, dynamic> body = resp.data ?? const <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      final String msg = '${body['msg'] ?? ''}'.trim();
      throw MerchantCrmApiException(
        msg.isNotEmpty ? msg : (fallback.isEmpty ? '操作失败' : fallback),
        isLocalFallback: msg.isEmpty,
      );
    }
    return body['data'];
  }
}
