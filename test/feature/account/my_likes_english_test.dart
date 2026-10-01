// NOT_RUN locally: Flutter SDK unavailable.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int id) => AuthState(initialized: true,
    user: User(id: id, nickname: '用户$id', avatar: '', role: 'player'));
  void switchTo(int id) => state = _state(id);
  void logout() => state = const AuthState(initialized: true);
}

void main() {
  testWidgets('English saved-topic list rejects prior owner response and clears on logout', (t) async {
    final first = Completer<List<Topic>>();
    final auth = _Auth();
    await t.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(() => auth),
      myLikesProvider.overrideWith((ref) async {
        final id = ref.watch(authControllerProvider.select((value) => value.user?.id));
        return id == 1 ? first.future : [Topic(id: 2, name: '新账号主题', picUrl: '')];
      }),
    ], child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MyLikesPage(),
    )));
    await t.pump();
    auth.switchTo(2);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('like-card-2')), findsOneWidget);
    first.complete([Topic(id: 1, name: '旧账号主题', picUrl: '')]);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('like-card-1')), findsNothing);
    final semantics = t.ensureSemantics();
    expect(find.bySemanticsLabel('Open 新账号主题'), findsOneWidget);
    semantics.dispose();
    auth.logout();
    await t.pumpAndSettle();
    expect(find.text('Sign in to view saved topics'), findsOneWidget);
    expect(find.byKey(const Key('like-card-2')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
