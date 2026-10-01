import 'dart:collection';

import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/my_project.dart';

class MyProjectPage extends ListBase<MyProject> {
  MyProjectPage({required List<MyProject> rows, required this.total})
    : rows = List<MyProject>.unmodifiable(rows);

  final List<MyProject> rows;
  final int total;

  @override
  int get length => rows.length;

  @override
  set length(int value) => throw UnsupportedError('项目分页是只读的');

  @override
  MyProject operator [](int index) => rows[index];

  @override
  void operator []=(int index, MyProject value) =>
      throw UnsupportedError('项目分页是只读的');
}

/// 我发布的内容。对齐后端 `/api/project/my` 与三组业务各自的删除/上下架端点。
class MyProjectApi {
  MyProjectApi(this._client);
  final DioClient _client;

  /// 我发布的列表:`POST /api/project/my`。
  Future<List<MyProject>> list({
    String type = 'all',
    String state = 'all',
    String ownerType = 'all',
    String? scope,
    int pageSize = 200,
  }) => page(
    type: type,
    state: state,
    ownerType: ownerType,
    scope: scope,
    pageSize: pageSize,
  );

  Future<MyProjectPage> page({
    String type = 'all',
    String state = 'all',
    String ownerType = 'all',
    String? scope,
    int pageSize = 200,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/project/my',
      data: FormData.fromMap(<String, dynamic>{
        'type': type,
        'state': state,
        'ownerType': ownerType,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
        'pageNum': '1',
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MyProjectApiException((body['msg'] as String?) ?? '加载失败',
        code: (body['code'] as num?)?.toInt(),
        localCode: body['msg'] == null ? 'load' : null);
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rows = ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MyProject.fromJson)
        .toList();
    final rawTotal = data['total'];
    final reportedTotal = switch (rawTotal) {
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    return MyProjectPage(
      rows: rows,
      total: reportedTotal != null && reportedTotal >= 0
          ? reportedTotal
          : rows.length,
    );
  }

  /// 删除。★ 端点由 bizType 决定 —— 拿错端点删不掉,用户只会看到一个删不动的条目。
  ///   未知 bizType 时 [ProjectEndpoints.forBizType] 返回 null,这里直接抛,
  ///   **不猜一个端点去试**。
  Future<void> remove(MyProject p) async {
    final ep = ProjectEndpoints.forBizType(p.bizType);
    if (ep == null) throw const MyProjectApiException('这种类型暂不支持删除', localCode: 'removeUnsupported');
    await _post(ep.delete, <String, dynamic>{'id': p.id.toString()});
  }

  /// 上架 / 下架。
  Future<void> toggleStatus(MyProject p) async {
    final ep = ProjectEndpoints.forBizType(p.bizType);
    if (ep == null) throw const MyProjectApiException('这种类型暂不支持上下架', localCode: 'statusUnsupported');
    await _post(ep.toggleStatus, <String, dynamic>{
      'id': p.id.toString(),
      if (p.bizType == 'topic') 'expectedUserStatus': p.isOnline ? '1' : '0',
    });
  }

  Future<void> _post(String path, Map<String, dynamic> data) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(data),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MyProjectApiException((body['msg'] as String?) ?? '操作失败',
        code: (body['code'] as num?)?.toInt(),
        localCode: body['msg'] == null ? 'action' : null);
    }
  }

  /// 项目主页(主办/承接双身份聚合):`POST /api/project/home`。
  ///
  /// ★ 后端注释说明了它为什么存在:在此之前这些数据散在**五个接口**里
  ///   (topic/info-to-merchant、registration/merchant/info、coop/candidates、
  ///    coop/list、merchant/upcoming-runs),前端要打五次才拼得出一屏。
  ///   ⇒ 有它就别再拿那五条去拼,拼出来的与聚合口径必然漂。
  ///
  /// ★★ **身份与联系方式的可见范围一律在 service 判,前端不做二次过滤**
  ///   (后端原话)。也就是说:后端给你的就是能给你看的,
  ///   前端再过滤一遍没有意义;而前端"补上"后端没给的字段则是越权。
  Future<Map<String, dynamic>> projectHome({int? topicId}) =>
      _object('/api/project/home', <String, dynamic>{'topicId': ?topicId});

  /// 项目玩家名单(谁要来 / 谁还没来):`POST /api/project/players`。
  ///
  /// ★ 后端注释:「商家开店前想知道的是『谁要来、谁还没来』,不是『已售 24 份』
  ///   —— 所以这里给名单不给统计口径的分析」。
  ///   ⇒ 界面别把它渲染成一个销量数字,那不是这条接口的用途。
  ///
  /// ★★ 联系方式给不给**判在 service**(主办方自办才给)。
  ///   后端原话:「前端过滤等于把号码先发出去再假装没发」。
  ///   ⇒ 拿到就显示,没拿到就不显示;**不要在前端做脱敏** ——
  ///     那意味着明文已经到了客户端。
  /// ★ 返回的是**整个对象**(rows + summary + contactVisible + contactHint),
  ///   不是裸名单 —— 后端连为什么看不到手机号的文案都给了(contactHint),
  ///   原话:「不能只给一个 false 就完事:商家会以为是 bug。说清为什么、以及该找谁」。
  Future<Map<String, dynamic>> projectPlayers({int? topicId}) =>
      _object('/api/project/players', <String, dynamic>{'topicId': ?topicId});

  /// 我的发布工作台:`POST /api/publish/home`。
  Future<Map<String, dynamic>> publishHome() =>
      _object('/api/publish/home', <String, dynamic>{});

  /// 个性化推荐:`POST /api/recommendation/list`(表单 candidate_type / limit)。
  ///
  /// ⚠️ 参数名是 **`candidate_type`**(下划线)。写成驼峰绑不上,
  ///   后端回落成默认的 "topic" —— 你以为在要活动,拿回来的是主题,
  ///   而且不报错。
  /// ⚠️ limit 缺省 20。
  Future<List<Map<String, dynamic>>> recommendations({
    String candidateType = 'topic',
    int? limit,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/recommendation/list',
      data: FormData.fromMap(<String, dynamic>{
        'candidate_type': candidateType,
        if (limit != null) 'limit': limit.toString(),
      }),
    );
    return _rowsOf(resp.data ?? <String, dynamic>{});
  }

  /// IP 世界首页:`POST /api/world/home`(表单 city_code / world_id)。
  ///
  /// ⚠️ 两个参数名都是**下划线**式。
  /// ★ 这条**不要求登录**(后端没取 uid)—— 游客也能看,别在前面加登录闸。
  Future<Map<String, dynamic>> worldHome({
    String? cityCode,
    int? worldId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/world/home',
      data: FormData.fromMap(<String, dynamic>{
        if (cityCode != null && cityCode.isNotEmpty) 'city_code': cityCode,
        if (worldId != null) 'world_id': worldId.toString(),
      }),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MyProjectApiException((body['msg'] as String?) ?? '加载失败',
        code: (body['code'] as num?)?.toInt(),
        localCode: body['msg'] == null ? 'load' : null);
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _object(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body);
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MyProjectApiException((res['msg'] as String?) ?? '加载失败',
        code: (res['code'] as num?)?.toInt(),
        localCode: res['msg'] == null ? 'load' : null);
    }
    return (res['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> res) {
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MyProjectApiException((res['msg'] as String?) ?? '加载失败',
        code: (res['code'] as num?)?.toInt(),
        localCode: res['msg'] == null ? 'load' : null);
    }
    final Object? data = res['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList();
  }
}

/// Optional localCode marks only client-generated copy; server text remains exact.
class MyProjectApiException implements Exception {
  const MyProjectApiException(this.message, {this.code, this.localCode});
  final String message;
  final int? code;
  final String? localCode;
  @override
  String toString() => 'Exception: $message';
}
