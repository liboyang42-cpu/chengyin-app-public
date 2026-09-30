import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/publish_page.dart';
import 'package:chengyin_app/feature/roam/roam_history_page.dart';
import 'package:chengyin_app/feature/roam/stamp_album_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyStampRoamApi implements RoamApi {
  const _EmptyStampRoamApi();

  @override
  Future<RoamStampPage> stampList({int pageNum = 1, int pageSize = 20}) async =>
      RoamStampPage(
        list: const <RoamStamp>[],
        total: 0,
        pageNum: pageNum,
        pageSize: pageSize,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FilledStampRoamApi implements RoamApi {
  const _FilledStampRoamApi();

  @override
  Future<RoamStampPage> stampList({int pageNum = 1, int pageSize = 20}) async =>
      RoamStampPage(
        list: const <RoamStamp>[
          RoamStamp(
            id: 1,
            picUrl: 'https://example.invalid/stamp.jpg',
            checkState: 1,
          ),
        ],
        total: 1,
        pageNum: pageNum,
        pageSize: pageSize,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 集邮册对游客是登录门,这一组测的是页内结构,所以给一个已登录态。
AuthState _loggedIn() => AuthState(
  initialized: true,
  user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
);

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
  await tester.pumpAndSettle();
}

void _expectNativeRoot(String title) {
  expect(find.byType(CupertinoPageScaffold), findsOneWidget);
  expect(find.byType(CupertinoNavigationBar), findsOneWidget);
  expect(find.byType(AppBar), findsNothing);
  expect(find.text(title), findsOneWidget);
}

void main() {
  testWidgets('快速配置使用 Apple 原生一级导航并保留页内大标题', (WidgetTester tester) async {
    await _pump(tester, page: const PublishPage());

    _expectNativeRoot('快速配置');
  });

  testWidgets('漫游历史使用 Apple 原生导航并保留集邮与实时入口', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const RoamHistoryPage(),
      overrides: <dynamic>[
        roamHistoryProvider.overrideWith(
          (Ref ref) async => const <RoamSession>[],
        ),
      ],
    );

    _expectNativeRoot('漫游历史');
    expect(find.bySemanticsLabel('集邮册'), findsOneWidget);
    expect(find.bySemanticsLabel('实时漫游'), findsOneWidget);
  });

  testWidgets('集邮册使用 Apple 原生一级导航并保留页内大标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const StampAlbumPage(),
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_loggedIn())),
        roamApiProvider.overrideWithValue(const _EmptyStampRoamApi()),
      ],
    );

    _expectNativeRoot('集邮册');
  });

  testWidgets('原生集邮册有邮票时仍在右下角提供 44pt 拍摄入口', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const StampAlbumPage(),
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_loggedIn())),
        roamApiProvider.overrideWithValue(const _FilledStampRoamApi()),
      ],
    );

    final Finder camera = find.byKey(const Key('stamp-camera-fab'));
    expect(camera, findsOneWidget);
    expect(find.bySemanticsLabel('拍摄邮票'), findsOneWidget);
    expect(tester.getSize(camera).height, greaterThanOrEqualTo(44));
  });

  testWidgets('提现记录使用 Apple 原生一级导航且保留空态', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const WithdrawalRecordsPage(),
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_loggedIn())),
        withdrawalRecordsProvider.overrideWith(
          (Ref ref) async => const <WithdrawalRecord>[],
        ),
      ],
    );

    _expectNativeRoot('提现记录');
    // 空态文案逐字贴真源 scene-member-withdraw-history 的 cy-empty。
    expect(find.text('暂无提现记录'), findsOneWidget);
  });
}
