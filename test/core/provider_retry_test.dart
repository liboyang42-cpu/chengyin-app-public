// Riverpod 3 的自动重试默认值不适合本项目。
//
// ★★★ 默认策略(ProviderContainer.defaultRetry)会把**任何** Exception 重试
//   最多 10 次、退避到 6.4s。而本项目 API 层的业务失败一律 throw Exception,
//   于是:
//   · 后端故意拒绝的接口(fail-closed / 未登录 / 无权限)被反复重打
//   · 重试期间状态停在 AsyncLoading ⇒ 用户盯着转圈三十多秒才看到错误态
//
// 这条测试钉住:业务拒绝一次都不重,只有传输层故障才重、且最多 2 次。

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/network/provider_retry.dart';

DioException _dio(DioExceptionType t) =>
    DioException(requestOptions: RequestOptions(path: '/x'), type: t);

void main() {
  test('★★★ 业务拒绝一次都不重试', () {
    expect(chengyinRetry(0, Exception('该订单没有探店日完局面')), isNull);
    expect(chengyinRetry(0, Exception('请登录')), isNull);
    expect(chengyinRetry(0, Exception('无权限')), isNull);
  });

  test('★★ 服务端明确答复(4xx/5xx)也不重 —— 重试同样打不通', () {
    expect(chengyinRetry(0, _dio(DioExceptionType.badResponse)), isNull);
  });

  test('★ 我们自己取消的请求不重 —— 重试等于跟自己对着干', () {
    expect(chengyinRetry(0, _dio(DioExceptionType.cancel)), isNull);
  });

  test('★★ 传输层故障重试,但最多 2 次', () {
    for (final DioExceptionType t in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      expect(chengyinRetry(0, _dio(t)), const Duration(milliseconds: 300));
      expect(chengyinRetry(1, _dio(t)), const Duration(milliseconds: 600));
      expect(chengyinRetry(2, _dio(t)), isNull,
          reason: '超过 2 次就把控制权交还给用户手上那个「重试」按钮');
    }
  });

  test('★ 总重试时长要短 —— 默认那套能拖三十多秒', () {
    int total = 0;
    for (int i = 0; ; i++) {
      final Duration? d = chengyinRetry(i, _dio(DioExceptionType.connectionError));
      if (d == null) break;
      total += d.inMilliseconds;
    }
    expect(total, lessThan(1500),
        reason: '重试期间用户看到的是转圈,不是错误态');
  });

  // ★★ 策略函数对不对是一回事,**装没装上**是另一回事。
  //   下面这条用真 provider 走一遍:业务失败必须**立刻**变成 AsyncError,
  //   而不是停在 AsyncLoading 等着重试。
  test('★★★ 装上之后:业务失败立刻是 error 态,不是转圈', () async {
    final container = ProviderContainer(retry: chengyinRetry);
    addTearDown(container.dispose);
    final p = FutureProvider<int>((ref) async => throw Exception('后端拒绝'));

    container.listen(p, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // ⚠️ 判据是 **isLoading**,不是 hasError。重试期间的状态是
    //   `AsyncLoading(error: ...)` —— hasError 已经是 true,
    //   但 `when()` 优先走 loading 分支,用户看到的仍是转圈。
    //   第一版用 hasError 写,两边都 true,负控当场没红。
    expect(container.read(p).isLoading, isFalse,
        reason: '停在 loading 的话,页面上那些「重试」按钮永远不出现');
    expect(container.read(p).hasError, isTrue);
  });

  test('★★★ 负控:用默认策略跑同一个 provider —— 它会卡在 loading', () async {
    // 这条证明上一条不是恒真:同样的 provider,默认策略下 50ms 时仍在重试。
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final p = FutureProvider<int>((ref) async => throw Exception('后端拒绝'));

    container.listen(p, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(p).isLoading, isTrue,
        reason: 'Riverpod 3 默认会重试,状态停在 AsyncLoading(error:) ——'
            '这正是要覆盖它的原因');
  });
}
