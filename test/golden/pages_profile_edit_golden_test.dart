import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

/// 表单是**登录态**的那一屏:游客进这一页看到的是登录引导,不是表单
/// (见 test/feature/profile/profile_edit_guest_gate_test.dart)。
class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '城市漫游者', avatar: '', role: 'player'),
    initialized: true,
  );
}

void main() {
  testWidgets('编辑资料:Cupertino 表单', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          myProfileProvider.overrideWith(
            (ref) async => ProfileDetail(
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
            ),
          ),
        ].cast(),
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: const ProfileEditPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_profile_edit.png'),
    );
  });
}
