/// CRM 运营台接口(`MerchantCrmConsoleApi`)的测试替身。
///
/// ★ 商家客户页 `_bootstrap` 会按能力位真打网络(名册 / 保存分群 / 券 / 触达历史),
///   凡是渲染这一页的用例都必须桩掉它,否则测试里会发真请求、留 pending timer。
/// ★ 每次调用都记进 `queries` 等记录(给「点下去有没有发对请求」的判据用);
///   没桩的方法走 noSuchMethod 直接抛 —— 页面真调了没桩的方法时会红,
///   而不是悄悄返回空数据把判据糊过去。
library;

import 'package:chengyin_app/data/api/merchant_crm_console_api.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';

class FakeCrmConsoleApi implements MerchantCrmConsoleApi {
  FakeCrmConsoleApi({
    CrmCustomerPageData? page,
    this.segmentRows = const <CrmSavedSegment>[],
    this.couponRows = const <CrmCoupon>[],
    this.campaignRows = const <CrmCampaignTask>[],
    CrmCampaignTask? task,
    CrmCampaignPreview? preview,
    Map<String, String>? failures,
  }) : page = page ?? emptyPage(),
       task =
           task ??
           CrmCampaignTask.tryParse(<String, dynamic>{
             'id': 7,
             'status': 'SUCCESS',
             'recipientCount': 12,
             'deliveredCount': 12,
           })!,
       preview =
           preview ??
           const CrmCampaignPreview(
             totalCount: 12,
             consentedCount: 10,
             deliverableCount: 9,
           ),
       failures = failures ?? <String, String>{};

  /// 「一位客户都没有」的合法分页回包(空态四档里的一档)。
  static CrmCustomerPageData emptyPage() =>
      CrmCustomerPageData.tryParse(<String, dynamic>{
        'total': 0,
        'rows': <dynamic>[],
        'segmentCounts': <String, dynamic>{'all': 0},
      })!;

  /// 一行合法客户的原始回包,字段与真源 `isCustomerRow` 逐条对齐。
  static Map<String, dynamic> rowJson({
    int memberId = 42,
    String name = '张三',
    String? phone = '13812341234',
    String? contactHint,
    String? latestNote,
    String tier = 'pending',
    String sourceType = 'TOPIC',
    String lastTime = '2026-09-10 12:00:00',
    String lastAction = '核销了夜跑咖啡路线',
  }) => <String, dynamic>{
    'memberId': memberId,
    'name': name,
    'avatar': null,
    'phone': phone,
    'contactHint': contactHint,
    'latestNote': latestNote,
    'arrivedCount': 2,
    'pendingCount': 0,
    'refundedCount': 0,
    'paidAmount': 199.0,
    'lastTime': lastTime,
    'lastAction': lastAction,
    'tier': tier,
    'sourceType': sourceType,
  };

  /// 用原始行拼一页(和真后端同一条路径:走 `tryParse` 的 fail-closed 校验)。
  static CrmCustomerPageData pageOf(
    List<Map<String, dynamic>> rows, {
    int? total,
    Map<String, dynamic>? segmentCounts,
  }) => CrmCustomerPageData.tryParse(<String, dynamic>{
    'total': total ?? rows.length,
    'rows': rows,
    'segmentCounts': segmentCounts ?? <String, dynamic>{'all': rows.length},
  })!;

  CrmCustomerPageData page;
  List<CrmSavedSegment> segmentRows;
  List<CrmCoupon> couponRows;
  List<CrmCampaignTask> campaignRows;

  /// 触达四连(create / dispatch / retry / detail)的应答。
  CrmCampaignTask task;
  CrmCampaignPreview preview;

  /// 定向广播的 preview / send 应答。
  CrmBroadcastPreview broadcastPreview = CrmBroadcastPreview(
    audienceCount: 30,
    consentedCount: 12,
    noConsentCount: 18,
    frequencyLimitedCount: 2,
    deliverableCount: 10,
    recipientLimit: 500,
    merchantDailyLimit: 3,
    merchantDailyUsed: 1,
    merchantDailyRemaining: 2,
    filterTotalCount: 30,
  );
  CrmBroadcastResult broadcastResult = CrmBroadcastResult(
    id: 9,
    status: 'SUCCESS',
    audienceCount: 30,
    consentedCount: 12,
    noConsentCount: 18,
    frequencySkippedCount: 2,
    deliveredCount: 10,
    failedCount: 0,
  );

  /// 方法名 → 异常文案:让某一步按需失败,验错误态。
  final Map<String, String> failures;

  final List<CrmCustomerQuery> queries = <CrmCustomerQuery>[];
  final List<({List<int> ids, String tagName, String requestId})> batchTags =
      <({List<int> ids, String tagName, String requestId})>[];
  final List<({String name, CrmSegmentFilter filter, String requestId})>
  savedSegments = <({String name, CrmSegmentFilter filter, String requestId})>[];
  final List<({int segmentId, String channel})> previews =
      <({int segmentId, String channel})>[];
  final List<
    ({
      int segmentId,
      String channel,
      int? couponId,
      String title,
      String content,
      String requestId,
    })
  >
  creates =
      <
        ({
          int segmentId,
          String channel,
          int? couponId,
          String title,
          String content,
          String requestId,
        })
      >[];
  final List<int> dispatches = <int>[];
  final List<int> retries = <int>[];
  final List<int> details = <int>[];

  final List<CrmBroadcastPayload> broadcastPreviews = <CrmBroadcastPayload>[];
  final List<({CrmBroadcastPayload payload, String content, String requestId})>
  broadcasts =
      <({CrmBroadcastPayload payload, String content, String requestId})>[];

  void _maybeFail(String method) {
    final String? message = failures[method];
    if (message != null) throw MerchantCrmApiException(message);
  }

  @override
  Future<CrmCustomerPageData> customers(CrmCustomerQuery query) async {
    queries.add(query);
    _maybeFail('customers');
    return page;
  }

  /// 换明文号码(F15)。每次联系都会打这里 —— 列表里的号是脱敏号。
  final List<({int memberId, String purpose})> contacts =
      <({int memberId, String purpose})>[];
  String contactPhone = '13812341234';

  @override
  Future<String> revealContact(
    int customerMemberId, {
    required String purpose,
  }) async {
    contacts.add((memberId: customerMemberId, purpose: purpose));
    _maybeFail('revealContact');
    return contactPhone;
  }

  @override
  Future<void> batchTag({
    required List<int> customerMemberIds,
    required String tagName,
    String tagColor = kCrmBatchTagColor,
    required String requestId,
  }) async {
    batchTags.add(
      (ids: customerMemberIds, tagName: tagName, requestId: requestId),
    );
    _maybeFail('batchTag');
  }

  @override
  Future<List<CrmSavedSegment>> segments() async {
    _maybeFail('segments');
    return segmentRows;
  }

  @override
  Future<void> saveSegment({
    required String name,
    required CrmSegmentFilter filter,
    required String requestId,
  }) async {
    savedSegments.add((name: name, filter: filter, requestId: requestId));
    _maybeFail('saveSegment');
  }

  @override
  Future<List<CrmCoupon>> coupons() async {
    _maybeFail('coupons');
    return couponRows;
  }

  @override
  Future<CrmCampaignPreview> previewCampaign({
    required int segmentId,
    required String channel,
  }) async {
    previews.add((segmentId: segmentId, channel: channel));
    _maybeFail('previewCampaign');
    return preview;
  }

  @override
  Future<CrmCampaignTask> createCampaign({
    required int segmentId,
    required String channel,
    int? couponId,
    required String title,
    required String content,
    required String requestId,
  }) async {
    creates.add((
      segmentId: segmentId,
      channel: channel,
      couponId: couponId,
      title: title,
      content: content,
      requestId: requestId,
    ));
    _maybeFail('createCampaign');
    return task;
  }

  @override
  Future<CrmCampaignTask> dispatchCampaign(int campaignId) async {
    dispatches.add(campaignId);
    _maybeFail('dispatchCampaign');
    return task;
  }

  @override
  Future<List<CrmCampaignTask>> campaigns() async {
    _maybeFail('campaigns');
    return campaignRows;
  }

  @override
  Future<CrmBroadcastPreview> previewBroadcast(
    CrmBroadcastPayload payload,
  ) async {
    broadcastPreviews.add(payload);
    _maybeFail('previewBroadcast');
    return broadcastPreview;
  }

  @override
  Future<CrmBroadcastResult> sendBroadcast(
    CrmBroadcastPayload payload, {
    required String content,
    required String requestId,
  }) async {
    broadcasts.add((payload: payload, content: content, requestId: requestId));
    _maybeFail('sendBroadcast');
    return broadcastResult;
  }

  @override
  Future<CrmCampaignTask> campaignDetail(int campaignId) async {
    details.add(campaignId);
    _maybeFail('campaignDetail');
    return task;
  }

  @override
  Future<CrmCampaignTask> retryCampaign(int campaignId) async {
    retries.add(campaignId);
    _maybeFail('retryCampaign');
    return task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
