import 'dart:async';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/object_card_api.dart';
import 'package:chengyin_app/data/models/object_card.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/object_cards/object_cards_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
  void owner(int? id) => state = AuthState(
    initialized: true,
    user: id == null ? null : User(id: id, nickname: '', avatar: '', role: 'player'),
  );
}

class _Api extends ObjectCardApi {
  _Api() : super(DioClient(TokenStore(const FlutterSecureStorage())));
  final requests = <Completer<ObjectCardCollection>>[];
  @override
  Future<ObjectCardCollection> list({String category = ''}) {
    final request = Completer<ObjectCardCollection>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('guest makes no request; account switch rejects old cards; logout clears', (tester) async {
    final auth = _Auth();
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        objectCardApiProvider.overrideWithValue(api),
      ],
      child: const CupertinoApp(home: ObjectCardsPage()),
    ));
    expect(find.byKey(const Key('object-cards-login')), findsOneWidget);
    expect(api.requests, isEmpty);
    auth.owner(1);
    await tester.pump();
    expect(api.requests, hasLength(1));
    auth.owner(2);
    await tester.pump();
    expect(api.requests, hasLength(2));
    api.requests[1].complete(const ObjectCardCollection(cards: [
      ObjectCard(id: 'new', title: 'New owner', frames: []),
    ], total: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('object-card-new')), findsOneWidget);
    api.requests[0].complete(const ObjectCardCollection(cards: [
      ObjectCard(id: 'old', title: 'Old owner private', frames: []),
    ], total: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('object-card-old')), findsNothing);
    expect(find.byKey(const ValueKey('object-card-new')), findsOneWidget);
    auth.owner(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('object-card-new')), findsNothing);
    expect(find.byKey(const Key('object-cards-login')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
