import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';

final merchantPredictApiProvider = Provider<MerchantPredictApi>((ref) {
  return MerchantPredictApi(ref.watch(dioClientProvider));
});

/// 消息页那条「竞猜待答」入口要不要露。
///
/// 对齐小程序 `subpackageB/pages/im/list/index.js:loadMerchantEntry`:
/// **问的是身份,不是待办条数** —— 待办拉不到(没权限/网络失败)都不该让这一行
/// 消失或乱出现,所以失败一律按「不露」处理(小程序 `fail` 分支同款)。
///
/// ⚠️ 不在这里拉待办列表:那会把「不是商家」这个正常回执静默吞掉。
final merchantCanSettlePredictProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  try {
    final Map<String, dynamic> access = await ref
        .read(pageParityApiProvider)
        .merchantAccess();
    return access['active'] == true && access['canManageProjects'] == true;
  } catch (_) {
    return false;
  }
});

/// 竞猜待答(商家侧)。对齐小程序 `pages/merchant/predict/index`。
///
/// 只有两个业务端点:列 `inbox`、结 `settle`。能不能结算由
/// `/api/merchant/access/me` 的 `merchant:project:manage` 下发
/// (结算发券,后端要的就是项目管理权限),本客户端不猜。
class MerchantPredictApi {
  MerchantPredictApi(this._client);

  final DioClient _client;

  /// 待答列表:`POST /api/merchant/predict/inbox`。
  ///
  /// `data` 是数组本体(小程序 `res.data.map(shapeRound)`),不是分页包。
  Future<List<Map<String, dynamic>>> inbox() async {
    final Map<String, dynamic> body = await _postJson(
      '/api/merchant/predict/inbox',
      const <String, dynamic>{},
    );
    _ensureOk(body);
    final Object? data = body['data'];
    if (data is! List) {
      throw const MerchantPredictApiException('待答列表回执不完整', localCode: 'incomplete');
    }
    return data
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// 公布答案并结算:`POST /api/merchant/predict/settle` → 猜中人数。
  ///
  /// ⚠️ 一轮只能结一次,而且会按商家配的规则发券 —— 调用方必须先二次确认;
  ///   失败要**留在原地**让人能再试,不许把「没结成功」当成结过把卡片拿掉。
  Future<int> settle({
    required int nodeId,
    required String playDay,
    required String settledOption,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/merchant/predict/settle',
      <String, dynamic>{
        // 小程序里 nodeId 是 String(nodeId + ':' + playDay 拼 rid 时被字串化),
        // 原样发字符串,别自作主张转数字。
        'nodeId': '$nodeId',
        'playDay': playDay,
        'settledOption': settledOption,
      },
    );
    _ensureOk(body);
    final Object? data = body['data'];
    final Object? winners = data is Map ? data['winners'] : null;
    if (winners is num) return winners.toInt();
    return int.tryParse('${winners ?? ''}'.trim()) ?? 0;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final Response<Map<String, dynamic>> resp = await _client.dio
          .post<Map<String, dynamic>>(path, data: payload);
      return resp.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final Object? rawCode = body['code'];
    final int? code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse('${rawCode ?? ''}');
    if (code != 200) {
      throw MerchantPredictApiException(
        '${body['msg'] ?? '请求失败'}',
        code: code,
        localCode: body['msg'] == null ? 'request' : null,
      );
    }
  }

  MerchantPredictApiException _fromDio(DioException error) {
    final int? status = error.response?.statusCode;
    final Object? data = error.response?.data;
    final String? msg = data is Map && data['msg'] != null
        ? '${data['msg']}'
        : null;
    final bool noResponse =
        error.response == null ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
    return MerchantPredictApiException(
      msg ??
          (noResponse
              ? '网络连接失败，请稍后重试'
              : '请求失败${status == null ? '' : '（$status）'}'),
      code: status,
      localCode: msg == null ? (noResponse ? 'network' : 'http') : null,
      networkUnreachable: noResponse,
      outcomeUnknown: noResponse || (status != null && status >= 500),
    );
  }
}

class MerchantPredictApiException implements Exception {
  const MerchantPredictApiException(
    this.message, {
    this.code,
    this.localCode,
    this.networkUnreachable = false,
    this.outcomeUnknown = false,
  });

  final String message;
  final int? code;
  final String? localCode;
  final bool networkUnreachable;

  /// 结果未确认:请求可能已被服务端受理(结算只此一次,不许自动重试)。
  final bool outcomeUnknown;

  @override
  String toString() => message;
}
