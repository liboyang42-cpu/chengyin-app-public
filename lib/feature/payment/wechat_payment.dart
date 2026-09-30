import 'dart:async';

import 'package:fluwx/fluwx.dart';

import '../auth/auth_controller.dart'
    show kWechatAppId, kWechatUniversalLink, isWechatConfigured;

/// 调起微信 App 支付的结果。
///
/// ★★★ 这四个值描述的是**用户在微信里做了什么**,不是**订单最终状态**。
/// 微信支付的真源是服务端回调(/api/registration/callback)。
/// 客户端拿到 success 只能说明用户完成了支付动作,订单是否入账必须回查服务端;
/// 拿到 failed/cancelled 也**不能断定没付**——用户可能已扣款而回调尚未到达。
/// 故调用方一律「调起后回查订单状态」,不要用本枚举直接改本地订单态。
enum WechatPayOutcome {
  /// 微信返回成功。仍需回查服务端确认入账。
  success,

  /// 用户主动取消(errCode == -2)。
  cancelled,

  /// 微信返回失败。
  failed,

  /// 没等到回应/超时/未安装微信等。**结果未知,尤其不可当作未支付**。
  unknown,
}

/// 同一时刻只允许一个微信支付会话占用全局回执流。
class WechatPaymentGate {
  bool _active = false;

  bool tryAcquire() {
    if (_active) return false;
    _active = true;
    return true;
  }

  void release() => _active = false;
}

/// 建单前使用的全局支付流闸门；避免多个页面同时创建互相争抢回执的订单。
final WechatPaymentGate wechatPaymentFlowGate = WechatPaymentGate();

/// 微信 App 支付调起。
///
/// 与登录共用同一套 registerApi 参数;支付六元组由后端
/// `/api/registration/create`(payChannel=APP)或 `/api/registration/pay/app` 下发。
class WechatPayment {
  const WechatPayment();

  static final WechatPaymentGate _sdkGate = WechatPaymentGate();

  /// 等待微信回应的上限。超时返回 [WechatPayOutcome.unknown] —— 不是失败。
  static const Duration _timeout = Duration(minutes: 5);
  static const Set<String> _requiredAppPaymentKeys = <String>{
    'appId',
    'partnerId',
    'prepayId',
    'packageValue',
    'nonceStr',
    'timeStamp',
    'sign',
  };

  /// 后端下发的 timeStamp 是字符串,fluwx 的 Payment.timestamp 要 int。
  static int _asTimestamp(String? v) => int.tryParse(v ?? '') ?? 0;

  static bool hasCompleteAppParams(Map<String, String> params) =>
      _requiredAppPaymentKeys.every(
        (String key) => params[key]?.isNotEmpty ?? false,
      ) &&
      _asTimestamp(params['timeStamp']) > 0;

  /// 调起支付。[params] 为后端下发的六元组。
  Future<WechatPayOutcome> pay(Map<String, String> params) async {
    // 服务端签名覆盖完整七字段；任一缺失都不能用空串或
    // Sign=WXPay 默认值“补全”，否则只会制造一次必然失败的 SDK 调用。
    if (!hasCompleteAppParams(params)) {
      return WechatPayOutcome.failed;
    }
    if (!isWechatConfigured) {
      // 未配置 = 请求根本没发出去,和 sent==false 同语义(B1 真跑报告 P2-3:
      // 此前返回 unknown,用户被推去「待确认…不要重复支付」,
      // 而这里既没扣款可能、也没有等待中的结果可确认)。
      return WechatPayOutcome.failed;
    }
    if (!_sdkGate.tryAcquire()) {
      return WechatPayOutcome.unknown;
    }
    FluwxCancelable? sub;
    try {
      final fluwx = Fluwx();
      await fluwx.registerApi(
        appId: kWechatAppId,
        universalLink: kWechatUniversalLink,
      );
      if (!await fluwx.isWeChatInstalled) {
        return WechatPayOutcome.unknown;
      }

      final completer = Completer<WechatPayOutcome>();
      sub = fluwx.addSubscriber((WeChatResponse response) {
        if (response is! WeChatPaymentResponse) return;
        if (completer.isCompleted) return;
        if (response.isSuccessful) {
          completer.complete(WechatPayOutcome.success);
        } else if (response.errCode == -2) {
          completer.complete(WechatPayOutcome.cancelled);
        } else {
          completer.complete(WechatPayOutcome.failed);
        }
      });

      final sent = await fluwx.pay(
        which: Payment(
          appId: params['appId']!,
          partnerId: params['partnerId']!,
          prepayId: params['prepayId']!,
          packageValue: params['packageValue']!,
          nonceStr: params['nonceStr']!,
          timestamp: _asTimestamp(params['timeStamp']),
          sign: params['sign']!,
        ),
      );
      // sent=false 只说明「请求没发出去」,此时确实没支付。
      if (!sent) return WechatPayOutcome.failed;

      return await completer.future.timeout(
        _timeout,
        // 超时不等于没付:用户可能付完了但回应没回来。
        onTimeout: () => WechatPayOutcome.unknown,
      );
    } catch (_) {
      // 异常同样不能断定未支付。
      return WechatPayOutcome.unknown;
    } finally {
      sub?.cancel();
      _sdkGate.release();
    }
  }
}
