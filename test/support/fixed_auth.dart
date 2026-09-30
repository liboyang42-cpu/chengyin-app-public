// 页内登录门(roam #208 模式)的测试替身:把 authControllerProvider 钉成
// 「已登录/游客」两种确定态,测试不必碰真 token 存储。

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

AuthState signedInAuthState({String role = 'player'}) => AuthState(
  initialized: true,
  user: User(id: 1, nickname: '测试账号', avatar: '', role: role),
);

const AuthState guestAuthState = AuthState(initialized: true);

class FixedAuth extends AuthController {
  FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 已登录(玩家)的 ProviderScope override。账号/资料域带页内登录门的页面
/// 测「登录后的真实态」必须带上 —— 不带就是游客,先撞登录门。
dynamic signedInAuthOverride({String role = 'player'}) => authControllerProvider
    .overrideWith(() => FixedAuth(signedInAuthState(role: role)));

/// 游客(已初始化、未登录)的 override。默认容器态本就是游客,显式版本用于
/// 深链用例表达「游客落地」的意图。
dynamic guestAuthOverride() =>
    authControllerProvider.overrideWith(() => FixedAuth(guestAuthState));
