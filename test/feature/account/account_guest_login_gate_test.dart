import 'package:chengyin_app/l10n/app_localizations_en.dart';
// B1 账号/资料域修复线 REPORT-sim-account 的行为门禁(2026-09-19)。
//
// 覆盖报告里四条游客可见问题:
//   · P1-1  /address /my-likes /participants /address/edit —— 游客/会话失效
//           不再直出英文 `DioException … 401 …`,统一中文口径 + 登录门;
//   · P1-2  /invites /deregister 游客深链不再被路由静默弹回首页;
//   · P1-3  /address 回到真源「参与人信息」语义,UI 不再调用 setDefault;
//   · P1-4  /address/edit 游客不进空表单。
//
// 游客判定与「去登录」弹层的承接方式同票夹 #231 / 漫游 #208 的修法:
// 门留在页内,登录完人还在原页。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/account/account_login_gate.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/main.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';
import 'package:chengyin_app/l10n/strings_provider.dart';

import '../../support/fixed_auth.dart';
import '../../support/source_text.dart';

/// 游客 401:后端对未登录的原话(HTTP 401 + msg)。
DioException _unauthorized() => DioException(
  type: DioExceptionType.badResponse,
  requestOptions: RequestOptions(path: '/api/user/address/list'),
  response: Response<dynamic>(
    statusCode: 401,
    data: <String, dynamic>{'code': 401, 'msg': '登录状态已失效，请重新登录'},
    requestOptions: RequestOptions(path: '/api/user/address/list'),
  ),
);

DioException _networkDown() => DioException(
  type: DioExceptionType.connectionError,
  requestOptions: RequestOptions(path: '/api/user/address/list'),
  error: Exception('SocketException'),
);

Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(home: home),
);

void main() {
  group('P1-1 口径归一:错误文案函数', () {
    test('401 summary follows selected English language', () {
      final strings = AppLocalizationsEn();
      expect(accountFailureCopy(_unauthorized(), networkFallback: 'Retry', strings: strings), strings.loginExpired);
    });
    test('401 → 后端中文原话,绝不吐 DioException 英文栈', () {
      final String copy = accountFailureCopy(
        _unauthorized(),
        networkFallback: '参与人没能加载出来',
      );
      expect(copy, '登录状态已失效，请重新登录');
      expect(copy.contains('DioException'), isFalse);
    });

    test('断网/超时 → 不推登录,给点名的中文兜底', () {
      expect(
        accountFailureCopy(_networkDown(), networkFallback: '参与人没能加载出来'),
        '参与人没能加载出来',
      );
      expect(accountLoginRequired(_networkDown()), isFalse);
    });

    test('业务失败(HTTP 200 + code≠200)→ 后端中文原话照说', () {
      expect(
        accountFailureCopy(Exception('地址不可用'), networkFallback: '参与人没能加载出来'),
        '地址不可用',
      );
    });
  });

  group('P1-1/P1-4 游客进页:先给登录门,不发注定 401 的请求', () {
    testWidgets('/address 游客 = 门,列表请求一次都不发', (WidgetTester tester) async {
      int listCalls = 0;
      await tester.pumpWidget(
        _app(<dynamic>[
          guestAuthOverride(),
          addressListProvider.overrideWith((_) {
            listCalls++;
            return Future.value(<MemberAddress>[]);
          }),
        ], const AddressListPage()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address-login-gate')), findsOneWidget);
      expect(find.text('登录后查看参与人信息'), findsOneWidget);
      expect(find.text('新增收货地址'), findsNothing);
      expect(listCalls, 0);
    });

    testWidgets('/participants 游客 = 门,列表请求一次都不发', (WidgetTester tester) async {
      int listCalls = 0;
      await tester.pumpWidget(
        _app(<dynamic>[
          guestAuthOverride(),
          participantsProvider.overrideWith((_) {
            listCalls++;
            return Future.value(<Participant>[]);
          }),
        ], const ParticipantsPage(liquidGlassSupported: false)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('participants-login-gate')), findsOneWidget);
      expect(find.text('登录后查看参与人信息'), findsOneWidget);
      expect(listCalls, 0);
    });

    testWidgets('/my-likes 游客 = 门,收藏请求一次都不发', (WidgetTester tester) async {
      int listCalls = 0;
      await tester.pumpWidget(
        _app(<dynamic>[
          guestAuthOverride(),
          myLikesProvider.overrideWith((_) {
            listCalls++;
            return Future.value(<Topic>[]);
          }),
        ], const MyLikesPage()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-likes-login-gate')), findsOneWidget);
      expect(find.text('登录后查看我的收藏'), findsOneWidget);
      expect(listCalls, 0);
    });

    testWidgets('/address/edit 游客不进空表单(P1-4),回读请求也不发', (
      WidgetTester tester,
    ) async {
      int infoCalls = 0;
      await tester.pumpWidget(
        _app(<dynamic>[
          guestAuthOverride(),
          addressApiProvider.overrideWithValue(
            _CountingAddressApi(() => infoCalls++),
          ),
        ], const AddressEditPage(addressId: 5)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address-edit-login-gate')), findsOneWidget);
      expect(find.text('登录后填写参与人信息'), findsOneWidget);
      expect(find.text('保存参与人信息'), findsNothing);
      expect(infoCalls, 0);
    });

    testWidgets('门上的「去登录」就地弹登录层,不是换页', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[guestAuthOverride()], const AddressListPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('去登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('登录城瘾'), findsOneWidget);
    });
  });

  group('P1-1 会话失效(已登录后服务端 401):同一扇门,不是英文栈', () {
    testWidgets('/address 的 401 落到登录门', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          signedInAuthOverride(),
          addressListProvider.overrideWith((_) => throw _unauthorized()),
        ], const AddressListPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录后查看参与人信息'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('/my-likes 的 401 落到登录门', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          signedInAuthOverride(),
          myLikesProvider.overrideWith((_) => throw _unauthorized()),
        ], const MyLikesPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录后查看我的收藏'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('/address/edit 回读 401 → 门,不是一张会清空旧数据的表单', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(_UnauthorizedAddressApi()),
        ], const AddressEditPage(addressId: 5)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address-edit-login-gate')), findsOneWidget);
      expect(find.text('保存参与人信息'), findsNothing);
    });

    testWidgets('非 401 的业务失败仍然原话透传,不被门吞掉', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          signedInAuthOverride(),
          addressListProvider.overrideWith((_) => throw Exception('地址服务在维护')),
        ], const AddressListPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('地址服务在维护'), findsOneWidget);
      expect(find.text('请检查网络后再进来，数据不会丢失'), findsOneWidget);
    });
  });

  group('P1-2 游客深链:停在原页并解释,不再静默弹回首页', () {
    Future<ProviderContainer> boot(WidgetTester tester) async {
      final ProviderContainer container = ProviderContainer(
        retry: (int _, Object _) => null,
        overrides: <dynamic>[guestAuthOverride()].cast(),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ChengyinApp(),
        ),
      );
      return container;
    }

    testWidgets('/invites 游客深链留在邀请页', (WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final ProviderContainer container = await boot(tester);
      container.read(appRouterProvider).go('/invites');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/invites',
      );
      expect(find.byKey(const Key('invites-login-gate')), findsOneWidget);
      expect(find.text('登录后查看邀请记录'), findsOneWidget);

      await tester.tap(find.text('去登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('登录城瘾'), findsOneWidget);
    });

    testWidgets('/deregister 游客深链留在注销页', (WidgetTester tester) async {
      final ProviderContainer container = await boot(tester);
      container.read(appRouterProvider).go('/deregister');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/deregister',
      );
      expect(find.byKey(const Key('deregister-login-gate')), findsOneWidget);
      expect(find.text('登录后注销账号'), findsOneWidget);
    });
  });

  group('P1-3 /address 语义收口', () {
    test('页面不再调用 setDefault,也不再有默认位相关 UI', () {
      final String page = codeOf('lib/feature/account/address_list_page.dart');
      expect(page.contains('setDefault'), isFalse);
      expect(page.contains('设为默认'), isFalse);
      expect(page.contains('默认'), isFalse);
    });

    test('虚构的收货语义已删干净', () {
      final String page = codeOf('lib/feature/account/address_list_page.dart');
      expect(page.contains('收货地址'), isFalse);
      expect(page.contains('寄送实物奖励'), isFalse);
      // 真源标题与行内说明逐字在位(pages/address/address.wxml)。
      expect(page.contains('CyPageTitle(stringsOf(context).accountParticipants)'), isTrue);
      expect(page.contains('accountParticipantPurpose'), isTrue);
      expect(page.contains('label: stringsOf(context).accountParticipantAdd'), isTrue);
    });

    test('设置页不再挂虚构的「收货地址」入口', () {
      final String settings = codeOf('lib/feature/settings/settings_page.dart');
      expect(settings.contains('收货地址'), isFalse);
    });
  });

  group('P2 登录失败落点', () {
    test('微信未配置:不再把用户指向同样走不通的手机号路', () async {
      // isWechatConfigured 恒 false(kWechatAppId 仍是占位符),
      // 该分支在触网/触 SDK 之前返回,直接跑真实 AuthController。
      final ProviderContainer container = ProviderContainer(overrides: [
        appStringsProvider.overrideWithValue(AppLocalizationsZh()),
      ]);
      addTearDown(container.dispose);
      final String? msg = await container
          .read(authControllerProvider.notifier)
          .loginWithWechatApp();
      expect(msg, '暂时无法使用微信登录,请用「通过 Apple 登录」,或稍后再试');
      expect(msg, isNot(contains('手机号登录')));
    });

    test('Apple 取消/设备无 Apple 账户有落点文案,不再死寂(P2-1)', () {
      final String src = codeOf('lib/feature/auth/auth_controller.dart');
      final int at = src.indexOf('AuthorizationErrorCode.canceled');
      expect(at, greaterThan(0));
      final String body = src.substring(at, at + 700);
      expect(body.contains('authAppleIncomplete'), isTrue);
      expect(AppLocalizationsZh().authAppleIncomplete,
          'Apple 登录没有完成。若这台设备还没登录 Apple 账户,'
          '请先在系统「设置 → Apple 账户」登录后再试');
    });
  });
}

class _CountingAddressApi extends Fake implements AddressApi {
  _CountingAddressApi(this.onInfoCall);
  final void Function() onInfoCall;

  @override
  Future<MemberAddress> info(int id) {
    onInfoCall();
    return Future<MemberAddress>.error(Exception('不该被调用'));
  }
}

class _UnauthorizedAddressApi extends Fake implements AddressApi {
  @override
  Future<MemberAddress> info(int id) => throw _unauthorized();
}
