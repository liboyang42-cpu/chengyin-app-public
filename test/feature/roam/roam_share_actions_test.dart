import 'dart:typed_data';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_session_page.dart';
import 'package:chengyin_app/feature/roam/roam_session_store.dart';
import 'package:chengyin_app/feature/roam/roam_share_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements RoamSessionStore {
  @override
  Future<RoamSession?> findByTs(int ts) async => const RoamSession(
    ts: 1755518400000,
    zone: '静安寺街区',
    distance: 3.4,
    explorePct: 42,
    shops: 2,
    durSec: 2900,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Actions implements RoamShareActions {
  int saves = 0;
  int shares = 0;
  Uint8List? savedBytes;
  Uint8List? sharedBytes;
  Rect? origin;

  @override
  Future<void> saveToAlbum(
    Uint8List pngBytes, {
    required String fileName,
  }) async {
    saves += 1;
    savedBytes = pngBytes;
  }

  @override
  Future<void> share(
    Uint8List pngBytes, {
    required String fileName,
    required Rect sharePositionOrigin,
  }) async {
    shares += 1;
    sharedBytes = pngBytes;
    origin = sharePositionOrigin;
  }
}

class _Encoder implements RoamShareCardEncoder {
  static final Uint8List png = Uint8List.fromList(<int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
  ]);

  @override
  Future<Uint8List> capture(RenderRepaintBoundary boundary) async => png;
}

Future<void> _pump(
  WidgetTester tester,
  RoamShareActions actions, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        roamSessionStoreProvider.overrideWithValue(_Store()),
      ].cast(),
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: RoamSessionPage(
          ts: 1755518400000,
          shareActions: actions,
          shareCardEncoder: _Encoder(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('生成足迹卡'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('足迹卡 Sheet 有保存到相册与系统分享两个真实目标', (WidgetTester tester) async {
    await _pump(tester, _Actions());

    expect(find.text('分享足迹卡'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(find.text('系统分享'), findsOneWidget);
    expect(find.text('返回本次漫游'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('分享足迹卡'),
        matching: find.byType(CupertinoPageScaffold),
      ),
      findsOneWidget,
    );
    expect(find.byType(CupertinoNavigationBar), findsWidgets);
    for (final Key key in const <Key>[
      Key('roam-save-album'),
      Key('roam-system-share'),
      Key('roam-share-back'),
    ]) {
      expect(tester.widget(find.byKey(key)), isA<CupertinoButton>());
    }

    await tester.tap(find.text('返回本次漫游'));
    await tester.pumpAndSettle();
    expect(find.text('分享足迹卡'), findsNothing);
  });

  testWidgets('保存前先说明相册用途，取消不调用系统相册', (WidgetTester tester) async {
    final actions = _Actions();
    await _pump(tester, actions);

    await tester.tap(find.byKey(const Key('roam-save-album')));
    await tester.pumpAndSettle();

    expect(find.text('保存足迹卡到相册'), findsOneWidget);
    expect(find.textContaining('写入系统相册'), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNWidgets(2));
    expect(actions.saves, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(actions.saves, 0);
  });

  testWidgets('大字号下保存与分享改为纵向，不挤压文案', (WidgetTester tester) async {
    await _pump(tester, _Actions(), textScaler: const TextScaler.linear(2));

    final Offset save = tester.getTopLeft(
      find.byKey(const Key('roam-save-album')),
    );
    final Offset share = tester.getTopLeft(
      find.byKey(const Key('roam-system-share')),
    );
    expect(share.dx, save.dx);
    expect(share.dy, greaterThan(save.dy));
  });

  testWidgets('用户确认后将真实 PNG 保存到系统相册', (WidgetTester tester) async {
    final actions = _Actions();
    await _pump(tester, actions);

    await tester.tap(find.byKey(const Key('roam-save-album')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final Finder error = find.byKey(const Key('roam-share-error'));
    expect(
      error,
      findsNothing,
      reason: error.evaluate().isEmpty ? null : tester.widget<Text>(error).data,
    );
    expect(actions.saves, 1);
    expect(actions.savedBytes, isNotNull);
    expect(actions.savedBytes!.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(find.text('已保存到相册'), findsOneWidget);
  });

  testWidgets('系统分享不借相册权限，直接传递 PNG 与 iPad 锚点', (WidgetTester tester) async {
    final actions = _Actions();
    await _pump(tester, actions);

    await tester.tap(find.byKey(const Key('roam-system-share')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(actions.shares, 1);
    expect(actions.saves, 0);
    expect(actions.sharedBytes!.take(8), <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
    expect(actions.origin, isNotNull);
    expect(actions.origin!.isEmpty, isFalse);
    expect(find.text('保存足迹卡到相册'), findsNothing);
  });
}
