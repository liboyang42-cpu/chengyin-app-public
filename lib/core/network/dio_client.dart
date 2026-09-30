import 'dart:convert';

import 'package:dio/dio.dart';
import '../config/env.dart';
import 'token_store.dart';

/// 统一网络层:基址 + JWT 注入 + 错误归一。**feature 层不直接发 http**。
class DioClient {
  DioClient(this._tokenStore, {this.onUnauthorized})
    : dio = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: Env.connectTimeout,
          receiveTimeout: Env.receiveTimeout,
          contentType: Headers.jsonContentType,
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token;
          try {
            token = await _tokenStore.read();
          } catch (_) {
            // 安全存储暂不可读时仍允许匿名接口工作；需要登录的接口会由
            // 服务端返回 401，并进入现有的统一登出路径。
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = token;
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // 401:token 失效 → 清 token + 通知上层登出(由 go_router 跳回 /login)。
          // 暂不做"无感续期"(后端无 refresh token 端点;有了再在此重放)。
          if (e.response?.statusCode == 401) {
            try {
              await _tokenStore.clear();
            } catch (_) {
              // 钥匙串暂不可写不得阻断登出通知或吞掉原始 401。
            }
            onUnauthorized?.call();
          }
          handler.next(e);
        },
      ),
    );
  }

  /// SSE 流式通道: POST body → 逐行解析 text/event-stream 的 `data:` 行。
  /// 用于 NPC 追问等实时生成场景。
  Stream<String> sse(String path, Map<String, dynamic> body) async* {
    final resp = await dio.post<ResponseBody>(
      path,
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    final stream = resp.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in stream) {
      if (line.startsWith('data:')) {
        yield line.substring(5).trim();
      }
    }
  }

  final TokenStore _tokenStore;

  /// 401 时回调(上层用于重置登录态)。
  final void Function()? onUnauthorized;

  final Dio dio;
}

/// 后端是否以「未登录」拒绝了这次请求。**只认 401** —— 把网络故障也算成要登录,
/// 断网用户会被反复推去登录页,登完还是失败(判据同 activity_detail_page)。
///
/// ★ 生产实测(2026-09-18,无 token):
///   `POST /api/topic/info-to-user` / `/api/topic/pricing/preview` / `/api/club/detail`
///   一律 `HTTP 401 {"msg":"登录状态已失效，请重新登录","code":401}`。
///   页面把这一类比成「网络异常」= 让用户一直重试一条永远不会成功的死路。
bool isUnauthorizedError(Object error) =>
    error is DioException && error.response?.statusCode == 401;

/// 读接口失败时**给用户看的那句话**:说人话 + 点名失败的是什么。
///
/// ★ 判据 1:1 抄小程序 `subpackageMember/coupon-qr/index.js` 的 `friendlyQrError`
///   (登录 / 网络两档稳定文案,其余交调用方给场景兜底)—— 不是另发明一套口径。
/// ★ 出口永不会是异常原文:`DioException [bad response]: … 502 …` 那种英文栈
///   一律只进调用方的 `debugPrint`,不进 UI(b1 报告 P2-1 的实拍)。
///
/// [fallback] = 「点名失败的是什么」,由调用方按页给(对齐真源)。
String friendlyErrorMessage(Object error, {required String fallback}) {
  final String text = '$error';
  if (RegExp(r'登录|认证|401|token', caseSensitive: false).hasMatch(text)) {
    return '登录已过期，请重新进入';
  }
  if (RegExp(r'网络|timeout|fail|502|503', caseSensitive: false).hasMatch(text)) {
    return '网络异常，请稍后重试';
  }
  return fallback;
}


/// 上面那句的**业务版**:后端/我方 API 层已经回了一句中文人话(如
/// 「当前有效供给少于 3 家,本次不刷新」「记录不可见」)时照说 —— 那是可行动
/// 的信息,换成场景兜底等于把它吞掉;只有裸异常(DioException / PlatformException
/// 那种英文栈)才交给 [friendlyErrorMessage] 说人话。
///
/// 判据:整句**不含英文字母**、至少一个汉字 = 人话(英文栈永远不满足)。
String friendlyOrBackendMessage(Object error, {required String fallback}) {
  final String text = '$error'.replaceFirst('Exception: ', '');
  if (RegExp(r'^[^A-Za-z]*[\u4e00-\u9fff][^A-Za-z]*$').hasMatch(text)) {
    return text;
  }
  return friendlyErrorMessage(error, fallback: fallback);
}
