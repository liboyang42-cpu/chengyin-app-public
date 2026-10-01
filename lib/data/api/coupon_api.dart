import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/coupon.dart';

/// 券已停用/被撤销(后端业务码 410)——**终态,不是可重试故障**。
/// 真源 `scene-qr-coupon` 收到 410 会停轮询、停倒计时、撤码;
/// 混在普通 Exception 里页面无法分辨「再试一次」和「别再试了」。
class CouponUnavailableException implements Exception {
  const CouponUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Provenance for merchant-side messages created locally, not by the server.
enum CouponLocalFailureKind { load, publish, stop }

class CouponLocalFailure implements Exception {
  const CouponLocalFailure(this.kind, this.message);
  final CouponLocalFailureKind kind;
  final String message;
  @override
  String toString() => 'Exception: $message';
}

class CouponPublishReceipt {
  const CouponPublishReceipt({required this.message, this.hasLocalMessage = false});
  final String message;
  final bool hasLocalMessage;
}

/// 优惠券接口(对齐后端 ApiCouponController)。
class CouponApi {
  CouponApi(this._client);
  final DioClient _client;

  static int? _bodyCode(Map<String, dynamic> body) =>
      (body['code'] as num?)?.toInt();

  /// 我领取的券:`POST /api/coupon/myrecvlist`(需登录)。
  /// 参数 keyword 可空;后端 success(`List<ViewCouponHistory>`),data 直接是 List。
  Future<List<CouponRecord>> myReceivedList({String? keyword}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/myrecvlist',
      data: FormData.fromMap(<String, dynamic>{
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '未登录或会话已过期').toString());
    }
    final rows = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => CouponRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 我发布的券(商家侧):`POST /api/coupon/mypublishlist`。
  ///
  /// ★ 此前 App 只有玩家侧(领券/出示码),商家**发了券之后看不到自己发过什么**。
  ///
  /// ⚠️ 后端 `myPublishCouponList` 返回的是**券模板**(`List<SmsCoupon>`:
  ///   name/publishCount/receiveCount/useCount/status),不是 `myrecvlist` 那种
  ///   单张核销记录(`ViewCouponHistory`:couponCode/useStatus)——两条字段完全不同,
  ///   **不能**共用 [CouponRecord]。原样带 Map 出去,由页面按券模板的字段读。
  Future<List<Map<String, dynamic>>> myPublishedList({String? keyword}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/mypublishlist',
      data: FormData.fromMap(<String, dynamic>{
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      if (body['msg'] == null) {
        throw const CouponLocalFailure(CouponLocalFailureKind.load, '加载失败');
      }
      throw Exception(body['msg'].toString());
    }
    final rows = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  /// 发布一张券(商家侧):`POST /api/coupon/publish`(JSON body)。
  ///
  /// ⚠️ 后端有**两道闸**,失败原因要原样透传给用户,不能笼统说「发布失败」:
  ///   ① RBAC 配额:按角色限制「同时存在」的券数量 —— 提示是「你还能发几张」
  ///      这类可执行信息,吞掉的话用户不知道该去下架旧券;
  ///   ② 发券防重(Redis SETNX,商家+类型+分钟粒度)—— 连点会回
  ///      「发券太频繁,请稍后再试」,那是**保护不是错误**,别引导用户去改表单。
  ///
  /// ⚠️ 时间传 ISO8601 字符串;后端是 `Date`,秒级即可。
  Future<String> publish({
    required String name,
    required DateTime startTime,
    required DateTime endTime,
    required int publishCount,
    required int couponType,
    String? description,
  }) async {
    return (await publishWithReceipt(
      name: name, startTime: startTime, endTime: endTime,
      publishCount: publishCount, couponType: couponType, description: description,
    )).message;
  }

  /// Additive receipt API keeps local fallback provenance for localized views.
  Future<CouponPublishReceipt> publishWithReceipt({
    required String name,
    required DateTime startTime,
    required DateTime endTime,
    required int publishCount,
    required int couponType,
    String? description,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/publish',
      data: <String, dynamic>{
        'name': name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'publishCount': publishCount,
        'couponType': couponType,
        if (description != null && description.isNotEmpty)
          'description': description,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      if (body['msg'] == null) {
        throw const CouponLocalFailure(CouponLocalFailureKind.publish, '发布失败');
      }
      throw Exception(body['msg'].toString());
    }
    return CouponPublishReceipt(
      message: (body['msg'] as String?) ?? '已发布',
      hasLocalMessage: body['msg'] == null,
    );
  }

  /// 停发自己的券(商家侧):`POST /api/coupon/stop`(表单 couponId)。
  ///
  /// ★ 真源 `subpackageMember/coupon/coupon.js:163-195`:
  ///   二次确认(不可撤销)→ 停发 → **成功回读列表**。
  ///   只停「新增发放/领取」,已领到的券照常可用、可核销 —— 后端按
  ///   `status in (0,1)` CAS,所以入口只在未开始/进行中时才摆。
  Future<void> stop(int couponId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/stop',
      data: FormData.fromMap(<String, dynamic>{
        'couponId': couponId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      if (body['msg'] == null) {
        throw const CouponLocalFailure(CouponLocalFailureKind.stop, '停发失败，请稍后重试');
      }
      throw Exception(body['msg'].toString());
    }
  }

  /// 核销一张券(商家侧):`POST /api/coupon/verification`。
  ///
  /// ★ 后端**同时兼容**两种码,且有明确优先级(ApiCouponController:283-300):
  ///   ① 动态 token(60s 时效,`/qr-token` 签发)—— 优先;
  ///   ② 扫码器可能把 token 塞进 code 字段 —— 后端会再拿 code 当 token 试一次;
  ///   ③ 都不是才回落成旧的静态 couponCode。
  ///
  /// 所以**扫到什么就原样传什么**,前端不要自作聪明判断「这看起来像 token 还是 code」——
  /// 判错了会把一张能核销的券挡在门外。这里统一走 `code` 交给后端分辨。
  ///
  /// ⚠️ token 过期后端回「二维码已过期,请刷新后重试」——
  ///   那是**让用户刷新**,不是核销失败,提示要原样透传。
  Future<String> verify(String scanned) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/verification',
      data: FormData.fromMap(<String, dynamic>{'code': scanned}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '核销失败').toString());
    }
    return (body['msg'] as String?) ?? '核销成功';
  }

  /// 签发动态二维码:`POST /api/coupon/qr-token`。
  /// 60s 时效 token,前端倒计时自动刷新;响应附带券展示信息(名称/描述),省一次查询。
  Future<CouponQr> qrToken(int couponHistoryId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/qr-token',
      data: FormData.fromMap(<String, dynamic>{
        'couponHistoryId': couponHistoryId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_bodyCode(body) == 410) {
      throw CouponUnavailableException((body['msg'] ?? '').toString());
    }
    if (_bodyCode(body) != 200) {
      throw Exception((body['msg'] ?? '出码失败').toString());
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CouponQr.fromJson(data);
  }

  /// 核销状态轮询:`POST /api/coupon/status`。出示页每 5s 拉一次。
  Future<CouponStatus> status(int couponHistoryId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/status',
      data: FormData.fromMap(<String, dynamic>{
        'couponHistoryId': couponHistoryId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_bodyCode(body) == 410) {
      throw CouponUnavailableException((body['msg'] ?? '').toString());
    }
    if (_bodyCode(body) != 200) {
      throw Exception((body['msg'] ?? '核销状态获取失败').toString());
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CouponStatus.fromJson(data);
  }

  /// 停发自己的券:`POST /api/coupon/stop`(表单 `couponId`)。
  ///
  /// ★ 只停**新增**发放/领取:已领到的券照常可用、可核销 —— 与后端 CAS 的
  ///   `status in (0,1)` 同一口径(小程序 `canStop(status)` 也是这两档)。
  /// ★ 归属校验在后端(不是本人的券回「无权停发该优惠券」),前端不自己判
  ///   「这张是不是我的」—— 列表回执里的 `status` 只决定摆不摆入口。
  Future<void> stopIssuing(int couponId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/coupon/stop',
      data: FormData.fromMap(<String, dynamic>{'couponId': couponId}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      if (body['msg'] == null) {
        throw const CouponLocalFailure(CouponLocalFailureKind.stop, '停发失败，请稍后重试');
      }
      throw Exception(body['msg'].toString());
    }
  }
}
