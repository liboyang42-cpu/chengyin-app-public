import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';

import '../../support/fixed_auth.dart';

void main() {
  testWidgets('收藏保留小程序 16:9 封面卡片，分享改为左滑露出', (WidgetTester tester) async {
    final _RecordingTopicShareActions share = _RecordingTopicShareActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          myLikesProvider.overrideWith(
            (_) async => <Topic>[
              Topic(
                id: 9,
                name: '静安微旅行',
                picUrl: 'https://example.com/cover.jpg',
              ),
            ],
          ),
          topicShareActionsProvider.overrideWithValue(share),
        ].cast(),
        child: const MaterialApp(home: MyLikesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('like-card-9')), findsOneWidget);
    expect(find.byType(AspectRatio), findsWidgets);

    // 分享从卡内浮标改成左滑露出（交互呈现层，动作集与文案仍 1:1）。
    await tester.drag(
      find.byKey(const Key('like-row-9')),
      const Offset(-300, 0),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    final Finder shareAction = find.byKey(const Key('swipe-action-share-9'));
    expect(shareAction, findsOneWidget);
    expect(tester.getSize(shareAction).shortestSide, greaterThanOrEqualTo(44));

    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('分享静安微旅行'), findsOneWidget);
    semantics.dispose();

    await tester.tap(shareAction);
    await tester.pump();
    expect(share.topic?.id, 9);
    expect(share.origin?.size.shortestSide, greaterThan(0));
  });

  testWidgets('参与人列表保留新增和编辑入口，并进入已有编辑页', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/participants',
      routes: <RouteBase>[
        GoRoute(
          path: '/participants',
          builder: (_, _) =>
              const ParticipantsPage(liquidGlassSupported: false),
        ),
        GoRoute(
          path: '/address/edit',
          builder: (_, _) => const AddressEditPage(),
        ),
        GoRoute(
          path: '/address/edit/:id',
          builder: (_, GoRouterState state) => AddressEditPage(
            addressId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(_FakeAddressApi()),
          participantsProvider.overrideWith(
            (_) async => <Participant>[
              const Participant(
                id: 5,
                fullName: '顾青',
                mobilePhone: '13900001111',
              ),
            ],
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final Finder add = find.byKey(const Key('participant-add'));
    final Finder edit = find.byKey(const Key('participant-edit-5'));
    expect(add, findsOneWidget);
    expect(edit, findsOneWidget);
    expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(edit).height, greaterThanOrEqualTo(44));

    // 编辑要先从同一张地址表按 id 回读；不许把参与人页接到一个空白伪编辑器。
    await tester.tap(edit);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(router.state.uri.path, '/address/edit/5');
    expect(find.byKey(const Key('address-save-participant')), findsOneWidget);
  });
}

class _RecordingTopicShareActions implements TopicShareActions {
  Topic? topic;
  Rect? origin;

  @override
  Future<void> share({required Topic topic, required Rect origin}) async {
    this.topic = topic;
    this.origin = origin;
  }
}

class _FakeAddressApi extends AddressApi {
  _FakeAddressApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<MemberAddress> info(int id) async =>
      const MemberAddress(id: 5, fullName: '顾青', mobilePhone: '13900001111');
}
