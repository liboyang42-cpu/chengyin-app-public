// 发官方通知 sheet 的提交失败文案归一(ofc2-01)。
//
// 旧 catch(e) 直接 `e.toString()`:内容安全失败时后端中文原话恰好能看,
// 但 401/断网吐的就是 `DioException [bad response] …` 英文栈。
// 三档口径全部钉死在这里(同 official_guest_401_test / play 域前例):
//   · HTTP 401 → 登录引导话术(dio 层已清 token 并全局跳回 /login);
//   · 后端中文 msg → 原话直用 —— 「内容安全不过时把原因原文返回」的意图保住;
//   · dio 英文栈无 msg → 人话兜底。任何一档都不许出现 DioException 字样。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/official/official_broadcast_sheet.dart';

class _ThrowingApi implements OfficialApi {
  _ThrowingApi(this.failure);

  final Object failure;

  @override
  Future<int> broadcast(Map<String, dynamic> bc) async => throw failure;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _unauthorized() => DioException(
  requestOptions: RequestOptions(path: '/api/official/broadcast'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/official/broadcast'),
    statusCode: 401,
    data: <String, dynamic>{'msg': '登录状态已失效，请重新登录', 'code': 401},
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/api/official/broadcast'),
  type: DioExceptionType.connectionError,
);

/// 打开 sheet → 填标题/受众 → 点提交,等失败文案上屏。
Future<void> _submitFailing(WidgetTester tester, Object failure) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [officialApiProvider.overrideWithValue(_ThrowingApi(failure))],
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            child: const Text('open'),
            onPressed: () => showBroadcastSheet(context),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('broadcast-title')), '周末公告');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('broadcast-send')));
  await tester.tap(find.byKey(const Key('broadcast-send')));
  // pumpAndSettle 会一口气跨过 notice 的 2400ms 自动隐藏,只慢放入场动画。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('★ 401(token 失效)→ 登录引导话术,不吐 dio 英文栈', (
    WidgetTester tester,
  ) async {
    await _submitFailing(tester, _unauthorized());
    expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('★ 后端中文 msg(内容安全)→ 原话直用,告诉他改哪儿', (WidgetTester tester) async {
    await _submitFailing(tester, OfficialApiException('标题包含违规内容,请修改后再发'));
    expect(find.text('标题包含违规内容,请修改后再发'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('★ 断网(dio 栈无中文 msg)→ 人话兜底', (WidgetTester tester) async {
    await _submitFailing(tester, _offline());
    expect(find.text('网络开了点小差'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });
}
