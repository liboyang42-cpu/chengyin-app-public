// 集邮册三态整页快照。
//
// ★ 三态是**互斥**的,而且它们各自解决一个真出过的问题 ——
//   golden 拍的正是"它们没有互相串台":
//   ① 空态:「还没有邮票」+ 大按钮,**没有** FAB(FAB 只在有票时出现);
//   ② 有票:散落 collage(不是网格),计数「N 枚」在标题下;
//   ③ 首屏失败:整屏错误态,**不是**空态 —— 空态替失败背书会让用户
//      以为册子被清空了(小程序截图 057 的原始教训)。
//
// 更新基准图:flutter test --update-goldens test/golden/page_stamp_album_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/stamp_album_page.dart';
import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 只替换 stampList 的替身。构造真 RoamApi 需要 DioClient,
/// 这里直接继承覆写那一个方法 —— 比起 mock 框架,少一层看不懂的间接。
class _FakeRoamApi implements RoamApi {
  _FakeRoamApi(this._page);
  final RoamStampPage? _page; // null = 读失败

  @override
  Future<RoamStampPage> stampList({int pageNum = 1, int pageSize = 20}) async {
    final RoamStampPage? p = _page;
    if (p == null) throw RoamApiException('读不到');
    return p;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本测试只用到 stampList');
}

Widget _app(RoamStampPage? page) => ProviderScope(
      overrides: <dynamic>[
        // 集邮册对游客是登录门(游客深链落地只看到「登录后查看」),
        // 这三张快照拍的是册子自己的三态,所以给已登录态。
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              initialized: true,
              user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
            ),
          ),
        ),
        roamApiProvider.overrideWithValue(_FakeRoamApi(page)),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const StampAlbumPage(),
      ),
    );

RoamStampPage _pageWith(int n) => RoamStampPage(
      list: List<RoamStamp>.generate(
        n,
        (int i) => RoamStamp(
          id: i + 1,
          picUrl: 'https://example.invalid/$i.jpg',
          // 混一枚未送检的:它必须照样出现在册子里。
          checkState: i == 0 ? 0 : 1,
        ),
      ),
      total: n,
      pageNum: 1,
      pageSize: 50,
    );

Future<void> _shot(
    WidgetTester tester, RoamStampPage? page, String golden) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(_app(page));
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

void main() {
  testWidgets('★ 空态:大按钮在,FAB 不在', (WidgetTester tester) async {
    await _shot(
      tester,
      const RoamStampPage(
          list: <RoamStamp>[], total: 0, pageNum: 1, pageSize: 50),
      'goldens/page_stamp_album_empty.png',
    );
    expect(find.text('还没有邮票'), findsOneWidget);
    expect(find.text('打开集邮相机'), findsOneWidget);
    expect(find.byKey(const Key('stamp-camera-fab')), findsNothing,
        reason: '空态已经有一个大按钮了,再放 FAB 就是同一个动作两个入口');
  });

  testWidgets('★ 有票:散落 collage + 计数', (WidgetTester tester) async {
    await _shot(tester, _pageWith(9), 'goldens/page_stamp_album_filled.png');
    expect(find.text('9'), findsOneWidget);
    expect(find.text('枚'), findsOneWidget);
    expect(find.byKey(const Key('stamp-camera-fab')), findsOneWidget);
    // 未送检那枚也在:checkState=0 是"机审没跑",不是"没过审"。
    expect(find.byType(Transform), findsWidgets);
  });

  testWidgets('★★ 首屏失败:整屏错误态,不是空态', (WidgetTester tester) async {
    await _shot(tester, null, 'goldens/page_stamp_album_error.png');
    expect(find.text('集邮册没打开'), findsOneWidget);
    expect(find.text('还没有邮票'), findsNothing,
        reason: '读失败时显示空态 = 空态替失败背书,用户以为册子被清空了');
    // 「N 枚」也不能出现:数据没回来就别用权威口吻报数。
    expect(find.text('枚'), findsNothing);
  });
}
