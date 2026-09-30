import 'dart:async';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_edit_page.dart';
import 'package:chengyin_app/feature/club/club_group_code_page.dart';
import 'package:chengyin_app/feature/club/club_join_requests_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  List<dynamic> overrides = const <dynamic>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pump();
}

void _expectNativeRoot(String title, {int titleCount = 1}) {
  expect(find.byType(CupertinoPageScaffold), findsOneWidget);
  expect(find.byType(CupertinoNavigationBar), findsOneWidget);
  expect(find.byType(Scaffold), findsNothing);
  expect(find.byType(AppBar), findsNothing);
  // titleCount=2 = 导航栏标准标题(手册 §3.2 N1)+ 页内大标题 `CyPageTitle`(D10④)。
  expect(find.text(title), findsNWidgets(titleCount));
}

void main() {
  testWidgets('俱乐部详情使用 Apple 原生导航且保留页内大标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubDetailPage(clubId: 1),
      overrides: <dynamic>[
        clubDetailProvider(
          1,
        ).overrideWith((Ref ref) => Completer<Club>().future),
      ],
    );

    _expectNativeRoot('俱乐部详情', titleCount: 2);
  });

  testWidgets('主理人四步申请使用 Apple 原生导航且保留进度与返回', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubApplyPage(),
      overrides: <dynamic>[
        roleInfoProvider.overrideWith(
          (Ref ref) => Completer<RoleInfo>().future,
        ),
      ],
    );

    _expectNativeRoot('主理人实名');
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('编辑俱乐部使用 Apple 原生导航且保留页内大标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubEditPage(clubId: 1),
      overrides: <dynamic>[
        clubDetailProvider(
          1,
        ).overrideWith((Ref ref) => Completer<Club>().future),
      ],
    );

    _expectNativeRoot('编辑俱乐部');
  });

  testWidgets('入会申请使用 Apple 原生导航且保留空态', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubJoinRequestsPage(clubId: 1),
      overrides: <dynamic>[
        clubJoinRequestsProvider(
          1,
        ).overrideWith((Ref ref) async => const <JoinRequest>[]),
      ],
    );
    await tester.pumpAndSettle();

    _expectNativeRoot('入会申请');
    expect(find.text('还没有入会申请'), findsOneWidget);
  });

  testWidgets('团核销码使用 Apple 原生导航且保留错误态', (WidgetTester tester) async {
    await _pump(tester, page: const ClubGroupCodePage());
    await tester.pump();

    _expectNativeRoot('团核销码');
    // 缺参是终态(不带 activityId/topicId 进来),文案照 pages/club/group-code 原文。
    expect(find.text('缺少路线或场次信息'), findsOneWidget);
  });
}
