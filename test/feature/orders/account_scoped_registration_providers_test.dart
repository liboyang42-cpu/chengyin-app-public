import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  void switchTo(int? id) => state = _state(id);
  static AuthState _state(int? id) => AuthState(
    initialized: true,
    user: id == null ? null : User(id: id, nickname: '$id', avatar: '', role: 'player'),
  );
}

class _Api extends Fake implements ActivityApi {
  final lists = <Completer<List<MyRegistration>>>[];
  final details = <Completer<RegistrationDetail>>[];
  Future<List<MyRegistration>> _list() {
    final call = Completer<List<MyRegistration>>();
    lists.add(call);
    return call.future;
  }
  @override
  Future<List<MyRegistration>> orderList({String? status}) => _list();
  @override
  Future<List<MyRegistration>> myJoined() => _list();
  @override
  Future<RegistrationDetail> ticketInfo(int id) {
    final call = Completer<RegistrationDetail>();
    details.add(call);
    return call.future;
  }
}

void main() {
  testWidgets('failed second-account load does not retain first-account orders', (tester) async {
    final api = _Api();
    final auth = _Auth();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        activityApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: OrdersPage()),
    ));
    api.lists.single.complete([MyRegistration(
      id: 11, ownerType: 2, ownerId: 7, title: 'First account private order',
      registrationStatus: 2,
    )]);
    await tester.pumpAndSettle();
    expect(find.text('First account private order'), findsOneWidget);
    auth.switchTo(2);
    await tester.pump();
    api.lists[1].completeError(Exception('Second account request failed'));
    await tester.pumpAndSettle();
    expect(find.text('First account private order'), findsNothing);
    expect(find.text('订单暂时没有加载出来'), findsOneWidget);
  });

  for (final provider in [myOrdersProvider, myJoinedActivitiesProvider]) {
    test('account change discards delayed registration list: $provider', () async {
      final api = _Api();
      final auth = _Auth();
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => auth),
        activityApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      container.listen(provider, (_, _) {});
      expect(api.lists, hasLength(1));
      auth.switchTo(2);
      final current = container.read(provider.future);
      expect(api.lists, hasLength(2));
      api.lists[1].complete([MyRegistration(id: 22, ownerType: 2, ownerId: 7)]);
      expect((await current).single.id, 22);
      api.lists[0].complete([MyRegistration(id: 11, ownerType: 2, ownerId: 7)]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue.single.id, 22);
      auth.switchTo(null);
      expect(await container.read(provider.future), isEmpty);
      expect(api.lists, hasLength(2), reason: 'Guests must not request account lists');
    });
  }

  for (final provider in [orderDetailProvider(7), ticketDetailProvider(7)]) {
    test('account change discards delayed detail: $provider', () async {
      final api = _Api();
      final auth = _Auth();
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => auth),
        activityApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      container.listen(provider, (_, _) {});
      auth.switchTo(2);
      final current = container.read(provider.future);
      expect(api.details, hasLength(2));
      api.details[1].complete(const RegistrationDetail(
        id: 7, ownerType: 2, ownerId: 7, entitlements: [], realName: 'Second account',
      ));
      expect((await current).realName, 'Second account');
      api.details[0].complete(const RegistrationDetail(
        id: 7, ownerType: 2, ownerId: 7, entitlements: [], realName: 'First account',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue.realName, 'Second account');
      auth.switchTo(null);
      await expectLater(container.read(provider.future), throwsException);
      expect(api.details, hasLength(2), reason: 'Guests must not request account details');
    });
  }
}
