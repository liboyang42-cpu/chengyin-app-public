// 合作者选择器。
//
// ★★ App 此前**完全没有这块**:专业版编辑器把 collaboratorIds 恒设成
//   `[我自己]`,没有任何添加别人的入口 —— 合作者在 App 里等于不存在。
//
// ⚠️ 小程序那个选择器的搜索框只存值、没接过滤逻辑(它自己的注释写了
//   「原样保留,不在本次范围内新修」)。这边没照抄那个假搜索框:
//   点了没反应的控件比没有更坏,而 publicMemberList 本来就支持 keyword。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/publish/collaborator_picker.dart';

class _FakeApi implements RegistrationApi {
  _FakeApi({this.rows = const <Map<String, dynamic>>[], this.err});
  final List<Map<String, dynamic>> rows;
  final Object? err;
  String? lastKeyword;

  @override
  Future<List<Map<String, dynamic>>> publicMemberList({
    String userType = '0',
    String? keyword,
  }) async {
    lastKeyword = keyword;
    if (err != null) throw err!;
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<CollaboratorCandidate?> _open(
  WidgetTester t,
  _FakeApi api, {
  List<int> picked = const <int>[],
}) async {
  CollaboratorCandidate? result;
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[
        registrationApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () async {
                result = await showCollaboratorPicker(c, alreadyPicked: picked);
              },
              child: const Text('开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  test('★★ 关注数拿不到时显示「—」,不是 0', () {
    expect(
      CollaboratorCandidate.fromJson(<String, dynamic>{'id': 1}).followText,
      '—',
      reason: '"拿不到这个数"和"这个人没有粉丝"是两回事',
    );
    expect(
      CollaboratorCandidate.fromJson(<String, dynamic>{
        'id': 1,
        'followNum': 0,
      }).followText,
      '0',
      reason: '真的是 0 就照实说',
    );
  });

  test('★ 昵称为空时兜底,不留空行', () {
    expect(
      CollaboratorCandidate.fromJson(<String, dynamic>{
        'id': 1,
        'nickname': '  ',
      }).name,
      '未命名用户',
    );
  });

  testWidgets('★★ 已邀请过的不给再邀 —— 重复 id 传后端会变成同一个人被邀两次', (WidgetTester t) async {
    final api = _FakeApi(
      rows: <Map<String, dynamic>>[
        <String, dynamic>{'id': 7, 'nickname': '小李', 'followNum': 12},
        <String, dynamic>{'id': 8, 'nickname': '小王'},
      ],
    );
    await _open(t, api, picked: <int>[7]);

    expect(
      t.widget<CupertinoButton>(find.byKey(const Key('invite-7'))).onPressed,
      isNull,
    );
    expect(find.text('已邀请'), findsOneWidget);
    expect(
      t.widget<CupertinoButton>(find.byKey(const Key('invite-8'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('★ 拿不到 id 的行说「无法邀请」,不是灰着不说话', (WidgetTester t) async {
    await _open(
      t,
      _FakeApi(
        rows: <Map<String, dynamic>>[
          <String, dynamic>{'nickname': '数据不全的人'},
        ],
      ),
    );
    expect(find.text('无法邀请'), findsOneWidget);
  });

  testWidgets('★★ 搜索是真的去搜,不是摆设', (WidgetTester t) async {
    final api = _FakeApi(
      rows: <Map<String, dynamic>>[
        <String, dynamic>{'id': 7, 'nickname': '小李'},
      ],
    );
    await _open(t, api);
    expect(api.lastKeyword, isNull, reason: '首屏不带关键词');

    await t.enterText(find.byType(EditableText), '小王');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(api.lastKeyword, '小王', reason: '搜索框只存值不发请求 = 假控件');
  });

  testWidgets('★★ 空态分清「搜不到」和「一个人都没有」', (WidgetTester t) async {
    await _open(t, _FakeApi());
    expect(find.text('还没有可邀请的合作者'), findsOneWidget);

    await t.enterText(find.byType(EditableText), '张三');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(
      find.text('没有匹配「张三」的用户'),
      findsOneWidget,
      reason: '搜不到时说"还没有可邀请的合作者"是假话',
    );
  });

  testWidgets('★ 加载失败给重试,不吞成空态', (WidgetTester t) async {
    await _open(t, _FakeApi(err: Exception('网络连接超时')));
    expect(find.text('合作者列表没能加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      find.text('还没有可邀请的合作者'),
      findsNothing,
      reason: '把"没加载出来"说成"没有人"是本项目最高频的那类假话',
    );
  });

  testWidgets('选择器是 iOS sheet，搜索使用系统搜索框', (WidgetTester t) async {
    await _open(t, _FakeApi());

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(
      t
          .widget<CupertinoSearchTextField>(
            find.byType(CupertinoSearchTextField),
          )
          .placeholder,
      '搜索',
    );
    expect(find.byKey(const Key('collaborator-cancel')), findsOneWidget);
  });
}
