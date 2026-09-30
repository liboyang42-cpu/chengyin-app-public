// 「怎么赚积分」半屏。
//
// ★★ 未登录时后端 **有意**拒绝:生产实测无 token 的
//   `POST /api/points/result_list` 返 HTTP 401 —— 抛的是 DioException。
//   所以判据必须是 HTTP 401([isUnauthorizedError]),不能拿
//   `toString().contains('登录')` 去猜:那串英文里没有「登录」两个字,
//   分支恒不命中,用户看到的就是 6 行英文异常。
//   抛了必须说「登录后可见 + 去登录」,不能渲成「加载失败 + 重试」——
//   那会让用户以为是网络问题、反复点重试,而重试永远不会成功。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/points/points_tasks_sheet.dart';

class _FakeApi implements RegistrationApi {
  _FakeApi({this.rows, this.err});
  final List<Map<String, dynamic>>? rows;
  final Object? err;

  @override
  Future<List<Map<String, dynamic>>> pointsResultList() async {
    if (err != null) throw err!;
    return rows ?? <Map<String, dynamic>>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// 生产实测的游客态:无 token 时 `/api/points/result_list` 返
/// `HTTP 401 {"code":401,"msg":"登录状态已失效，请重新登录"}` —— 抛的是
/// **DioException**,不是 `Exception('请登录')`。
DioException _unauthorized() => DioException(
  requestOptions: RequestOptions(path: '/api/points/result_list'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/points/result_list'),
    statusCode: 401,
  ),
);

/// 断网 / 超时:没有 response,状态码无从谈起 —— 必须仍算故障。
DioException _timeout() => DioException.connectionTimeout(
  timeout: const Duration(seconds: 10),
  requestOptions: RequestOptions(path: '/api/points/result_list'),
);

Future<void> _open(WidgetTester t, _FakeApi api) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        registrationApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () => showPointsTasksSheet(c),
              child: const Text('开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 401 游客走「登录后可见」,不许说加载失败', (WidgetTester t) async {
    await _open(t, _FakeApi(err: _unauthorized()));
    expect(find.text('登录后可见赚分任务'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget, reason: '要给出出路,不是一句结论');
    expect(find.textContaining('加载不出来'), findsNothing);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '重试永远不会成功 —— 摆一个必然无效的按钮',
    );
    expect(
      find.textContaining('DioException'),
      findsNothing,
      reason: '英文异常不许漏给用户(这就是修之前那一屏)',
    );
  });

  testWidgets('★ 真的网络故障才说加载失败,且给重试', (WidgetTester t) async {
    await _open(t, _FakeApi(err: _timeout()));
    expect(find.text('赚分任务加载不出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去登录'), findsNothing, reason: '断网不是要登录');
  });

  testWidgets('★★ 花分规则(eventType=14)不许出现在赚分列表', (WidgetTester t) async {
    await _open(
      t,
      _FakeApi(
        rows: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'eventType': 3,
            'title': '完成一次探店',
            'value': 12,
            'pointsNum': 2,
            'status': 1,
          },
          <String, dynamic>{
            'id': 2,
            'eventType': 14, // 解锁提示 = 花分
            'title': '解锁提示',
            'value': -10,
            'status': 1,
          },
          <String, dynamic>{
            'id': 3,
            'eventType': 5,
            'title': '没启用的规则',
            'value': 99,
            'status': 0,
          },
        ],
      ),
    );
    expect(find.text('完成一次探店'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('已获 2 次'), findsOneWidget);
    expect(find.text('解锁提示'), findsNothing, reason: '花分规则列进赚分列表 = 告诉用户"花分能赚分"');
    expect(find.text('没启用的规则'), findsNothing);
  });

  testWidgets('★ 规则表合法地为空时,说清楚是后台没配', (WidgetTester t) async {
    await _open(t, _FakeApi(rows: <Map<String, dynamic>>[]));
    expect(find.text('暂无积分任务'), findsOneWidget);
  });
}
