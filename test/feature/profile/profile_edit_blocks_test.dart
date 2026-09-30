import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/profile_edit.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';

import '../../support/fixed_auth.dart';

class _FakeRegistrationApi implements RegistrationApi {
  _FakeRegistrationApi({required this.me, this.err, this.hangFrom});

  final ProfileDetail me;
  final Object? err;

  /// 第 N 次(含)起的 userDetail 永不返回 —— 用来演「刷新中」这一态。
  final int? hangFrom;
  int detailCalls = 0;
  final List<ProfileEditForm> saved = <ProfileEditForm>[];

  @override
  Future<ProfileDetail> userDetail({int? memberId}) {
    detailCalls++;
    if (hangFrom != null && detailCalls >= hangFrom!) {
      return Completer<ProfileDetail>().future;
    }
    return Future<ProfileDetail>.value(me);
  }

  @override
  Future<void> updateProfile(ProfileEditForm form) async {
    if (err != null) throw err!;
    saved.add(form);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryApi implements CategoryApi {
  int calls = 0;

  @override
  Future<List<Category>> list({String? type}) async {
    calls++;
    return <Category>[Category(id: 5, name: '美食'), Category(id: 6, name: '夜游')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProfileDetail _me({
  List<String> casePics = const <String>[],
  String wechat = '',
  List<Category> routePreferences = const <Category>[],
}) => ProfileDetail(
  id: 7,
  nickname: '探索者',
  avatar: '',
  introduction: '',
  levelId: 3,
  point: 88,
  followNum: 1,
  fansNum: 2,
  likeNum: 3,
  topicNum: 0,
  activityNum: 0,
  casePics: casePics,
  wechat: wechat,
  routePreferences: routePreferences,
);

Future<_FakeRegistrationApi> _pump(
  WidgetTester tester, {
  ProfileDetail? me,
  Object? err,
  CategoryApi? categoryApi,
  int? hangFrom,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = _FakeRegistrationApi(
    me: me ?? _me(),
    err: err,
    hangFrom: hangFrom,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        signedInAuthOverride(),
        registrationApiProvider.overrideWithValue(api),
        if (categoryApi != null)
          categoryApiProvider.overrideWithValue(categoryApi),
      ].cast(),
      child: const MaterialApp(home: ProfileEditPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 第一笔就卡住时不能 pumpAndSettle —— 加载动画永远不静止。
    await tester.pump();
  }
  return api;
}

void main() {
  testWidgets('资料编辑页有探索作品/联系二维码/路线偏好三块,保存时整字段回传(不许清空用户已存的)', (
    WidgetTester tester,
  ) async {
    final api = await _pump(
      tester,
      me: _me(
        casePics: const <String>['https://cdn.example/1.jpg'],
        wechat: 'https://cdn.example/qr.jpg',
        routePreferences: <Category>[Category(id: 5, name: '美食')],
      ),
    );

    expect(find.text('探索作品'), findsOneWidget);
    expect(find.text('联系二维码'), findsOneWidget);
    expect(find.text('路线偏好'), findsOneWidget);
    expect(find.text('美食'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-name-field')), '新名字');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.saved, hasLength(1));
    // ★ /api/user/update 是整字段覆盖:少传一项就是把用户已存的清空。
    expect(api.saved.single.casePics, <String>['https://cdn.example/1.jpg']);
    expect(api.saved.single.wechat, 'https://cdn.example/qr.jpg');
    expect(api.saved.single.tagIds, <int>[5]);
    expect(api.saved.single.toJson()['casePics'], 'https://cdn.example/1.jpg');
    expect(api.saved.single.toJson()['tagIds'], '5');
  });

  testWidgets('删掉一枚路线偏好后就该少传一个 tagId(仍保留其余)', (WidgetTester tester) async {
    final api = await _pump(
      tester,
      me: _me(
        routePreferences: <Category>[
          Category(id: 5, name: '美食'),
          Category(id: 6, name: '夜游'),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('profile-preference-remove-美食')));
    await tester.pumpAndSettle();
    expect(find.text('美食'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.saved.single.tagIds, <int>[6]);
  });

  testWidgets('路线偏好「编辑」拉 /api/category/list(type=1) 多选后写回 tagIds', (
    WidgetTester tester,
  ) async {
    final categoryApi = _FakeCategoryApi();
    final api = await _pump(
      tester,
      me: _me(routePreferences: <Category>[Category(id: 5, name: '美食')]),
      categoryApi: categoryApi,
    );

    await tester.tap(find.byKey(const Key('profile-route-preference-edit')));
    await tester.pumpAndSettle();
    expect(categoryApi.calls, 1);
    expect(find.text('夜游'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-preference-6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-preference-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.saved.single.tagIds, <int>[5, 6]);
  });

  testWidgets('资料加载态说「正在读取个人资料」,刷新态说「正在核对个人资料…」', (WidgetTester tester) async {
    // 首次进来:拉不到之前是「正在读取个人资料」(真源骨架屏的 loading-label)。
    await _pump(tester, hangFrom: 1, settle: false);
    expect(find.text('正在读取个人资料'), findsOneWidget);

    // 已有内容后被 invalidate(保存成功会走这一步):说「正在核对个人资料…」,
    // 不说这句用户会以为刚存的东西被清空了。
    final api = await _pump(tester, hangFrom: 2);
    await tester.enterText(find.byKey(const Key('profile-name-field')), '新名字');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.detailCalls, 2);
    expect(find.text('正在核对个人资料…'), findsOneWidget);
    expect(find.text('正在读取个人资料'), findsNothing);
  });

  testWidgets('保存失败给的是行内错误,点名「资料没有保存」而不是只说「失败」', (WidgetTester tester) async {
    final api = await _pump(tester, err: Exception('服务器开小差了'));

    await tester.enterText(find.byKey(const Key('profile-name-field')), '新名字');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump();

    expect(api.saved, isEmpty);
    expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
    expect(find.text('资料没有保存：服务器开小差了'), findsOneWidget);
  });
}
