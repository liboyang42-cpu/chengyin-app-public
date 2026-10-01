import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/profile_edit.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int id) => AuthState(
    initialized: true,
    user: User(id: id, nickname: 'Account $id', avatar: '', role: 'player'),
  );
  void switchTo(int id) => state = _state(id);
}

class _Api implements RegistrationApi {
  final reads = <Completer<ProfileDetail>>[];
  final saves = <Completer<void>>[];
  @override
  Future<void> updateProfile(ProfileEditForm form) {
    final result = Completer<void>();
    saves.add(result);
    return result.future;
  }
  @override
  Future<ProfileDetail> userDetail({int? memberId}) {
    final result = Completer<ProfileDetail>();
    reads.add(result);
    return result.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProfileDetail _profile(int id, String name) => ProfileDetail(
  id: id, nickname: name, avatar: '', introduction: '', levelId: 1,
  point: 0, followNum: 0, fansNum: 0, likeNum: 0, topicNum: 0, activityNum: 0,
);

void main() {
  testWidgets('late profile from previous account cannot populate English form', (tester) async {
    final api = _Api();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      registrationApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileEditPage(),
      ),
    ));
    await tester.pump();
    expect(api.reads, hasLength(1));
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    await tester.pump();
    await tester.pump();
    expect(api.reads, hasLength(2));
    api.reads[1].complete(_profile(2, '用户原文 B'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.widgetWithText(CupertinoTextField, '用户原文 B'), findsOneWidget);
    api.reads[0].complete(_profile(1, 'Old account A'));
    await tester.pumpAndSettle();
    expect(find.text('Old account A'), findsNothing);
    expect(find.widgetWithText(CupertinoTextField, '用户原文 B'), findsOneWidget);
  });
  testWidgets('save completion from previous account cannot refresh current profile', (tester) async {
    final api = _Api();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      registrationApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileEditPage(),
      ),
    ));
    await tester.pump();
    api.reads.single.complete(_profile(1, 'Account A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'Edited A');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(api.saves, hasLength(1));
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    await tester.pump();
    await tester.pump();
    expect(api.reads, hasLength(2));
    api.reads[1].complete(_profile(2, 'Account B'));
    await tester.pumpAndSettle();
    api.saves.single.complete();
    await tester.pumpAndSettle();
    expect(api.reads, hasLength(2), reason: 'Stale save must not invalidate B');
    expect(find.text('Saved'), findsNothing);
    expect(find.widgetWithText(CupertinoTextField, 'Account B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
