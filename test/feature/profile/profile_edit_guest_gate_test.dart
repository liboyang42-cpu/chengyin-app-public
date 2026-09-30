// /profile/edit 的游客态:页内登录引导,不是裸 401 英文。
//
// ★ 来自 B1 模拟器真跑(报告 #217 P1,prof-05-profile-edit-guest.jpg):
//   游客深链 `/profile/edit` 打 `/api/user/info` 拿 HTTP 401,错误态把裸
//   `DioException` 英文原样铺在屏幕上,配「重试 / 回首页」——而重试按多少次
//   都还是 401,是条死路。同域 `/profile` 的游客引导本来是对的,这一页是漏了。
//
// 三条判据各挡一种回归:
//   ① 游客看到的是中文登录引导,屏幕上没有 DioException 字样;
//   ② 游客态**一次接口都不打** —— 挡在 build 里,那条注定 401 的请求根本不发;
//   ③ 登录成功后就地出表单,人留在本页(不是被弹回首页)。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _MutableAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);

  void signIn() {
    state = AuthState(
      initialized: true,
      user: User(id: 7, nickname: '城市漫游者', avatar: '', role: 'player'),
    );
  }
}

/// 记下有没有人去问「我的资料」—— 游客态一次都不该问。
class _RecordingRegistrationApi implements RegistrationApi {
  int calls = 0;

  @override
  Future<ProfileDetail> userDetail({int? memberId}) async {
    calls += 1;
    // 生产实测:无 token 打这条接口就是 HTTP 401。
    throw DioException(
      requestOptions: RequestOptions(path: '/api/user/info'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/user/info'),
        statusCode: 401,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubRegistrationApi implements RegistrationApi {
  @override
  Future<ProfileDetail> userDetail({int? memberId}) async => ProfileDetail(
    id: 7,
    nickname: '城市漫游者',
    avatar: '',
    introduction: '用脚步认识城市',
    levelId: 1,
    point: 20,
    balance: 128.5,
    followNum: 0,
    fansNum: 0,
    likeNum: 0,
    topicNum: 0,
    activityNum: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('游客打开 /profile/edit:出登录引导,且不发资料请求', (WidgetTester tester) async {
    final api = _RecordingRegistrationApi();
    await tester.pumpWidget(
      ProviderScope(
        // Riverpod 3 默认对失败的 provider 自动重试 10 次 —— 那不是本文件要验
        // 的东西,关掉才能把「这一页自己发不发请求」数干净。
        retry: (int _, Object _) => null,
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          registrationApiProvider.overrideWithValue(api),
        ].cast(),
        child: const MaterialApp(home: ProfileEditPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后编辑我的资料'), findsOneWidget);
    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(api.calls, 0, reason: '游客态不该打 /api/user/info —— 打出去就是一条注定 401 的请求');
  });

  testWidgets('登录成功后就地出表单,人留在本页', (WidgetTester tester) async {
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_MutableAuth.new),
        registrationApiProvider.overrideWithValue(_StubRegistrationApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileEditPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后编辑我的资料'), findsOneWidget);

    (container.read(authControllerProvider.notifier) as _MutableAuth).signIn();
    await tester.pumpAndSettle();

    expect(find.text('登录后编辑我的资料'), findsNothing);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
  });
}
