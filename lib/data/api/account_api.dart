import '../models/account_local_failure.dart';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../models/consent_record.dart';
import '../models/deregistration.dart';

/// 账号注销 + 合规同意。
///
/// 对齐后端 `ApiAccountDeregistrationController`(/api/user/deregister)与
/// `ApiComplianceController`(/api/compliance)。
///
/// ★ 苹果 Guideline 5.1.1(v):支持账号创建的 App 必须提供 App 内删除账号入口,
///   没有会被拒审。后端四个接口早已具备,此前 App 侧完全没接。
///
/// ⚠️ apply 前后端各有一道闸,顺序不能颠倒:
///   ① 必须先有 account_cancellation_notice / account_cancel 的 AGREE 记录,
///     且 docVersion 等于服务端当前版本(服务端用 versionOf 现算,客户端不传版本);
///   ② 必须绑定手机号并通过短信验证码;
///   ③ requestId 幂等,≤64 字符。
class AccountApi {
  AccountApi(this._client);
  final DioClient _client;

  static const String _cancelDocType = 'account_cancellation_notice';
  static const String _cancelScene = 'account_cancel';

  /// 报名信息向主办方提供的单独同意。
  /// ★ 后端 /api/registration 的 **create / pay / pay/app 三个入口都查这条**,
  ///   没有当前版本的 AGREE 记录一律拒 —— 所以它是报名与支付的前置,
  ///   不是可选的合规装饰。
  static const String signupDocType = 'activity_host_data_sharing';
  static const String signupScene = 'activity_signup';
  static const String merchantOnsiteDocType = 'merchant_onsite_data_sharing';
  static const String merchantOnsiteScene = 'merchant_redeem';
  static const String merchantScopeType = 'MERCHANT';
  static const String roamLocationDocType = 'privacy_policy';
  static const String roamLocationScene = 'roam_location';
  static final Random _rng = Random();

  /// 幂等标识。后端只要求「非空且 ≤64 字符」,不校验格式,
  /// 故用「微秒时间戳 + 随机数」即可,不为此引入 uuid 直接依赖。
  static String newRequestId() =>
      'app-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32)}';

  Map<String, dynamic> _body(Response<Map<String, dynamic>> resp) {
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw Exception((body['msg'] as String?) ?? '请求失败');
    }
    return body;
  }

  /// 当前登录玩家的永久小程序码:`POST /api/user/player-code`。
  ///
  /// 后端会生成或复用已存储的玩家身份码，App 只展示服务端
  /// 返回的 `data.qr`；缺失或空值不用占位图伪造成功。
  Future<String> playerCode() async {
    final Response<Map<String, dynamic>> resp = await _client.dio
        .post<Map<String, dynamic>>('/api/user/player-code');
    final Map<String, dynamic> body = _body(resp);
    final Object? data = body['data'];
    final Object? value = data is Map<String, dynamic> ? data['qr'] : null;
    final String qr = value is String ? value.trim() : '';
    if (qr.isEmpty) {
      throw const AccountLocalFailure(AccountLocalFailureKind.playerCode, '个人码暂不可用，请稍后重试');
    }
    return qr;
  }

  /// 查询注销状态:`GET /api/user/deregister/status`。
  /// 无在途申请时后端返回 status=NORMAL。
  Future<DeregistrationStatus> deregisterStatus() async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/user/deregister/status',
    );
    final data =
        (_body(resp)['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DeregistrationStatus.fromJson(data);
  }

  /// 注销前置条件检查:`POST /api/user/deregister/precheck`。
  /// 返回 BLOCKED 时 blockers 非空,应原样展示给用户。
  Future<DeregistrationStatus> deregisterPrecheck() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/deregister/precheck',
    );
    final data =
        (_body(resp)['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DeregistrationStatus.fromJson(data);
  }

  /// 查询某协议场景的**最新同意状态**:`POST /api/compliance/consents/latest`。
  ///
  /// ★ 又一处「只写不读」:App 能**提交**同意,但读不回**已经同意过什么**。
  ///   于是每次进到需要同意的场景都只能重新弹一次 ——
  ///   用户明明签过了,还要再签;而合规上真正要的是「这个人在哪个版本上同意过」。
  ///
  /// ★ **`success()` 不带 data 表示「没同意过」**,不是错误
  ///   (ApiComplianceController:~128)。判据是 data 有没有,不是 code。
  ///   把它当失败弹红字,会让用户以为系统坏了。
  ///
  /// ⚠️ `docVersion` 由服务端给,**客户端不传也不猜** —— 与提交那条同一条纪律:
  ///   客户端猜的版本一旦与服务端不符,后端会判定「未同意」。
  ///   所以比对版本也交给服务端,前端只问「最新的那条是什么」。
  Future<ConsentRecord?> latestConsent({
    required String docType,
    required String scene,
    String? scopeType,
    int? scopeId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/compliance/consents/latest',
      data: <String, dynamic>{
        'docType': docType,
        'scene': scene,
        'scopeType': ?scopeType,
        'scopeId': ?scopeId,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '授权状态暂不可用');
    }
    final Object? data = body['data'];
    // ★ 无 data = 没同意过。这是**正常态**,返回 null 而不是抛。
    if (data is! Map<String, dynamic> || data.isEmpty) return null;
    return ConsentRecord.fromJson(data);
  }

  /// 记录一条同意:`POST /api/compliance/consents`。
  /// docVersion 由服务端按 docType 现算,客户端不传也不猜 ——
  /// 传了也会被忽略,而且客户端猜的版本一旦与服务端不符,后端会判定「未同意」。
  Future<void> recordConsent({
    required String docType,
    required String scene,
    required String requestId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/compliance/consents',
      data: <String, dynamic>{
        'docType': docType,
        'scene': scene,
        'eventType': 'AGREE',
        'requestId': requestId,
      },
    );
    _body(resp);
  }

  /// 同意账号注销须知。
  Future<void> agreeCancellationNotice(String requestId) => recordConsent(
    docType: _cancelDocType,
    scene: _cancelScene,
    requestId: requestId,
  );

  /// 同意向主办方提供报名信息 —— 报名与支付的前置。
  Future<void> agreeSignupDataSharing(String requestId) => recordConsent(
    docType: signupDocType,
    scene: signupScene,
    requestId: requestId,
  );

  /// 当前门店现场信息授权的最新记录。范围只能来自服务端节点下发的 merchantId。
  Future<ConsentRecord?> latestMerchantOnsiteConsent(int merchantId) {
    if (merchantId <= 0) {
      throw ArgumentError.value(merchantId, 'merchantId', '必须为正整数');
    }
    return latestConsent(
      docType: merchantOnsiteDocType,
      scene: merchantOnsiteScene,
      scopeType: merchantScopeType,
      scopeId: merchantId,
    );
  }

  Future<ConsentRecord> agreeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) => _writeAndReadbackMerchantOnsiteConsent(
    merchantId: merchantId,
    eventType: 'AGREE',
    requestId: requestId,
  );

  Future<ConsentRecord> revokeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) => _writeAndReadbackMerchantOnsiteConsent(
    merchantId: merchantId,
    eventType: 'REVOKE',
    requestId: requestId,
  );

  /// 撤回漫游定位同意。POST 成功不等于撤回已生效，必须精确回读 REVOKE。
  Future<ConsentRecord> revokeRoamLocationConsent({
    required String requestId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/compliance/consents',
      data: <String, dynamic>{
        'docType': roamLocationDocType,
        'scene': roamLocationScene,
        'eventType': 'REVOKE',
        'requestId': requestId,
      },
    );
    _body(resp);

    final ConsentRecord? latest = await latestConsent(
      docType: roamLocationDocType,
      scene: roamLocationScene,
    );
    final bool matched =
        latest != null &&
        latest.docType == roamLocationDocType &&
        latest.scene == roamLocationScene &&
        latest.eventType == 'REVOKE' &&
        latest.scopeType == null &&
        latest.scopeId == null;
    if (!matched) {
      throw const AccountLocalFailure(AccountLocalFailureKind.roamRevocation, '漫游定位撤回状态未确认，请重试');
    }
    return latest;
  }

  /// 法律高风险写入必须由客户端再读 `/latest` 验证服务器最终状态。
  /// POST 成功本身不是授权成立；任何空记录、错事件或错范围都 fail closed。
  Future<ConsentRecord> _writeAndReadbackMerchantOnsiteConsent({
    required int merchantId,
    required String eventType,
    required String requestId,
  }) async {
    if (merchantId <= 0) {
      throw ArgumentError.value(merchantId, 'merchantId', '必须为正整数');
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/compliance/consents',
      data: <String, dynamic>{
        'docType': merchantOnsiteDocType,
        'scene': merchantOnsiteScene,
        'scopeType': merchantScopeType,
        'scopeId': merchantId,
        'eventType': eventType,
        'requestId': requestId,
      },
    );
    _body(resp);

    final ConsentRecord? latest = await latestMerchantOnsiteConsent(merchantId);
    final bool matched =
        latest != null &&
        latest.docType == merchantOnsiteDocType &&
        latest.scene == merchantOnsiteScene &&
        latest.scopeType == merchantScopeType &&
        latest.scopeId == merchantId &&
        latest.eventType == eventType;
    if (!matched) {
      throw const AccountLocalFailure(AccountLocalFailureKind.merchantConsent, '门店授权状态未确认，核销码未打开');
    }
    return latest;
  }

  /// 提交注销申请:`POST /api/user/deregister/apply`(需短信验证码)。
  /// 成功后进入冷静期,返回的 executeAfter 是到期执行时间。
  Future<DeregistrationStatus> deregisterApply({
    required String smscode,
    required String requestId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/deregister/apply',
      data: FormData.fromMap(<String, dynamic>{
        'smscode': smscode,
        'requestId': requestId,
      }),
    );
    final data =
        (_body(resp)['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DeregistrationStatus.fromJson(data);
  }

  /// 撤销冷静期内的注销申请:`POST /api/user/deregister/cancel`。
  Future<DeregistrationStatus> deregisterCancel() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/deregister/cancel',
    );
    final data =
        (_body(resp)['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DeregistrationStatus.fromJson(data);
  }
}

/// 定义在本文件而非 core/providers.dart:那个文件当前有未提交改动,
/// 不去纠缠它。Riverpod 不要求 provider 集中声明。
final accountApiProvider = Provider<AccountApi>((ref) {
  return AccountApi(ref.watch(dioClientProvider));
});
