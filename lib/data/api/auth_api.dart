import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';

/// 登录相关接口。**契约对齐真实后端 `ApiLoginController`(RuoYi,/api 前缀,参数走表单)**。
/// 后端用裸 String 形参绑定请求参数,故这里用 `FormData` 提交。
class AuthApi {
  AuthApi(this._client);
  final DioClient _client;

  /// 微信登录:小程序/ App 取 wx code → 后端 `POST /api/login/code`
  /// （jscode2session 换 openid，已注册则发 token）。
  Future<Map<String, dynamic>> loginWithWechatCode(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/login/code',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 原生微信登录(App):fluwx 拉起微信授权拿 oauth code → `POST /api/login/wechat/app`。
  /// 返回结构与 `loginWithWechatCode` 一致(`{code, token, data}`)。
  Future<Map<String, dynamic>> loginWithWechatApp(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/login/wechat/app',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// Sign in with Apple:sign_in_with_apple 拿 identityToken → `POST /api/login/apple`。
  /// 返回结构与 `loginWithWechatCode` 一致(`{code, token, data}`)。
  Future<Map<String, dynamic>> loginWithApple(String identityToken) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/login/apple',
      data: FormData.fromMap(<String, dynamic>{'identityToken': identityToken}),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 账号密码登录:`POST /api/login`。
  Future<Map<String, dynamic>> loginWithPassword(
    String username,
    String password, {
    String? code,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/login',
      data: FormData.fromMap(<String, dynamic>{
        'username': username,
        'password': password,
        'code': ?code,
      }),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 微信绑定手机号:`POST /api/getwxbindphone`(getPhoneNumber 的 code)。
  Future<Map<String, dynamic>> bindWxPhone(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/getwxbindphone',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 当前用户信息:`POST /api/userInfo`(需带 token)。
  Future<Map<String, dynamic>> userInfo() async {
    final resp = await _client.dio.post<Map<String, dynamic>>('/api/userInfo');
    return resp.data ?? <String, dynamic>{};
  }

  /// 发送手机验证码。
  ///
  /// ★ 2026-08-18 核实:后端**早已实现**(`ApiLoginController.smsSend`)——
  ///   手机号格式校验 → 60 秒限频 → 6 位随机码 → 阿里云发送 → Redis 存 5 分钟。
  ///   生产实测该端点存在且在校验格式(空请求返回「手机号格式不正确」,
  ///   而不存在的路径返回 401),此前那句「待后端确认/接入」已过期。
  ///
  /// ⚠️ 阿里云凭据(后端读 `CHENGYIN_SMS_*` env 或 sys_config `sms.aliyun.*`)
  ///   **2026-09-19 生产实测确认未配置**:对格式合法且未分配的号段(13800000000)
  ///   调用返回「短信服务未配置」——该校验在限频与真实发送之前,无任何副作用。
  ///   故验证码登录在生产环境端到端不可用,App 内点「获取验证码」必失败。
  ///   实证与通道盘点见 docs/research/login-channels-sim-20260919.md。
  Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/sms/send',
      data: FormData.fromMap(<String, dynamic>{'phone': phone}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '验证码发送失败');
    }
    return body;
  }

  /// 手机号 + 验证码登录。
  ///
  /// ★ 2026-08-18 核实:`ApiLoginController.loginPhone` **已存在并实现**
  ///   (校验格式 → checkMscode 比对 Redis 里的码 → 签发登录态),
  ///   此前那句「暂无 sms 登录,可能要新增」已过期。
  Future<Map<String, dynamic>> loginWithPhone(String phone, String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/login/phone',
      data: FormData.fromMap(<String, dynamic>{'phone': phone, 'code': code}),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 退出登录:`POST /api/logout`。
  ///
  /// ★ **App 此前只清本地 token,从不通知服务端** ——
  ///   后端 `ApiLoginController:166` 会 `delLoginAppUser(token)` 把这个 token 作废;
  ///   不调它的话,**那个 token 在服务端一直有效**。
  ///   手机丢了、或者在别人设备上登录后退出,那份凭据仍然能用。
  ///
  /// ⚠️ 但**服务端失败不能阻断本地退出** —— 用户点了退出就必须退成,
  ///   否则网络一断人就被困在已登录状态里。所以调用方要:先尽力通知服务端,
  ///   无论成败都清本地。这是「尽力而为」不是「必须成功」。
  Future<void> logout() async {
    await _client.dio.post<Map<String, dynamic>>(
      '/api/logout',
      data: FormData.fromMap(<String, dynamic>{}),
    );
  }
}
