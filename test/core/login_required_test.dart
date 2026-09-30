// 401 → 「需要登录」判定。见 lib/core/network/login_required.dart:
// 后端对无 token 的请求返 401(有意拒绝),不是故障,不能渲成「加载失败」。
import 'package:chengyin_app/core/network/login_required.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _unauthorized(Object? body) {
  final RequestOptions options = RequestOptions(path: '/api/city/nodes');
  return DioException(
    requestOptions: options,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: 401,
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  test('HTTP 401 是「需要登录」', () {
    expect(
      isLoginRequiredError(_unauthorized(<String, Object?>{'code': 401})),
      isTrue,
    );
  });

  test('后端 HTTP 200 + code:401 的文案也算', () {
    expect(isLoginRequiredError(Exception('登录状态已失效，请重新登录')), isTrue);
    expect(isLoginRequiredError(Exception('请先登录')), isTrue);
  });

  test('记录对 await (a, b) 的 ParallelWaitError 里有 401 也算', () async {
    Object? captured;
    try {
      await (
        Future<int>.error(_unauthorized(<String, Object?>{'code': 401})),
        Future<int>.value(1),
      ).wait;
    } catch (error) {
      captured = error;
    }
    expect(captured, isNotNull);
    expect(isLoginRequiredError(captured), isTrue);
  });

  test('故障不算「需要登录」', () {
    final RequestOptions options = RequestOptions(path: '/api/city/nodes');
    expect(
      isLoginRequiredError(
        DioException(
          requestOptions: options,
          response: Response<Object?>(requestOptions: options, statusCode: 500),
          type: DioExceptionType.badResponse,
        ),
      ),
      isFalse,
    );
    expect(
      isLoginRequiredError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      isFalse,
    );
    expect(isLoginRequiredError(Exception('请求失败')), isFalse);
    expect(isLoginRequiredError(null), isFalse);
  });
}
