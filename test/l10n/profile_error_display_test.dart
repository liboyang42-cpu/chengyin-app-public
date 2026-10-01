import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';
import 'package:chengyin_app/l10n/error_presentation.dart';
import 'package:chengyin_app/l10n/profile_error_display.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthApi implements AuthApi {
  _AuthApi(this.response);
  final Map<String, dynamic> response;
  @override
  Future<Map<String, dynamic>> userInfo() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('local fallback is translated while identical server text remains original', () {
    final en = AppLocalizationsEn();
    const local = ProfileLoadFailure(ProfileLoadReason.postsFailed);
    const remote = ProfileLoadFailure(ProfileLoadReason.postsFailed, backendMessage: '动态加载失败');
    expect(profileFailureSummary(local, en), 'Could not load posts');
    expect(profileOriginalMessage(local), isNull);
    final display = presentError(remote, en,
      fallback: profileFailureSummary(remote, en), originalApiMessage: profileOriginalMessage(remote));
    expect(display.summary, 'Could not load posts');
    expect(display.detail, '动态加载失败');
    expect(profileFailureSummary(local, AppLocalizationsZh()), '动态加载失败');
  });

  test('provider preserves rejected response message provenance', () async {
    final container = ProviderContainer(retry: (_, _) => null, overrides: [authApiProvider.overrideWithValue(
      _AuthApi({'code': 500, 'msg': '  原始消息  '}))]);
    addTearDown(container.dispose);
    await expectLater(container.read(userInfoProvider.future), throwsA(
      isA<ProfileLoadFailure>()
        .having((e) => e.reason, 'reason', ProfileLoadReason.userInfoRejected)
        .having((e) => e.backendMessage, 'original message', '  原始消息  ')));
  });

  test('missing account body produces local failure rather than fake user', () async {
    final container = ProviderContainer(retry: (_, _) => null, overrides: [authApiProvider.overrideWithValue(_AuthApi({'code': 200}))]);
    addTearDown(container.dispose);
    await expectLater(container.read(userInfoProvider.future), throwsA(
      isA<ProfileLoadFailure>()
        .having((e) => e.reason, 'reason', ProfileLoadReason.missingUser)
        .having((e) => e.backendMessage, 'original message', isNull)));
  });
}
