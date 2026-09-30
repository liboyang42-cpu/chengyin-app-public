// 广场发布链路:点「发布」到底打到哪个接口、带什么字段、失败了跟用户说什么。
//
// ★ 为什么单独立一条:`/api/creativesquare/action` 是小程序两处发布入口
//   (`pages/square/list` 内嵌编辑器与 `components/cy/post-compose`)共用的唯一发布口,
//   而 App 这边的「发布」原来打在 `/api/v1/community/*` 那一代未落地的链路上 ——
//   按钮、公约弹窗、送审提示全都在,点了没人接,和「没做」在用户那边是一回事。
//
// 断言分两层:
//   - wire 层(打到哪个路径、带哪几个表单字段)用 stub adapter 真发一遍;
//   - 页面层(点了之后调哪个方法、失败说什么)用 stub API,不锁渲染细节。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, MaterialApp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_compose_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

/// 发布键只在 write 灰度打开时可用(`communityPostWrite`)。
class _WriteEnabledFlags extends FeatureFlagsNotifier {
  @override
  Map<String, bool> build() => const <String, bool>{'communityPostWrite': true};
}

class _StubSquareApi implements SquareApi {
  final List<String> calls = <String>[];
  Object? failure;

  int? lastId;
  String? lastContents;
  List<String> lastPics = const <String>[];
  String? lastAddress;
  String? lastLongitude;
  String? lastLatitude;
  int? lastDataId;
  int? lastDataType;
  String? lastRequestId;

  @override
  Future<void> publishPost({
    int? id,
    required String contents,
    List<String> pics = const <String>[],
    String? address,
    String? longitude,
    String? latitude,
    int? dataId,
    int? dataType,
    String? requestId,
  }) async {
    calls.add('publishPost:${id ?? 'new'}');
    lastId = id;
    lastContents = contents;
    lastPics = pics;
    lastAddress = address;
    lastLongitude = longitude;
    lastLatitude = latitude;
    lastDataId = dataId;
    lastDataType = dataType;
    lastRequestId = requestId;
    final Object? error = failure;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions options) reply;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 发帖带图时页面会先上传(`/api/common/uploadOSS`),这里只记「有没有传到」。
class _StubPlayApi implements PlayApi {
  final List<String> uploads = <String>[];

  @override
  Future<String> uploadImage(String filePath) async {
    uploads.add(filePath);
    return 'https://img.test/uploaded.jpg';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 入参是 form 表单(`FormData`),不是 JSON —— 取字段走 `.fields`。
String? _formField(RequestOptions options, String name) {
  final Object? data = options.data;
  if (data is! FormData) return null;
  for (final MapEntry<String, String> field in data.fields) {
    if (field.key == name) return field.value;
  }
  return null;
}

SquareApi _apiWith(_StubAdapter adapter) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  return SquareApi(client);
}

List<dynamic> _overrides(_StubSquareApi api, _StubPlayApi playApi) => <dynamic>[
  squareApiProvider.overrideWithValue(api),
  playApiProvider.overrideWithValue(playApi),
  featureFlagsProvider.overrideWith(_WriteEnabledFlags.new),
  authControllerProvider.overrideWith(_LoggedInAuth.new),
];

Future<void> _pumpCompose(
  WidgetTester tester, {
  required _StubSquareApi api,
  _StubPlayApi? playApi,
  SquarePost? initialPost,
}) async {
  // 走真 GoRouter:页面的成功落点是 `context.pop()`,那是 go_router 的方法 ——
  // 用裸 Navigator 搭台会把 pop 变成异常,测出来的是假失败。
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  key: Key('open-compose'),
                  onPressed: null,
                  child: Text('发帖'),
                ),
              ),
            ),
      ),
      GoRoute(
        path: '/square/compose',
        builder: (BuildContext context, GoRouterState state) =>
            SquareComposePage(initialPost: initialPost),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(api, playApi ?? _StubPlayApi()).cast(),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          DefaultMaterialLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/square/compose');
  await tester.pumpAndSettle();
}

/// 确认弹窗里的那颗按钮(页面上常有同名文案)。
Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _write(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('square-compose-content')), text);
  await tester.pump();
}

Future<void> _tapPublish(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('square-compose-submit')));
  // 不用 pumpAndSettle:发布中的转圈是**无限动画**,settle 不下来;
  // 而提示条本身 2.4s 后会自己收,settle 过去就把要断言的那句话也等没了。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  group('wire:/\u002fapi/creativesquare/action', () {
    test('新建:字段与小程序逐一对齐,pics 用英文分号连接', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'id': 123},
        },
      );
      await _apiWith(adapter).publishPost(
        contents: '江边的风',
        pics: <String>['https://img.test/a.jpg', 'https://img.test/b.jpg'],
        address: '昌平路桥',
        longitude: '121.4455',
        latitude: '31.2312',
        dataId: 91,
        dataType: 1,
        requestId: 'square-1789000000000000',
      );

      final RequestOptions options = adapter.sent.single;
      expect(options.path, '/api/creativesquare/action');
      expect(options.method, 'POST');
      expect(_formField(options, 'contents'), '江边的风');
      expect(
        _formField(options, 'pics'),
        'https://img.test/a.jpg;https://img.test/b.jpg',
      );
      expect(_formField(options, 'address'), '昌平路桥');
      expect(_formField(options, 'longitude'), '121.4455');
      expect(_formField(options, 'latitude'), '31.2312');
      expect(_formField(options, 'data_id'), '91');
      expect(_formField(options, 'data_type'), '1');
      expect(_formField(options, 'request_id'), 'square-1789000000000000');
      expect(_formField(options, 'id'), isNull, reason: '新建不带 id');
    });

    test('编辑:只发 id + 正文 + 关联 —— 图片/地点/意图键都不发', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{'code': 200},
      );
      await _apiWith(adapter).publishPost(
        id: 7,
        contents: '改过的正文',
        pics: <String>['https://img.test/should-not-send.jpg'],
        address: '不该发的地点',
        longitude: '121.0',
        latitude: '31.0',
        dataId: 91,
        dataType: 1,
        requestId: 'square-1789000000000000',
      );

      final RequestOptions options = adapter.sent.single;
      expect(options.path, '/api/creativesquare/action');
      expect(_formField(options, 'id'), '7');
      expect(_formField(options, 'contents'), '改过的正文');
      expect(_formField(options, 'data_id'), '91');
      expect(_formField(options, 'data_type'), '1');
      expect(
        _formField(options, 'pics'),
        isNull,
        reason: '编辑态不发图片:后端 R10-06 未提交字段保留原值,发了会覆盖',
      );
      expect(_formField(options, 'address'), isNull);
      expect(_formField(options, 'longitude'), isNull);
      expect(_formField(options, 'latitude'), isNull);
      expect(
        _formField(options, 'request_id'),
        isNull,
        reason: '编辑是幂等 update,不占意图键',
      );
    });

    test('没有关联时不发 data_id/data_type(后端按「无值即清 0」理解)', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{'code': 200},
      );
      await _apiWith(adapter).publishPost(contents: '随手一发');

      expect(_formField(adapter.sent.single, 'data_id'), isNull);
      expect(_formField(adapter.sent.single, 'data_type'), isNull);
      expect(_formField(adapter.sent.single, 'pics'), '');
    });

    test('后端非 200:抛发布异常并原话透传,不兜底', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{'code': 500, 'msg': '内容未通过审核，请修改后重新发布'},
      );
      await expectLater(
        _apiWith(adapter).publishPost(contents: '违规内容'),
        throwsA(
          isA<SquarePublishException>().having(
            (SquarePublishException e) => e.message,
            'message',
            '内容未通过审核，请修改后重新发布',
          ),
        ),
      );
    });
  });

  group('页面:发布', () {
    testWidgets('正文必填:空文/纯空白都不发请求(小程序同款闸)', (WidgetTester tester) async {
      final _StubSquareApi api = _StubSquareApi();
      await _pumpCompose(tester, api: api);

      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const Key('square-compose-submit')),
            )
            .onPressed,
        isNull,
      );
      await _tapPublish(tester);
      await _write(tester, '   ');
      await _tapPublish(tester);
      expect(api.calls, isEmpty);
    });

    testWidgets('点发布:正文 trim 后发出去,带上幂等意图键,发完回列表', (WidgetTester tester) async {
      final _StubSquareApi api = _StubSquareApi();
      await _pumpCompose(tester, api: api);

      await _write(tester, '  江边的风  ');
      await _tapPublish(tester);

      expect(api.calls, <String>['publishPost:new']);
      expect(api.lastContents, '江边的风', reason: '两端都是 trim 后判空/发送');
      expect(api.lastId, isNull);
      expect(
        api.lastRequestId,
        matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')),
        reason: '后端要求 16-64 位意图键,重试要复用同一个',
      );
      expect(find.text('已发布'), findsOneWidget);
      expect(
        find.byType(SquareComposePage),
        findsNothing,
        reason: '成功要回列表:列表那一次刷新就是回执',
      );
    });

    testWidgets('编辑:带 id 与关联,图片/地点/关联工具收起(R10-06 后端保留原值)', (
      WidgetTester tester,
    ) async {
      const SquarePost post = SquarePost(
        id: 7,
        memberId: 99,
        contents: '原正文',
        pics: <String>['https://img.test/old.jpg'],
        referenceType: 'ACTIVITY',
        referenceId: 91,
        dataId: 91,
        dataType: 1,
      );
      final _StubSquareApi api = _StubSquareApi();
      await _pumpCompose(tester, api: api, initialPost: post);

      expect(find.byKey(const Key('square-compose-photo')), findsNothing);
      expect(find.byKey(const Key('square-compose-location')), findsNothing);
      expect(find.byKey(const Key('square-compose-activity')), findsNothing);

      await _write(tester, '改过的正文');
      await _tapPublish(tester);

      expect(api.calls, <String>['publishPost:7']);
      expect(api.lastContents, '改过的正文');
      expect(api.lastDataId, 91, reason: '编辑重发关联:不发后端会清 0');
      expect(api.lastDataType, 1);
      expect(find.text('已保存'), findsOneWidget);
    });

    testWidgets('图片上限 6 张:到顶再点「照片」只说话,不开选择器', (WidgetTester tester) async {
      // 草稿恢复出 6 张图,再点「照片」—— 闸必须在打开系统选择器**之前**。
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'community_post_local_draft_v4:99:new': jsonEncode(<String, dynamic>{
          'memberId': 99,
          'workflowId': 'square-1789000000000000',
          'contents': '带图草稿',
          'pics': <String>[
            'https://img.test/1.jpg',
            'https://img.test/2.jpg',
            'https://img.test/3.jpg',
            'https://img.test/4.jpg',
            'https://img.test/5.jpg',
            'https://img.test/6.jpg',
          ],
        }),
      });
      final _StubSquareApi api = _StubSquareApi();
      await _pumpCompose(tester, api: api);

      await tester.tap(find.byKey(const Key('square-compose-photo')));
      await tester.pumpAndSettle();

      expect(find.text('最多 6 张图片'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('照片:选完先传到 /api/common/uploadOSS,发布时地址进 pics', (
      WidgetTester tester,
    ) async {
      // 系统选择器走平台通道,测试里把返回值钉成一张本地图。
      const MethodChannel picker = MethodChannel(
        'plugins.flutter.io/image_picker',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (MethodCall call) async =>
            call.method == 'pickImage' ? '/tmp/pick.jpg' : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      final _StubPlayApi play = _StubPlayApi();
      final _StubSquareApi api = _StubSquareApi();
      await _pumpCompose(tester, api: api, playApi: play);

      await _write(tester, '江边的风');
      await tester.tap(find.byKey(const Key('square-compose-photo')));
      await tester.pumpAndSettle();

      expect(play.uploads, <String>['/tmp/pick.jpg']);
      expect(find.byType(SquareComposeThumb), findsOneWidget);

      await _tapPublish(tester);
      expect(api.lastPics, <String>['https://img.test/uploaded.jpg']);
    });
  });

  group('页面:失败', () {
    testWidgets('内容被拒:弹窗说清楚并给「去修改」,不偷偷重试', (WidgetTester tester) async {
      final _StubSquareApi api = _StubSquareApi()
        ..failure = SquarePublishException('内容未通过审核，请修改后重新发布');
      await _pumpCompose(tester, api: api);

      await _write(tester, '含有敏感词的正文');
      await _tapPublish(tester);

      expect(find.text('内容没能通过审核'), findsOneWidget);
      expect(
        find.textContaining('内容未通过审核，请修改后重新发布'),
        findsOneWidget,
        reason: '失败要原文透传,不许改写成兜底话术',
      );
      await _tapDialogAction(tester, '去修改');
      expect(api.calls, <String>['publishPost:new'], reason: '重试不会让它通过,不该自动重发');
    });

    testWidgets('不是自己的帖:权限态单独说,不给「重试」的错觉', (WidgetTester tester) async {
      final _StubSquareApi api = _StubSquareApi()
        ..failure = SquarePublishException('无权编辑该内容');
      await _pumpCompose(tester, api: api);

      await _write(tester, '改别人的帖');
      await _tapPublish(tester);

      expect(find.text('不能编辑这条内容'), findsOneWidget);
      expect(find.textContaining('无权编辑该内容'), findsOneWidget);
    });

    testWidgets('临时故障:原话摆出来 + 正文还在 + 草稿存本机,人没被赶走', (WidgetTester tester) async {
      final _StubSquareApi api = _StubSquareApi()
        ..failure = SquarePublishException('发布结果确认中，请稍后重试');
      await _pumpCompose(tester, api: api);

      await _write(tester, '江边的风');
      await _tapPublish(tester);

      expect(find.textContaining('发布结果确认中，请稍后重试'), findsOneWidget);
      expect(find.byType(SquareComposePage), findsOneWidget, reason: '没发出去就别走');
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('square-compose-content')),
            )
            .controller
            ?.text,
        '江边的风',
      );
      expect(find.textContaining('已保存在本机'), findsOneWidget);
    });

    testWidgets('网络层失败:说人话(不把 DioException 原文怼给用户)', (
      WidgetTester tester,
    ) async {
      final _StubSquareApi api = _StubSquareApi()
        ..failure = DioException(
          requestOptions: RequestOptions(path: '/api/creativesquare/action'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        );
      await _pumpCompose(tester, api: api);

      await _write(tester, '江边的风');
      await _tapPublish(tester);

      expect(find.textContaining('网络错误，请检查连接后重试'), findsOneWidget);
    });
  });
}
