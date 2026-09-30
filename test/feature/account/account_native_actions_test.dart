import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';

import '../../support/fixed_auth.dart';

void main() {
  const List<String> pages = <String>[
    'lib/feature/account/address_list_page.dart',
    'lib/feature/account/participants_page.dart',
    'lib/feature/account/my_likes_page.dart',
  ];

  test('账户常用动作不再使用 Material 按钮或墨水点击层', () {
    const List<String> forbidden = <String>[
      'FloatingActionButton(',
      'TextButton(',
      'IconButton(',
      'FilledButton(',
      'OutlinedButton(',
      'InkWell(',
    ];

    for (final String path in pages) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoButton('), reason: path);
      for (final String materialControl in forbidden) {
        expect(source, isNot(contains(materialControl)), reason: path);
      }
    }
  });

  testWidgets('参与人信息新增和删除动作有 44pt 热区与可读语义', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressListProvider.overrideWith(
            (_) async => <MemberAddress>[
              MemberAddress.fromJson(<String, dynamic>{
                'id': 7,
                'fullName': '林野',
                'mobilePhone': '13800008001',
                'province': '上海市 静安区',
                'detailAddress': '愚园路 1 号',
              }),
            ],
          ),
        ].cast(),
        child: const MaterialApp(home: AddressListPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder add = find.byKey(const Key('address-add'));
    final Finder remove = find.byKey(const Key('address-remove-7'));
    expect(add, findsOneWidget);
    expect(remove, findsOneWidget);
    expect(tester.getSize(add).shortestSide, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(44));

    final SemanticsHandle semantics = tester.ensureSemantics();
    for (final String label in <String>['新增参与人信息', '删除林野']) {
      final SemanticsData data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue, reason: label);
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$label 必须暴露 VoiceOver 点击动作',
      );
    }
    semantics.dispose();
  });

  testWidgets('收藏卡片取消动作有 44pt 热区与可读语义', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          myLikesProvider.overrideWith(
            (_) async => <Topic>[Topic(id: 9, name: '静安微旅行')],
          ),
        ].cast(),
        child: const MaterialApp(home: MyLikesPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 收起态：整张卡可点进详情（语义层）。
    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('打开静安微旅行'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();

    // 取消收藏从卡内浮标改成左滑露出。
    await tester.drag(
      find.byKey(const Key('like-row-9')),
      const Offset(-300, 0),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    final Finder unlike = find.byKey(const Key('swipe-action-unlike-9'));
    expect(unlike, findsOneWidget);
    expect(tester.getSize(unlike).shortestSide, greaterThanOrEqualTo(44));

    final SemanticsHandle revealedSemantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('取消收藏静安微旅行'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    revealedSemantics.dispose();
  });

  testWidgets('参与人编辑与删除动作有独立 44pt 热区与可读语义', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          participantsProvider.overrideWith(
            (_) async => <Participant>[
              Participant.fromJson(<String, dynamic>{
                'id': 5,
                'fullName': '顾青',
                'mobilePhone': '13900001111',
              }),
            ],
          ),
        ].cast(),
        child: const MaterialApp(home: ParticipantsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder edit = find.byKey(const Key('participant-edit-5'));
    final Finder remove = find.byKey(const Key('participant-remove-5'));
    expect(edit, findsOneWidget);
    expect(remove, findsOneWidget);
    expect(tester.getSize(edit).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(44));

    final SemanticsHandle semantics = tester.ensureSemantics();
    for (final String label in <String>['编辑顾青', '删除顾青']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    semantics.dispose();
  });

  testWidgets('200% 动态字号下账户动作仍可访问且不横向溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressListProvider.overrideWith(
            (_) async => <MemberAddress>[
              MemberAddress.fromJson(<String, dynamic>{
                'id': 12,
                'fullName': '一位名字比较长的参与人',
                'mobilePhone': '13800008001',
                'province': '上海市 静安区',
                'detailAddress': '愚园路 1 号',
                'isDefault': 1,
              }),
            ],
          ),
        ].cast(),
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AddressListPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('address-add')), findsOneWidget);
    expect(find.byKey(const Key('address-remove-12')), findsOneWidget);
  });
}
