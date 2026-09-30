// official 域游客 401 收口(b1-sim-official 报告 ofc-06 / ofc-01)。
//
// ★ 实况(报告 §3 P1-1,截图 ofc-06):`/official-mine` 游客把
//   `DioException [bad response]: … 401 … developer.mozilla.org` 糊满屏幕。
//   同型死路还有两处:events 页「我的」档(`/api/official/my-events`)、
//   承接邀约收件箱(`/api/official/v2/party-inbox`)——游客都必撞 HTTP 401。
//
// 口径照 play 域前例(38790273,my_plays_guest_401_test):
//   · 401 → 可恢复的登录引导「去登录」;
//   · 500 带中文 msg → 后端原话;
//   · 断网 → 通用中文兜底,**不**推人去登录。
// 反面同样守住:权限态(HTTP 200 +「无官方发布权限」)不走登录引导
//   —— 那条分流已由 official_mine_permission_test 锁住。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/official/official_controller.dart'
    show myPublishedProvider, partyInboxProvider, officialErrorSub;
import 'package:chengyin_app/feature/official/official_events_page.dart';
import 'package:chengyin_app/feature/official/official_inbox_page.dart';
import 'package:chengyin_app/feature/official/official_mine_page.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart';

DioException _http(String path, int status, {Object? body}) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: body,
  ),
);

DioException _offline(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

DioException _unauthorized(String path) => _http(
  path,
  401,
  body: <String, dynamic>{'msg': '登录状态已失效，请重新登录', 'code': 401},
);

void main() {
  group('/official-mine 我发布的(ofc-06)', () {
    Widget page(Object error) => ProviderScope(
      overrides: [
        myPublishedProvider.overrideWith((_) async => throw error),
        officialCanPublishProvider.overrideWith((_) async => false),
      ],
      child: const MaterialApp(home: OfficialMinePage()),
    );

    testWidgets('401(游客)→ 登录引导,不画 dio 异常原文', (tester) async {
      await tester.pumpWidget(
        page(_unauthorized('/api/official/my-published')),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看我发布的内容'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('发布记录没能加载出来'), findsNothing);
    });

    testWidgets('500 → 后端中文原话,不画 dio 异常原文', (tester) async {
      await tester.pumpWidget(
        page(
          _http(
            '/api/official/my-published',
            500,
            body: <String, dynamic>{'msg': '服务器开小差了'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发布记录没能加载出来'), findsOneWidget);
      expect(find.text('服务器开小差了'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('断网 → 通用兜底,不推登录', (tester) async {
      await tester.pumpWidget(page(_offline('/api/official/my-published')));
      await tester.pumpAndSettle();
      expect(find.text('网络开了点小差'), findsOneWidget);
      expect(find.text('登录后查看我发布的内容'), findsNothing);
    });
  });

  group('/official-inbox 承接邀约(ofc-01 落点)', () {
    Widget page(Object error) => ProviderScope(
      overrides: [partyInboxProvider.overrideWith((_) async => throw error)],
      child: const MaterialApp(home: OfficialInboxPage()),
    );

    testWidgets('401(游客)→ 登录引导,不画 dio 异常原文', (tester) async {
      await tester.pumpWidget(
        page(_unauthorized('/api/official/v2/party-inbox')),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录后查看承接邀约'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('断网 → 错误态,不推登录', (tester) async {
      await tester.pumpWidget(page(_offline('/api/official/v2/party-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('承接邀约没能加载出来'), findsOneWidget);
      expect(find.text('网络开了点小差'), findsOneWidget);
      expect(find.text('登录后查看承接邀约'), findsNothing);
    });
  });

  group('/official-events「我的」档(ofc-01 落点)', () {
    testWidgets('401(游客)→ 登录引导,公开档的 200 空列表不受牵连', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 公开列表游客可拿 200 data:[](报告 §3 P2-2 的 curl 实测)。
            officialEventsProvider.overrideWith((_) async => <OfficialEvent>[]),
            myOfficialEventsProvider.overrideWith(
              (_) async => throw _unauthorized('/api/official/my-events'),
            ),
            officialCanPublishProvider.overrideWith((_) async => false),
          ],
          child: const MaterialApp(home: OfficialEventsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      expect(find.text('登录后查看我参与的活动'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });
  });

  test('officialErrorSub:非 dio 异常/OfficialApiException 保留后端原话', () {
    expect(officialErrorSub(OfficialApiException('无官方发布权限')), '无官方发布权限');
    expect(
      officialErrorSub(_offline('/x')).contains('DioException'),
      isFalse,
      reason: '兜底文案不能又把异常原文吐回去',
    );
  });
}
