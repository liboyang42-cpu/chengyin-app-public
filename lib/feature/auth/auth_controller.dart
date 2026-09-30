import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluwx/fluwx.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/providers.dart';
import '../../core/feature_flags.dart';
import '../../data/models/user.dart';

/// 微信开放平台 App AppId(原生微信登录用)。
/// TODO(native-login): 换成真实开放平台 AppId(`wx` 开头),并同步:
///   - iOS Info.plist 的 CFBundleURLTypes scheme(现为占位 wxYOURAPPID)
///   - iOS registerApi 的 universalLink(开放平台「Universal Links」)
///   - Android 开放平台「应用签名」+ WXEntryActivity 包名
///   - 后端 `app.wechat.app.appid/appsecret`(2026-09-19 生产实测未配置,
///     `/api/login/wechat/app` 返回「原生微信未配置」)
/// 详见 docs/native-login-setup.md。
const String kWechatAppId = 'wxYOURAPPID';

/// 微信开放平台配置是否已就位。
///
/// ★ 拿占位 appid 去调 fluwx 不会立刻报错 —— registerApi 会「成功」,
///   然后在拉起微信时静默失败或抛出难以定位的底层错误。真机上表现为
///   「点了没反应」,排查成本极高。故在入口处显式拦一道。
///
/// appid 到位后只改上面那个常量即可,本判据自动放行。
bool hasCompleteWechatAppConfiguration({
  required String appId,
  required String universalLink,
}) {
  final Uri? link = Uri.tryParse(universalLink);
  return appId.startsWith('wx') &&
      !appId.startsWith('wxYOUR') &&
      appId.length > 2 &&
      link != null &&
      link.scheme == 'https' &&
      link.host.isNotEmpty &&
      universalLink.endsWith('/');
}

/// 微信开放平台配置的 Universal Link(iOS 必填,否则授权拉起会失败)。
/// TODO(native-login): 换成真实 Universal Link。
const String kWechatUniversalLink = 'https://api.example.invalid/app/';

bool get isWechatConfigured => hasCompleteWechatAppConfiguration(
  appId: kWechatAppId,
  universalLink: kWechatUniversalLink,
);

/// 登录态。`user == null` 表示未登录;`initialized=false` 表示启动恢复未完成。
class AuthState {
  const AuthState({this.user, this.loading = false, this.initialized = false});
  final User? user;
  final bool loading;

  /// 启动恢复(bootstrap)是否完成。未完成时路由停在 splash,避免误跳 /login。
  final bool initialized;

  bool get isLoggedIn => user != null;

  AuthState copyWith({User? user, bool? loading, bool? initialized}) =>
      AuthState(
        user: user ?? this.user,
        loading: loading ?? this.loading,
        initialized: initialized ?? this.initialized,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  /// 启动时用已存 token 拉 /api/userInfo 恢复登录态;失败则清 token。
  /// 无论成败,最终 initialized=true 放行路由。
  Future<void> bootstrap() async {
    String? token;
    try {
      // 钥匙串读偶发不返回(securityd 卡死),有界等待后按游客放行,
      // 避免 splash 无限停在 initialized=false。
      token = await ref
          .read(tokenStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // 钥匙串在模拟器、设备恢复或签名变化后可能暂时不可读。
      // 这不应把 App 永久锁在启动页；按游客态放行，后续仍可重新登录。
      state = const AuthState(initialized: true);
      return;
    }
    if (token == null || token.isEmpty) {
      state = const AuthState(initialized: true);
      _refreshFeatureFlagsInBackground();
      return;
    }
    try {
      final body = await ref.read(authApiProvider).userInfo();
      final ok = (body['code'] as num?)?.toInt() == 200;
      final data = body['appUser'];
      if (ok && data is Map<String, dynamic>) {
        state = AuthState(user: User.fromJson(data), initialized: true);
        _refreshFeatureFlagsInBackground();
      } else {
        await _clearStoredTokenBestEffort();
        ref.read(featureFlagsProvider.notifier).clear();
        state = const AuthState(initialized: true);
        _refreshFeatureFlagsInBackground();
      }
    } catch (_) {
      await _clearStoredTokenBestEffort();
      state = const AuthState(initialized: true);
      ref.read(featureFlagsProvider.notifier).clear();
      _refreshFeatureFlagsInBackground();
    }
  }

  Future<void> _clearStoredTokenBestEffort() async {
    try {
      await ref.read(tokenStoreProvider).clear();
    } catch (_) {
      // 本地凭据存储不可用时仍要放行启动/登出流程；
      // 后续请求会由服务端 401 再次拒绝失效 token。
    }
  }

  /// 原生微信登录(App)。fluwx 拉起微信授权拿 oauth code →
  /// `AuthApi.loginWithWechatApp(code)` → 存 token、刷新登录态。
  /// 成功返回 null,失败返回错误文案,用户取消返回 null(不报错)。
  /// token 处理完全照 [loginWithPhone]。
  Future<String?> loginWithWechatApp() async {
    // 配置未就位时立刻返回,不拿占位 appid 去调 SDK。
    // ★ 给用户的文案里不提 appid / 开放平台 —— 那是我们的内部构件,
    //   用户看不懂,而且等于把「这个 App 还没配好」写在脸上(审核员也会看到)。
    //   开发者需要的定位信息走 assert,release 构建会被整体剥掉。
    if (!isWechatConfigured) {
      assert(() {
        debugPrint(
          '[dev] 微信 appid 仍是占位符:换掉 kWechatAppId + '
          'Info.plist 的 CFBundleURLSchemes 后才能真机登录',
        );
        return true;
      }());
      // ★ 不再写「请改用手机号登录」—— 手机号路当前同样走不通
      //   (后端 `sms.aliyun.*` 未配置,验证码发不出去,B1 账号域报告 P2-2)。
      //   引导只指向真实可达的出口:iOS 设备上 Apple 登录恒在。
      return '暂时无法使用微信登录,请用「通过 Apple 登录」,或稍后再试';
    }
    state = state.copyWith(loading: true);
    final fluwx = Fluwx();
    try {
      // 1) 注册 WXApi(每次拉起前注册是安全的)。
      await fluwx.registerApi(
        appId: kWechatAppId,
        universalLink: kWechatUniversalLink,
      );

      // 2) 没装微信直接报错,避免空等。
      if (!await fluwx.isWeChatInstalled) {
        state = state.copyWith(loading: false);
        return '未安装微信,请改用其他方式登录';
      }

      // 3) authBy 只负责把授权请求发给微信;真正的 code 通过响应流异步回来。
      //    用 Completer 把「异步响应」桥接成 await 拿 code。
      final codeCompleter = Completer<String?>();
      final cancelable = fluwx.addSubscriber((WeChatResponse response) {
        if (response is WeChatAuthResponse) {
          if (codeCompleter.isCompleted) return;
          // errCode==0 成功;-2 用户取消;其余为失败。
          if (response.isSuccessful) {
            codeCompleter.complete(response.code);
          } else {
            codeCompleter.complete(null);
          }
        }
      });

      String? code;
      try {
        final sent = await fluwx.authBy(
          which: NormalAuth(scope: 'snsapi_userinfo', state: 'chengyin_login'),
        );
        if (!sent) {
          cancelable.cancel();
          state = state.copyWith(loading: false);
          return '微信授权拉起失败';
        }
        // 等微信回调(限时,避免用户切走后永远 loading)。
        code = await codeCompleter.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () => null,
        );
      } finally {
        cancelable.cancel();
      }

      // 用户取消 / 拿不到 code:静默结束,不报错。
      if (code == null || code.isEmpty) {
        state = state.copyWith(loading: false);
        return null;
      }

      // 4) 换 token(与 loginWithPhone 同款)。
      final body = await ref.read(authApiProvider).loginWithWechatApp(code);
      return _consumeLoginBody(body);
    } catch (_) {
      state = state.copyWith(loading: false);
      return '网络错误,请稍后重试';
    }
  }

  /// Sign in with Apple(iOS)。getAppleIDCredential 拿 identityToken →
  /// `AuthApi.loginWithApple(identityToken)` → 存 token、刷新登录态。
  /// 成功返回 null,失败返回错误文案;取消/没走完成返回中性落点文案
  /// (见下:设备无 Apple 账户时同样以 canceled 结束,不能静默)。
  /// ⚠️ 后端 `apple.clientId` 生产实测未配置(`/api/login/apple` 返回
  ///   「Apple登录未配置」,2026-09-19),配置前本通道端到端不可用。
  Future<String?> loginWithApple() async {
    state = state.copyWith(loading: true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        state = state.copyWith(loading: false);
        return 'Apple 登录失败:未获取到凭证';
      }
      final body = await ref
          .read(authApiProvider)
          .loginWithApple(identityToken);
      return _consumeLoginBody(body);
    } on SignInWithAppleAuthorizationException catch (e) {
      state = state.copyWith(loading: false);
      if (e.code == AuthorizationErrorCode.canceled) {
        // ★ 「取消」≠ 只有用户主动取消这一种:设备上**没有登录 Apple 账户**时,
        //   系统面板根本不会出现,授权同样以 canceled 结束(B1 账号域报告 P2-1,
        //   模拟器实拍 acct-18/18b:点了没面板、没任何提示 = 失败无落点)。
        //   两种情况前端拿不到可区分的信号,所以给一条不指责的中性提示,
        //   把唯一可行动的出口写在句里。宁可让真取消多看一眼提示,
        //   也不能让「点了没反应」继续是死寂。
        return 'Apple 登录没有完成。若这台设备还没登录 Apple 账户,'
            '请先在系统「设置 → Apple 账户」登录后再试';
      }
      return 'Apple 登录失败,请稍后重试';
    } catch (_) {
      state = state.copyWith(loading: false);
      return '网络错误,请稍后重试';
    }
  }

  /// 统一消费登录返回体:取 token 持久化 + 刷新登录态。
  /// 与 [loginWithPhone] 的 token 处理逻辑一致。
  Future<String?> _consumeLoginBody(Map<String, dynamic> body) async {
    final ok = (body['code'] as num?)?.toInt() == 200;
    if (!ok) {
      state = state.copyWith(loading: false);
      return (body['msg'] ?? '登录失败').toString();
    }
    final token = body['token'] as String?;
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (token != null && token.isNotEmpty) {
      await ref.read(tokenStoreProvider).write(token);
    }
    state = AuthState(user: User.fromJson(data), initialized: true);
    _refreshFeatureFlagsInBackground();
    return null;
  }

  /// 手机号 + 验证码登录。成功返回 null,失败返回错误文案。
  /// ⚠️ 后端端点已实现,但短信通道生产实测未配置(见
  ///   docs/research/login-channels-sim-20260919.md),现网无法走到本方法。
  Future<String?> loginWithPhone(String phone, String code) async {
    state = state.copyWith(loading: true);
    try {
      final body = await ref.read(authApiProvider).loginWithPhone(phone, code);
      final ok = (body['code'] as num?)?.toInt() == 200;
      if (!ok) {
        state = state.copyWith(loading: false);
        return (body['msg'] ?? '登录失败').toString();
      }
      // 后端:token 在 AjaxResult 顶层,用户在 data
      final token = body['token'] as String?;
      final data =
          (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (token != null && token.isNotEmpty) {
        await ref.read(tokenStoreProvider).write(token);
      }
      state = AuthState(user: User.fromJson(data), initialized: true);
      _refreshFeatureFlagsInBackground();
      return null;
    } catch (_) {
      state = state.copyWith(loading: false);
      return '网络错误,请稍后重试';
    }
  }

  Future<void> logout() async {
    // ★ 先通知服务端作废 token(`/api/logout` → delLoginAppUser)。
    //   不调它的话,这份凭据在服务端**一直有效** —— 手机丢了或在别人设备上
    //   退出后,那个 token 仍然能用。
    //
    // ⚠️ 但这是**尽力而为**,不是必须成功:服务端失败绝不能阻断本地退出,
    //   否则网络一断,用户就被困在已登录状态里退不出去。
    try {
      await ref.read(authApiProvider).logout();
    } catch (_) {
      // 通知失败也照常清本地 —— 用户点了退出就必须退成。
    }
    await _signOutLocally();
  }

  /// 服务端已经用 401 宣告当前会话失效时，只需要本地退出。
  /// 不能再请求 `/api/logout`，否则失效 token 会再次收到 401，
  /// 重入 Dio 的 onUnauthorized 链路。
  Future<void> expireSession() => _signOutLocally();

  Future<void> _signOutLocally() async {
    await _clearStoredTokenBestEffort();
    ref.read(featureFlagsProvider.notifier).clear();
    state = const AuthState(initialized: true);
    _refreshFeatureFlagsInBackground();
  }

  void _refreshFeatureFlagsInBackground() {
    unawaited(ref.read(featureFlagsProvider.notifier).load());
  }

  /// 重新拉取用户信息刷新本地角色(RBAC 单一真源在服务端)。
  /// 成为俱乐部主理人(become-leader)等操作后,本地 user.role 会过期,调用本方法回读。
  Future<void> refreshRole() async {
    try {
      final body = await ref.read(authApiProvider).userInfo();
      final ok = (body['code'] as num?)?.toInt() == 200;
      final data = body['appUser'];
      if (ok && data is Map<String, dynamic>) {
        state = state.copyWith(user: User.fromJson(data));
      }
    } catch (_) {
      // 回读失败不阻塞流程:角色真源在后端,下次登录会拉回正确值。
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
