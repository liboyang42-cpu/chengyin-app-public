import 'dart:math';

import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/registration_cancellation_outcome.dart';
import '../models/activity.dart';
import '../models/registration_read_failure.dart';
import '../models/activity_publish.dart';

/// 活动接口。对齐后端 `ApiActivityController`(/api/activity)与
/// `ApiRegistrationController`(/api/registration)。
class ActivityApi {
  ActivityApi(this._client);
  final DioClient _client;

  /// 活动列表:`POST /api/activity/list`(表单参数)。
  /// isMy=0所有 / 1我发布的 / 2即将上线。后端 startPage 分页。
  /// 返回结构:AjaxResult.success(getDataTable(list)) → 列表在 data.rows。
  ///
  /// ⚠️ 日期/价格筛选**不发给后端**:`ApiActivityController.activityList` 签名只有
  /// is_my/keyword/category_id/sort_type/经纬度/schedule/product_type/sort/
  /// city_keyword/distance_meters,没有 min_price/start_date。小程序
  /// utils/discover-search.js 把 filters 标为「仅客户端消费」(void filters),
  /// 在取回 rows 后前端兜底过滤。这里因此只发后端认得的字段,过滤交给调用方
  /// (matchesDatePriceFilter)。
  Future<List<Activity>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    String? sortType,
    String? longitude,
    String? latitude,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/list',
      data: FormData.fromMap(<String, dynamic>{
        'is_my': isMy.toString(),
        'keyword': ?keyword,
        'category_id': ?categoryId,
        'sort_type': ?sortType,
        'longitude': ?longitude,
        'latitude': ?latitude,
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = body['data'];
    final rows =
        (data is Map<String, dynamic>
            ? data['rows'] as List<dynamic>?
            : null) ??
        (body['rows'] as List<dynamic>?) ??
        <dynamic>[];
    return rows
        .map((dynamic e) => Activity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 活动详情:`POST /api/activity/info`(表单参数 id)。
  /// 返回 AjaxResult.success(activityInfoVO) → 对象在 data。
  Future<ActivityDetail> info(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ActivityDetail.fromJson(data);
  }

  /// 评价活动：与小程序一样走 `/api/comment/add`，`owner_type=2`。
  Future<void> addReview({
    required int activityId,
    required int rating,
    required String contents,
  }) async {
    if (rating < 1 || rating > 5 || contents.trim().isEmpty) {
      throw ArgumentError('评分和评价内容不能为空');
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/add',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '2',
        'owner_id': activityId.toString(),
        'rating': rating.toString(),
        'contents': contents.trim(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '评价失败');
    }
  }

  /// 我报名的活动:`POST /api/registration/my-joined`。
  /// 返回 AjaxResult.success(`List<CmsRegistration>`) → data 直接是 List。
  /// 后端聚合了主题+活动,这里只保留活动(ownerType==2)。
  Future<List<MyRegistration>> myJoined() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/my-joined',
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return data
        .map((dynamic e) => MyRegistration.fromJson(e as Map<String, dynamic>))
        .where((MyRegistration r) => r.ownerType == 2)
        .toList();
  }

  /// 报名报价:`POST /api/registration/quote`。
  ///
  /// ★ 下单**之前**问后端「这单多少钱、能抵多少积分」。小程序报名页的费用明细
  ///   (票种价 / 订单金额 / 俱乐部权益 / 积分抵扣 / 总计)就是靠它算的;
  ///   App 此前**根本没调过**,所以既看不到明细,也用不了积分。
  ///
  /// 返回后端 `RegistrationQuoteResult`:payAmount / pointsUsed / pointsDeductYuan。
  Future<RegistrationQuote> quote({
    required int ownerId,
    int? ticketId,
    bool usePoints = false,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/quote',
      data: <String, dynamic>{
        'ownerType': 2,
        'ownerId': ownerId,
        'ticketId': ?ticketId,
        'isUsePoint': usePoints ? 1 : 0,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.quote, body, '没能取得报价');
    }
    return RegistrationQuote.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 创建活动报名:`POST /api/registration/create`(@RequestBody → JSON)。
  /// ownerType 固定 2(活动)。realName/phone 必填(后端 @NotBlank)。
  ///
  /// [appPay] 为 true 时带 payChannel=APP,后端直接返回 App 支付六元组。
  /// ★ 渠道必须在建单时定:同一个 outTradeNo 在微信侧只能对应一种
  ///   trade_type,建完 JSAPI 单再改走 App 会被拒。
  ///
  /// 成功返回 [RegistrationCreateResult];非 200 抛异常(携带后端 msg)。
  Future<RegistrationCreateResult> createRegistration({
    required int ownerId,
    required String realName,
    required String phone,
    int? ticketId,
    String? email,
    String? participateDate,
    bool appPay = true,
    String? requestId,
    bool usePoints = false,
    required String quoteSign,
    int? waitlistOfferId,
    String? waitlistOfferToken,
  }) async {
    final bool hasWaitlistOfferId = waitlistOfferId != null;
    final bool hasWaitlistOfferToken =
        waitlistOfferToken != null && waitlistOfferToken.isNotEmpty;
    if (hasWaitlistOfferId != hasWaitlistOfferToken ||
        (waitlistOfferId != null && waitlistOfferId <= 0)) {
      throw ArgumentError('waitlist offer id/token 必须成对传入');
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/create',
      data: <String, dynamic>{
        'ownerType': 2,
        'ownerId': ownerId,
        'realName': realName,
        'phone': phone,
        // ★ 此前这里**写死 0**,于是 App 用户的积分永远用不上 —— 而后端一直支持。
        //   小程序报名页有「积分抵扣」开关(baoming.wxml:78-84),App 之前连费用明细都没有。
        'isUsePoint': usePoints ? 1 : 0,
        // ★ 建单硬闸:RegistrationOrderCreateGateImpl:37 对 ownerType=2 空签名直接 400。
        //   必须先调 quote() 拿到签名再来建单,不能省。
        'quoteSign': quoteSign,
        'ticketId': ?ticketId,
        if (appPay) 'payChannel': 'APP',
        // 幂等标识:重复提交同一个 requestId 后端按同一单处理,
        // 不传等于放弃幂等保护(重复点会建出两张票)。
        'requestId': requestId ?? newRequestId(),
        if (hasWaitlistOfferId) 'waitlistOfferId': waitlistOfferId,
        if (hasWaitlistOfferToken) 'waitlistOfferToken': waitlistOfferToken,
        if (email != null && email.isNotEmpty) 'email': email,
        if (participateDate != null && participateDate.isNotEmpty)
          'participateDate': participateDate,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    final code = body['code'];
    if (code != 200) {
      throw RegistrationCheckoutException(
        _ajaxCodeOf(code),
        (body['msg'] as String?) ?? '报名失败',
        hasServerMessage: body['msg'] is String,
      );
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return RegistrationCreateResult.fromJson(data);
  }

  /// 对已存在的待支付报名单重新取 App 支付参数:
  /// `POST /api/registration/pay/app`。
  /// 取消报名。**未支付与已支付走两个不同的接口**,这是后端契约不是可选项:
  ///   · 未支付(registrationStatus != 2)→ `/api/registration/cancel`
  ///     只释放库存与已抵扣积分,没有钱要退。
  ///   · 已支付(== 2)→ `/api/registration/cancel-refund`
  ///     成团前可退,现金原路退回、失败兜底退余额、积分返还
  ///     (ApiRegistrationController:288)。
  ///
  /// ★ 判据取自小程序侧同一条:`Number(status) === 2 ? cancel-refund : cancel`
  ///   (xcx tests/unit/requestbody-dynamic-url.test.js 把它锁死了)。
  ///   走错接口的后果不对称:已支付却调 cancel,票没了钱不退。
  ///
  /// 返回后端下发的提示原文 —— 退款到账时效那句是后端写的,前端别自己编。
  /// Compatibility caller: preserve supplied message, never fabricate payout success.
  Future<String> cancelRegistration({required int registrationId, required bool paid}) async {
    final outcome = await cancelRegistrationWithOutcome(registrationId: registrationId, paid: paid);
    return outcome.message.isNotEmpty ? outcome.message : '取消结果尚未确认，请查看订单';
  }

  Future<RegistrationCancellationOutcome> cancelRegistrationWithOutcome({
    required int registrationId,
    required bool paid,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      paid ? '/api/registration/cancel-refund' : '/api/registration/cancel',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'id': registrationId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.cancellation, body, '取消失败');
    }
    return RegistrationCancellationOutcome.fromResponse(body);
  }

  /// 支付服务是否就绪:`POST /api/registration/payment-readiness`。
  ///
  /// ★ 它查的是**服务端的微信支付配置是否可用**
  ///   (RegistrationCheckoutServiceImpl:57 → `wechatPayService.isReady()`)。
  ///   小程序在支付前会先问这条;App 此前**不问**,于是配置没就绪时用户
  ///   点了「继续支付」才撞失败,而失败信息通常很底层、看不出是配置问题。
  ///
  /// ⚠️ 这是**软探测**:不 ready 不等于必然失败,只是概率很高。
  ///   所以拿它做**提示**(告诉用户现在支付通道有问题),
  ///   **不要拿它当硬闸**去禁掉支付按钮 —— 探测本身也可能失败,
  ///   把一条正常的支付路径堵死比让它去试一次更糟。
  Future<({bool ready, String message})> paymentReadiness() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/payment-readiness',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.paymentReadiness, body, '查询失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return (
      ready: data['ready'] == true,
      message: (data['message'] as String?) ?? '',
    );
  }

  Future<Map<String, String>> payApp(int registrationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/pay/app',
      data: FormData.fromMap(<String, dynamic>{
        'id': registrationId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationCheckoutException(
        _ajaxCodeOf(body['code']),
        (body['msg'] as String?) ?? '获取支付参数失败',
        hasServerMessage: body['msg'] is String,
      );
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final raw = data['payParams'];
    if (raw is! Map || raw.isEmpty) {
      throw const RegistrationReadFailure(RegistrationReadKind.paymentParameters, '没能取得支付参数,请稍后重试', hasServerMessage: false);
    }
    return raw.map((k, v) => MapEntry('$k', '${v ?? ''}'));
  }

  /// 商家扫玩家动态核销码:`POST /api/registration/scan_dynamic_code`。
  ///
  /// ★ A1 裁决:履约完成由**商家扫玩家动态码**坐实,这是商家拿到的唯一硬证据。
  /// ★ 服务端对码做 HMAC 验签,type 从码里取,**不接受客户端回传 type** ——
  ///   所以这里只传 code,不要"顺手"把类型也传上去。
  ///
  /// 成功返回后端下发的 data(含 redemptionId / chapterId);
  /// 失败抛异常并携带后端原因(码无效/已过期/已核销/无权限等),原样展示。
  Future<Map<String, dynamic>> scanDynamicCode(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/scan_dynamic_code',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw Exception((body['msg'] as String?) ?? '核销失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 幂等标识。后端只要求非空且 ≤64 字符。
  static String newRequestId() =>
      'app-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32)}';

  static final Random _rng = Random();

  /// 票夹列表:`POST /api/registration/list`(owner_type=2 活动票)。
  /// ⚠️ 后端在 ownerType<3 时**强制** registrationStatus=2(已支付),
  /// 所以这里天然只返回已支付的票 —— 正是票夹语义,不必再传 status。
  /// 返回 AjaxResult.success(`List<CmsRegistration>`) → data 直接是 List。
  /// 非 200 抛后端 msg(真源 `signup/index.js` getActivityList:业务失败
  /// 必须进 error 态,不许把错误伪装成空列表)。[fallbackMsg] = 后端没给
  /// msg 时的兜底,与真源 getRequestErrorMessage 的分支兜底同字。
  Future<List<MyRegistration>> ticketList({
    int? isOnline,
    String fallbackMsg = '活动票加载失败',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/list',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '2',
        'is_online': ?isOnline?.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.activityTickets, body, fallbackMsg);
    }
    final data = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return data
        .map((dynamic e) => MyRegistration.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 漫游起始页的已报名主题卡 / 票夹的路线票。与小程序相同，使用 owner_type=1，
  /// 后端会只返回已支付记录；活动实例存在时优先进入实例游玩。
  Future<List<MyRegistration>> topicTicketList({
    String fallbackMsg = '没能取得已报名主题',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/list',
      data: FormData.fromMap(<String, dynamic>{'owner_type': '1'}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.routeTickets, body, fallbackMsg);
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List<dynamic>
        ? data
        : data is Map<String, dynamic>
        ? (data['rows'] as List<dynamic>? ?? const <dynamic>[])
        : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(MyRegistration.fromJson)
        .toList(growable: false);
  }

  /// 我的订单:`POST /api/registration/list`(owner_type=3 全部)。
  ///
  /// ★ 与票夹(owner_type=2)的关键区别:后端对 owner_type<3 会**强制**
  ///   registrationStatus=2,只返回已支付的;**只有 owner_type=3 才能看到
  ///   待支付单**。没有这个入口,用户取消支付后就再也找不到订单,只能重新
  ///   报名建新单 —— 可能重复付款。
  ///
  /// [status] 0/null 全部 · 1 待支付 · 2 待使用 · 3 已完成 · 4 已取消。
  /// owner_type=3 会同时返回主题票(ownerType=1)与活动票(ownerType=2),
  /// 我的订单与小程序一样展示全部类型。
  Future<List<MyRegistration>> orderList({String? status}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/list',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '3',
        'status': ?status,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.orders, body, '订单加载失败');
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List<dynamic>
        ? data
        : data is Map<String, dynamic>
        ? (data['rows'] as List<dynamic>? ?? const <dynamic>[])
        : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(MyRegistration.fromJson)
        .where((MyRegistration r) => r.shouldShowInApp)
        .toList();
  }

  /// 票卡详情:`POST /api/registration/info`(表单参数 id)。
  /// ③ 探索票会带 entitlements(哪几章待核销/已核销/已失效)。
  Future<RegistrationDetail> ticketInfo(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.detail, body, '票券详情加载失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return RegistrationDetail.fromJson(data);
  }

  /// 签发动态核销码:`POST /api/verify/dyncode/issue`(玩家出码,商家扫)。
  /// 归 ActivityApi 是因为它只服务票券链路,复用同一个 DioClient;
  /// 路径属于 `/api/verify` 而非 `/api/registration`,勿按前缀找。
  ///
  /// 后端会拒:未登录 / 非本人票 / registrationStatus!=2 / 该票已核销完。
  /// 失败一律抛出携带后端 msg 的异常,不静默返回空码。
  Future<DynCode> issueDynamicCode(int registrationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/verify/dyncode/issue',
      data: FormData.fromMap(<String, dynamic>{
        'registrationId': registrationId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RegistrationReadFailure.fromResponse(RegistrationReadKind.dynamicCode, body, '核销码签发失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DynCode.fromJson(data);
  }

  /// 发布活动:`POST /api/activity/publish`(JSON body)。
  ///
  /// ⚠️ 后端四道闸(ApiActivityController:633-660):
  ///   ① 登录 ② **仅俱乐部主理人可发布活动** ③ 配额 ④ 内容安全审核
  ///   后两条只能等后端回 —— 抛 [ActivityPublishException] 并标出类型,
  ///   让页面决定给不给重试(配额与内容被拒都**不该给重试**)。
  Future<void> publishActivity(ActivityPublishForm form) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/publish',
      data: form.toJson(),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw ActivityPublishException((body['msg'] as String?) ?? '发布失败');
    }
  }

  /// 活动点赞 / 取消:`POST /api/activity/like`(**切换式**)。
  ///
  /// ⚠️ 后端还收一个 `type`(「类型 1点赞」),缺省即 1 —— 不传就是点赞,
  ///   这里不传,免得把一个语义不明的参数固化进客户端。
  Future<String> toggleLike(int activityId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/like',
      data: FormData.fromMap(<String, dynamic>{'id': activityId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
    return (body['msg'] as String?) ?? '已更新';
  }

  /// 取消活动(全额退款给所有已报名用户):`POST /api/activity/cancel`。
  ///
  /// ★★ **成功返回的那句话必须原样显示给主办方**,别自己写一句"已取消"。
  ///   后端在这句话里区分了三种情况,而且注释写明了为什么不能合并:
  ///     · 有自动退的  → 「已为 N 笔订单全额退款(原路退回,预计1-3个工作日)」
  ///     · 一笔没退的  → 「无可自动退款的已付款报名」
  ///     · 含已核销票  → 追加「另有 M 笔订单含已核销的票,无法自动退款,平台将人工跟进」
  ///
  ///   ⚠️ 后端注释原话:**else 分支不能写「无已付款报名」** ——
  ///     全部单都含已核销票被跳过时 refundedOrders=0,那句话是假的:
  ///     明明有已付款报名,只是一笔都没自动退。
  ///     ⇒ 前端更不能自己造这句话。
  ///
  /// ⚠️ reason 必填且会**展示给已报名用户**,后端空值直接拒。
  Future<String> cancelActivity({
    required int activityId,
    required String reason,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/cancel',
      data: FormData.fromMap(<String, dynamic>{
        'id': activityId.toString(),
        'reason': reason,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '取消失败');
    }
    // ★ data 里才是那句长文案(后端 `AjaxResult.success(msg.toString())`
    //   把它放在 msg 位;RuoYi 的 success(String) 是设 msg)。
    return (body['msg'] as String?) ?? '活动已取消';
  }

  /// 取消活动前预览:`POST /api/activity/cancel_preview`(表单 id / scope)。
  ///
  /// 返回**将被全额退款的已付款玩家人数** —— N 由服务端按与取消同一套授权算,
  /// 前端不自己从报名数推(报名 ≠ 已付款,还有已核销的票)。
  /// ⚠️ 9-18 拍板:确认框必须写明「将给 N 位已付款玩家全额退款」。
  ///   拿不到 N 就**不弹确认、不发取消** —— 失败原文向上抛给调用方 toast。
  Future<int> cancelPreview({required int activityId, String? scope}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/cancel_preview',
      data: FormData.fromMap(<String, dynamic>{
        'id': activityId.toString(),
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      }),
    );
    return _paidPlayersOf(resp.data);
  }

  /// 预览回包 → 已付款人数。后端把人数放在 `data.paidPlayers`。
  /// 解析不出口径宁可抛错,也不返回 0 —— 「将给 0 位玩家退款」是句假话。
  static int _paidPlayersOf(Map<String, dynamic>? body) {
    final Object? code = body?['code'];
    if (code is! num || code.toInt() != 200) {
      throw Exception((body?['msg'] as String?) ?? '暂时算不出退款人数，请稍后重试');
    }
    final Object? data = body?['data'];
    final Object? raw = data is Map<String, dynamic>
        ? data['paidPlayers']
        : null;
    final int? n = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '');
    if (n == null || n < 0) {
      throw Exception((body?['msg'] as String?) ?? '暂时算不出退款人数，请稍后重试');
    }
    return n;
  }

  /// 我赞过的活动:`POST /api/activity/like_list`。
  Future<List<Activity>> likedActivities() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/like_list',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Activity.fromJson)
        .toList();
  }
}

/// 活动发布失败。区分「不该重试」的三类。
class ActivityPublishException implements Exception {
  ActivityPublishException(this.message);
  final String message;

  /// 不是俱乐部主理人 —— 身份问题,重试无用。
  bool get isNotClubLeader => message.contains('仅俱乐部主理人');

  /// 配额用尽 —— 重试无用,要等下个周期或升级。
  bool get isQuotaExceeded =>
      message.contains('配额') ||
      message.contains('上限') ||
      message.contains('额度');

  /// 内容被审核拒 —— 要改文字。★ 先排除明确的故障词。
  bool get isContentRejected {
    if (message.contains('网络') || message.contains('稍后重试')) return false;
    return const <String>['违规', '敏感', '不合规', '含有'].any(message.contains);
  }

  bool get retryable =>
      !isNotClubLeader && !isQuotaExceeded && !isContentRejected;

  @override
  String toString() => message;
}

/// AjaxResult 的 code 有时是字符串(`'409'`),宽松取整数,取不到给 null。
int? _ajaxCodeOf(Object? code) =>
    code is num ? code.toInt() : int.tryParse('${code ?? ''}');

/// 报名/结算接口非 200 的业务异常 —— 带后端业务 code 上来。
///
/// 结算链要靠它判 410(过期待支付单)/409 终态冲突(拍板 #21:自动换幂等键
/// 重建一次)。裸 `Exception(msg)` 会把 code 丢掉,页面只能对着文案猜。
///
/// ★ `toString()` 与 `Exception: msg` 同形:各调用点现有的
///   `e.toString().replaceFirst('Exception: ', '')` 文案收口一行都不用改。
class RegistrationCheckoutException implements Exception {
  const RegistrationCheckoutException(this.code, this.message, {this.hasServerMessage = true});

  final bool hasServerMessage;

  final int? code;
  final String message;

  @override
  String toString() => 'Exception: $message';
}
