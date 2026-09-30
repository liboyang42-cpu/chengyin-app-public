// 履约链整页快照:票卡详情 / 出示核销码 / 商家扫码。
//
// 与 pages_golden_test.dart(票夹/订单)互补,这里覆盖的是「一张票买到之后
// 的履约闭环」:玩家看还剩几章 → 出码给商家扫 → 商家核销出结果。
//
// 不碰网络的三条做法:
//  1. ticketDetailProvider 是 family,overrideWith((ref, id) async => ...)。
//  2. PassPage / MerchantScanPage 都走 activityApiProvider,override 成
//     假的 ActivityApi 子类,只覆写 issueDynamicCode / scanDynamicCode。
//  3. PassPage「正常态」的二维码图由 Image.network 加载 —— 测试环境里
//     HttpClient 恒 400,这里用 debugNetworkImageHttpClientProvider(Flutter
//     官方为测试留的钩子)喂一张程序生成的 QR 样张,再用 runAsync 放行
//     dart:ui 的解码;看完立即置回 null(否则框架的 postTest 检查会红)。
//
// ⚠️ PassPage 的倒计时用 DateTime.now() 实时算,天然不可复现 —— 测试里
//    用 _FixedDynCode 覆写 remaining() 把倒计时钉死在固定值,否则 golden
//    每跑一次数字都不同,永远对不上。这是本文件内自制的确定性,不算改库。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_fulfil_golden_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'golden_theme.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/merchant/merchant_scan_page.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:chengyin_app/data/models/explore_completion.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/explore_completion_section.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// ★ MerchantScanPage 在真机上是**浅色**的(路由包了 _merchantLight)——
///   用深色拍出来的黑底是没人会看到的画面。
///   2026-08-19 由 merchant_routes_are_light 那条新门禁抓出来的存量问题。
///
/// ★ 票夹域的详情/出码页对**游客**会换成登录门(#231 P1),而基准图拍的是
///   有票可看、有码可出的那种画面 —— 那里必然有人在登录态,统一摆好。
class _GoldenAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

Widget _app(List<dynamic> overrides, Widget home, {bool light = false}) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GoldenAuth.new),
      ...overrides,
    ].cast(),
    child: MaterialApp(
      theme: light ? merchantGoldenTheme() : goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

// ── 假数据 ────────────────────────────────────────────────────────────────

/// ③ 探索票:待核销 / 已核销 / 已失效 各一章。
RegistrationDetail _exploreDetail() => RegistrationDetail.fromJson(<String, dynamic>{
  'id': 9001,
  'ownerType': 2,
  'ownerId': 3301,
  'registrationNo': 'R20260818001',
  'registrationStatus': 2,
  'verificationStatus': 1,
  'purchaseKind': 'EXPLORE_PASS',
  'realName': '李某',
  'phone': '138****8000',
  'participateDate': '2026-08-24 14:00',
  'cmsActivity': <String, dynamic>{'name': '静安探店日 · 第一期'},
  'entitlements': <dynamic>[
    <String, dynamic>{'id': 1, 'status': 1, 'chapterId': 11, 'chapterName': '第一站 · 咖啡', 'statusLabel': '已核销'},
    <String, dynamic>{'id': 2, 'status': 0, 'chapterId': 12, 'chapterName': '第二站 · 书店', 'statusLabel': '待核销'},
    <String, dynamic>{'id': 3, 'status': 2, 'chapterId': 13, 'chapterName': '第三站 · 展览', 'statusLabel': '已失效'},
  ],
});

/// ③ 探索票已全部核销完(还有章节行,但 pendingCount=0 → 按钮禁用)。
RegistrationDetail _exploreDoneDetail() => RegistrationDetail.fromJson(<String, dynamic>{
  'id': 9002,
  'ownerType': 2,
  'ownerId': 3301,
  'registrationNo': 'R20260818002',
  'registrationStatus': 2,
  'verificationStatus': 1,
  'purchaseKind': 'EXPLORE_PASS',
  'realName': '李某',
  'phone': '138****8000',
  'participateDate': '2026-08-10 14:00',
  'cmsActivity': <String, dynamic>{'name': '徐汇咖啡巡礼 · 周末场'},
  'entitlements': <dynamic>[
    <String, dynamic>{'id': 1, 'status': 1, 'chapterId': 21, 'chapterName': '第一站 · 手冲', 'statusLabel': '已核销'},
    <String, dynamic>{'id': 2, 'status': 1, 'chapterId': 22, 'chapterName': '第二站 · 拉花', 'statusLabel': '已核销'},
  ],
});

/// 非 ③ 票:无 entitlements,已核销 → 按钮禁用。
RegistrationDetail _plainDetail() => RegistrationDetail.fromJson(<String, dynamic>{
  'id': 9003,
  'ownerType': 2,
  'ownerId': 3301,
  'registrationNo': 'R20260818003',
  'registrationStatus': 2,
  'verificationStatus': 1,
  'purchaseKind': 'NORMAL',
  'realName': '王某',
  'phone': '139****9000',
  'participateDate': '2026-08-15 19:00',
  'cmsActivity': <String, dynamic>{'name': '经典定向 · 老城漫步'},
});

/// 倒计时钉死:PassPage 每秒重算 _remaining,但 DateTime.now() 不可复现,
/// 必须覆写 remaining() 才拿得到稳定 golden。
class _FixedDynCode extends DynCode {
  _FixedDynCode({
    required super.code,
    required super.expiresAt,
    super.qrcodeUrl,
    this.fixedRemaining = const Duration(minutes: 5),
  });

  final Duration fixedRemaining;

  @override
  Duration remaining() => fixedRemaining;
}

/// 假 API:PassPage 只调 issueDynamicCode,MerchantScanPage 只调 scanDynamicCode。
class _FakeActivityApi extends ActivityApi {
  _FakeActivityApi({required this.dynCode, this.scanError})
    : super(_dummyDioClient());

  final DynCode dynCode;

  /// 非 null 时 scanDynamicCode 抛这条后端原因。
  final String? scanError;

  static DioClient _dummyDioClient() =>
      DioClient(TokenStore(const FlutterSecureStorage()));

  @override
  Future<DynCode> issueDynamicCode(int registrationId) async => dynCode;

  @override
  Future<Map<String, dynamic>> scanDynamicCode(String code) async {
    if (scanError != null) throw Exception(scanError);
    return <String, dynamic>{'redemptionId': 1001, 'chapterId': 3};
  }
}

// ── 假 HttpClient(只喂 Image.network 用,NetworkImage 只用 getUrl/close) ──

/// NetworkImage 在测试环境恒 400,连不上 OSS —— 用 Flutter 官方测试钩子
/// debugNetworkImageHttpClientProvider 换成这个假客户端,返回程序生成的
/// QR 样张 PNG。没实现的方法靠 noSuchMethod 兜住,真被调用就炸出来。
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._bytes);
  final Uint8List _bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest(_bytes);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpClient 不支持: $invocation');
}

class _FakeHttpRequest extends Stream<List<int>> implements HttpClientRequest {
  _FakeHttpRequest(this._bytes);
  final Uint8List _bytes;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse(_bytes);

  @override
  Future<HttpClientResponse> get done async => _FakeHttpResponse(_bytes);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpClientRequest 不支持: $invocation');
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse(this._bytes);
  final Uint8List _bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpClientResponse 不支持: $invocation');
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpHeaders 不支持: $invocation');
}

/// 程序生成的 QR 样张:白底 + 21×21 确定性点阵 + 三处定位角。
/// 目的不是画真二维码,是让「正常态」能看见码图已占位(区别于回落态的文字)。
Future<Uint8List> _qrSamplePng() async {
  const int grid = 21;
  const double size = 120;
  final double cell = size / grid;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final ui.Paint white = ui.Paint()..color = const Color(0xFFFFFFFF);
  final ui.Paint ink = ui.Paint()..color = const Color(0xFF0F172B);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), white);

  final Random rng = Random(7);
  for (int y = 0; y < grid; y++) {
    for (int x = 0; x < grid; x++) {
      // 定位角区域留空,交给下面单独画,避免把角抹花。
      final bool inFinder =
          (x < 7 && y < 7) || (x >= grid - 7 && y < 7) || (x < 7 && y >= grid - 7);
      if (!inFinder && rng.nextDouble() < 0.45) {
        canvas.drawRect(
          ui.Rect.fromLTWH(x * cell, y * cell, cell, cell),
          ink,
        );
      }
    }
  }
  // 三个定位角:外框黑 + 中心白心。
  for (final (int fx, int fy) in <(int, int)>[(0, 0), (grid - 7, 0), (0, grid - 7)]) {
    canvas.drawRect(
      ui.Rect.fromLTWH(fx * cell, fy * cell, 7 * cell, 7 * cell),
      ink,
    );
    canvas.drawRect(
      ui.Rect.fromLTWH((fx + 2) * cell, (fy + 2) * cell, 3 * cell, 3 * cell),
      white,
    );
  }

  final ui.Image image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late Uint8List _qrPng;

  setUpAll(() async {
    _qrPng = await _qrSamplePng();
  });

  group('票卡详情', () {
    testWidgets('③ 探索票:三态章节各一 + 可出码', (WidgetTester tester) async {
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            ticketDetailProvider.overrideWith((ref, int id) async => _exploreDetail()),
            // ★ ③ 票会真去拉完局面 —— 不给替身就一直 pending,pumpAndSettle 超时。
            //   顺便把这块拍进基准图:还没走完的那种(说清还差几家店)。
            exploreCompletionProvider(9001).overrideWith(
                (ref) async => ExploreCompletion.fromJson(<String, dynamic>{
                      'completed': false,
                      'requiredChapterCount': 3,
                      'redeemedChapterCount': 1,
                      'stamps': <dynamic>[
                        <String, dynamic>{
                          'chapterId': 1,
                          'title': '静安咖啡',
                          'collected': true,
                        },
                        <String, dynamic>{'chapterId': 2, 'title': '愚园书店'},
                      ],
                    })),
          ],
          const TicketDetailPage(registrationId: 9001),
        ),
      );
      // 先出骨架屏(带呼吸动画),两拍后进数据态再截。
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_ticket_detail_explore.png'),
      );
    });

    testWidgets('③ 探索票已核销完:按钮禁用「该票已核销完」', (WidgetTester tester) async {
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            ticketDetailProvider.overrideWith((ref, int id) async => _exploreDoneDetail()),
            // 走完了、奖励已到账的那种:勋章没有数量(不显示 +0),积分有。
            exploreCompletionProvider(9002).overrideWith(
                (ref) async => ExploreCompletion.fromJson(<String, dynamic>{
                      'completed': true,
                      'requiredChapterCount': 2,
                      'redeemedChapterCount': 2,
                      'stamps': <dynamic>[
                        <String, dynamic>{
                          'chapterId': 1,
                          'title': '静安咖啡',
                          'collected': true,
                        },
                        <String, dynamic>{
                          'chapterId': 2,
                          'title': '愚园书店',
                          'collected': true,
                        },
                      ],
                      'awards': <String, dynamic>{
                        'credited': true,
                        'items': <dynamic>[
                          <String, dynamic>{
                            'kind': 'BADGE',
                            'title': '静安夜行徽章',
                          },
                          <String, dynamic>{
                            'kind': 'POINTS',
                            'title': '积分',
                            'amount': 120,
                          },
                        ],
                      },
                    })),
          ],
          const TicketDetailPage(registrationId: 9002),
        ),
      );
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_ticket_detail_explore_done.png'),
      );
    });

    testWidgets('非 ③ 票:无权益明细,按钮禁用', (WidgetTester tester) async {
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            ticketDetailProvider.overrideWith((ref, int id) async => _plainDetail()),
          ],
          const TicketDetailPage(registrationId: 9003),
        ),
      );
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_ticket_detail_plain.png'),
      );
    });
  });

  group('出示核销码', () {
    testWidgets('回落态:二维码不可用 → 白卡内深字码文本 + 四角框', (WidgetTester tester) async {
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            activityApiProvider.overrideWithValue(
              _FakeActivityApi(
                dynCode: _FixedDynCode(
                  code: 'CY.9001.activity.aB3xQ7',
                  expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
                  qrcodeUrl: null,
                ),
              ),
            ),
          ],
          const PassPage(registrationId: 9001),
        ),
      );
      await tester.pump(); // issueDynamicCode 完成 → 进回落态
      await tester.pump();
      // ★ 回落态下页面最醒目那句指令不能自相矛盾:此刻**没有东西可扫**,
      //   却是商家站在旁边等着的时刻。断言它说的是「核销」而不是「扫描」。
      expect(find.textContaining('扫描'), findsNothing);
      expect(find.text('请把此码交给商家核销'), findsOneWidget);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_pass_fallback.png'),
      );
    });

    testWidgets('正常态:二维码图已加载 + 倒计时 + 刷新', (WidgetTester tester) async {
      try {
        debugNetworkImageHttpClientProvider = () => _FakeHttpClient(_qrPng);
        setGoldenViewport(tester, const Size(390, 780));
        await tester.pumpWidget(
          _app(
            <dynamic>[
              activityApiProvider.overrideWithValue(
                _FakeActivityApi(
                  dynCode: _FixedDynCode(
                    code: 'CY.9001.activity.aB3xQ7',
                    expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
                    qrcodeUrl: 'https://oss.example/qrcode/20260818/x.png',
                  ),
                ),
              ),
            ],
            const PassPage(registrationId: 9001),
          ),
        );
        await tester.pump(); // 出码完成 → Image.network 开始加载
        // 解码走 dart:ui 真异步,必须放 runAsync 里等它完成。
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(); // 码图就位
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/fulfil_pass_normal.png'),
        );
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    });

    testWidgets('已过期:码卡 25% 透明 + 「已过期,请刷新」', (WidgetTester tester) async {
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            activityApiProvider.overrideWithValue(
              _FakeActivityApi(
                dynCode: _FixedDynCode(
                  code: 'CY.9001.activity.expired',
                  expiresAt: DateTime.now().millisecondsSinceEpoch - 60000,
                  qrcodeUrl: null,
                  fixedRemaining: Duration.zero,
                ),
              ),
            ),
          ],
          const PassPage(registrationId: 9001),
        ),
      );
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_pass_expired.png'),
      );
    });
  });

  group('商家扫码(相机在测试里渲染不出,聚焦结果浮层)', () {
    /// mobile_scanner 的相机平台端在测试里不存在 → 控制器落确定性错误态
    /// (黑底),但 _setupListeners 订阅的 barcodes 事件通道仍活着。往
    /// dev.steenbakker.mobile_scanner/scanner/event 推一条 barcode 事件即可
    /// 走真实 _onDetect 链路。
    ///
    /// 方法通道必须一并 mock:未 mock 时 invokeMethod 走真实事件循环、只在
    /// 测试 teardown 才解析,导致 controller.start() 被推迟到截图之后。mock
    /// 后全部立即返回 null → 'state'=0(undetermined)→'request'=null(false)
    /// → 确定性 permissionDenied 错误态。等 50ms fake 时间让订阅先就位再发码。
    void setUpScannerEventMock(String code) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
        (MethodCall call) async => null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        const EventChannel(
            'dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink? events) {},
          onCancel: (Object? arguments) {},
        ),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        const EventChannel('dev.steenbakker.mobile_scanner/scanner/event'),
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink? events) {
            Future<void>.delayed(const Duration(milliseconds: 50), () {
              events?.success(<Object?, Object?>{
                'name': 'barcode',
                'data': <Object?>[
                  <Object?, Object?>{'rawValue': code},
                ],
              });
            });
          },
          onCancel: (Object? arguments) {},
        ),
      );
    }

    Future<void> driveToOverlay(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100)); // 发码定时器
      await tester.pump(); // _onDetect 微任务(含假 API 返回)
      await tester.pump(const Duration(milliseconds: 300)); // 浮层动画收尾
      await tester.pump(); // 最终帧
    }

    testWidgets('成功态:绿勾 + 「核销成功(章节 3)」', (WidgetTester tester) async {
      // ⚠️ 必须用**真实格式** `v1.{regId}.{type}.{expMs}.{nonce}.{sig}`
      //   (后端 VerifyDynCodeUtil 的注释)。原来这里是 'CY.9001.activity.…',
      //   压根不是动态码的样子 —— 页面此前无条件把任何字符串丢给
      //   scanDynamicCode,所以看不出来;接了码型路由之后它会被正确地
      //   判成「二维码格式错误」。
      setUpScannerEventMock('v1.9001.activity.1786000000000.n7.sig');
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            activityApiProvider.overrideWithValue(
              _FakeActivityApi(
                dynCode: _FixedDynCode(code: 'CY.TEST', expiresAt: 0),
                scanError: null,
              ),
            ),
          ],
          const MerchantScanPage(),
          light: true,
        ),
      );
      await tester.pump(); // 相机控制器落定(错误态,黑底)+ 订阅建立
      await tester.pump();
      await driveToOverlay(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_merchant_scan_ok.png'),
      );
    });

    testWidgets('失败态:红错图标 + 后端原因原样展示', (WidgetTester tester) async {
      setUpScannerEventMock('v1.9001.activity.1786000000000.n8.sig');
      setGoldenViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          <dynamic>[
            activityApiProvider.overrideWithValue(
              _FakeActivityApi(
                dynCode: _FixedDynCode(code: 'CY.TEST', expiresAt: 0),
                scanError: '该核销码已过期,请让玩家刷新后重试',
              ),
            ),
          ],
          const MerchantScanPage(),
          light: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await driveToOverlay(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fulfil_merchant_scan_fail.png'),
      );
    });
  });
}
