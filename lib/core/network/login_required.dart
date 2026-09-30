import 'dart:async';

import 'package:dio/dio.dart';

/// 后端未登录的两种拒绝措辞:HTTP 401,以及 HTTP 200 + `code:401` 的文案。
final RegExp _loginPhrases = RegExp(r'请先登录|登录状态已失效|登录已过期');

/// 失败是不是「需要登录」,而不是故障。
///
/// 后端对无 token 的请求返回 HTTP 401(`{"code":401,"msg":"登录状态已失效，请重新登录"}`),
/// 这是**有意拒绝**。这类失败必须引导登录:渲成「加载失败 / 网络请求失败」会让用户
/// 以为是网络问题而反复重试,而重试永远不会成功
/// (活动详情页 2026-08-18 已踩过同一个坑,见 activity_detail_page.dart)。
bool isLoginRequiredError(Object? error) {
  if (error == null) return false;
  for (final Object? leaf in _leaves(error)) {
    if (leaf is DioException && leaf.response?.statusCode == 401) return true;
  }
  // 兜底:包装形状没枚举到的容器,以及后端 200 里带 code:401 的文案。
  final String text = error.toString();
  return text.contains('status code of 401') || _loginPhrases.hasMatch(text);
}

/// 摊平并行失败的容器,拿到里面的原始异常。
/// 本仓两种形状:`Future.wait`(Iterable)与记录对 `await (a, b)`(见
/// search_controller 的 cityNodeSearchProvider)。
Iterable<Object?> _leaves(Object? error) sync* {
  if (error is AsyncError) {
    yield* _leaves(error.error);
  } else if (error is ParallelWaitError) {
    final Object? errors = error.errors;
    if (errors is Iterable) {
      for (final Object? inner in errors) {
        yield* _leaves(inner);
      }
    } else if (errors is (AsyncError?, AsyncError?)) {
      yield* _leaves(errors.$1);
      yield* _leaves(errors.$2);
    }
  } else {
    yield error;
  }
}
