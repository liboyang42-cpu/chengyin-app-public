import 'package:dio/dio.dart';

/// Riverpod 3 的**全局重试策略**。
///
/// ★★★ 2026-08-19 发现:Riverpod 3 默认会把**任何**失败的 provider 自动重试
///   最多 10 次(200ms 起指数退避,封顶 6.4s,见 ProviderContainer.defaultRetry)。
///   它只跳过 `Error` 和 `ProviderException` —— 而本项目 API 层的业务失败
///   一律 `throw Exception(msg)`,正好**不在**跳过之列。
///
///   两个后果,都不是我们想要的:
///   ① 后端**故意拒绝**的接口会被反复重打。比如探店日完局面对非探索票
///      是 fail-closed(「该订单没有探店日完局面」),每开一次订单详情就打 10 次。
///      未登录、无权限同理 —— 重试永远不会成功。
///   ② 重试期间 AsyncValue 停在 `AsyncLoading`,`when()` 走的是 loading 分支
///      ⇒ 用户看到的是**转圈**,而全站那些写好的错误态和「重试」按钮
///      要等三十多秒才出得来。等于错误提示被静默吞掉半分钟。
///
/// 策略:**只重试真正可能自愈的传输层故障**,业务拒绝一次都不重。
/// 次数也压到 2 次(≈0.9s)——超过这个时长,把控制权交还给用户手上那个
/// 「重试」按钮,比让他盯着转圈强。
Duration? chengyinRetry(int retryCount, Object error) {
  if (error is! DioException) return null; // 业务拒绝:一次都不重
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      if (retryCount >= 2) return null;
      return Duration(milliseconds: 300 * (retryCount + 1));
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      // badResponse = 服务端明确答复(4xx/5xx),重试同样打不通;
      // cancel 是我们自己取消的,重试等于跟自己对着干。
      return null;
  }
}
