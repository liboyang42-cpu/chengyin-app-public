// 商家核销页的码型路由 + 选章/选站第二步。
//
// ★★★ 两个此前实实在在的缺口:
//   ① 页面**无条件调 scanDynamicCode** —— 商家扫优惠券码 / 团码 / 旧版票码
//      都会被打到错的端点,拿回一句莫名其妙的失败。
//   ② needsChoice 被当成失败抛掉 —— scan_result.dart 的注释早就写死了这个后果:
//      「候选列表连同 data 一起被丢掉,商家看到一句红字『请选择要核销的章节』
//       却没有可选的东西,核销变成死胡同」。
//      而且 scanQrCode 抛的那句话是「请到商家核销页扫码」——
//      **这里就是商家核销页**,自相矛盾。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/scan_result.dart';
import 'package:chengyin_app/feature/merchant/scan_choice.dart';

class _FakeCoupon implements CouponApi {
  String? seen;
  @override
  Future<String> verify(String scanned) async {
    seen = scanned;
    return '核销成功';
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGroup implements GroupCodeApi {
  String? seen;
  @override
  Future<String> redeem(String code) async {
    seen = code;
    return '已记录接待该团';
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeReg implements RegistrationApi {
  _FakeReg(this.first);
  final ScanResult first;
  int? chapterSeen;
  int? stationSeen;
  int chapterCalls = 0;

  @override
  Future<ScanResult> scanQrCodeDetailed({
    required String type,
    required String code,
  }) async =>
      first;

  @override
  Future<ScanResult> scanChapter({
    required String code,
    required int chapterId,
  }) async {
    chapterCalls += 1;
    chapterSeen = chapterId;
    return const ScanResult(outcome: ScanOutcome.redeemed, message: '核销成功');
  }

  @override
  Future<ScanResult> scanStation({
    required String code,
    required int registrationMerchantId,
  }) async {
    stationSeen = registrationMerchantId;
    return const ScanResult(outcome: ScanOutcome.redeemed, message: '核销成功');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('★★★ needsChoice 的解析:失败码 + 载荷里的候选', () {
    // 后端在交集 ≥2 时返回的是 error(...) —— code 是失败码,
    // 但 data 里带着 needChapterChoice + 候选。判据必须看 data。
    final ScanResult r = ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的章节',
      'data': <String, dynamic>{
        'needChapterChoice': true,
        'chapters': <dynamic>[
          <String, dynamic>{'id': 11, 'name': '第一站·手冲'},
          <String, dynamic>{'id': 12, 'name': '第二站·拉花'},
        ],
      },
    });
    expect(r.needsChoice, isTrue,
        reason: '只判 code 会把它当失败 —— 那样同一张票能反复核销');
    expect(r.choiceKind, 'chapter');
    expect(r.choices.map((ScanChoice c) => c.id), <int>[11, 12]);
    expect(r.choices.first.label, '第一站·手冲');
  });

  test('★★ 站点选择用的是中标记录 ID,不是站点 id', () {
    final ScanResult r = ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的站点',
      'data': <String, dynamic>{
        'needStationChoice': true,
        'stations': <dynamic>[
          <String, dynamic>{'registrationMerchantId': 77, 'name': '静安咖啡'},
        ],
      },
    });
    expect(r.choiceKind, 'station');
    expect(r.choices.single.id, 77);
  });

  test('★ 候选没名字时显示 #id,不留空条目', () {
    final ScanResult r = ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的章节',
      'data': <String, dynamic>{
        'needChapterChoice': true,
        'chapterIds': <dynamic>[9],
      },
    });
    expect(r.choices.single.label, '#9');
  });

  testWidgets('★★★ 选章面板:选一个 → 提交第二步', (WidgetTester t) async {
    final reg = _FakeReg(ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的章节',
      'data': <String, dynamic>{
        'needChapterChoice': true,
        'chapters': <dynamic>[
          <String, dynamic>{'id': 11, 'name': '第一站·手冲'},
          <String, dynamic>{'id': 12, 'name': '第二站·拉花'},
        ],
      },
    }));
    await _pumpScan(t, reg: reg);

    // 面板上必须真的有可选项 —— 缺了它就是那条注释说的"死胡同"。
    expect(find.text('第一站·手冲'), findsOneWidget);
    expect(find.text('第二站·拉花'), findsOneWidget);

    await t.tap(find.byKey(const Key('scan-choice-12')));
    await t.pumpAndSettle();
    expect(reg.chapterSeen, 12);
    expect(_outcome, '核销成功');
  });

  testWidgets('★★ 关掉面板 = 没核销,如实说', (WidgetTester t) async {
    final reg = _FakeReg(ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的章节',
      'data': <String, dynamic>{
        'needChapterChoice': true,
        'chapters': <dynamic>[
          <String, dynamic>{'id': 11, 'name': '第一站'},
        ],
      },
    }));
    await _pumpScan(t, reg: reg);
    // 点遮罩关掉
    await t.tapAt(const Offset(200, 60));
    await t.pumpAndSettle();
    expect(reg.chapterSeen, isNull);
    expect(_outcome, contains('还没核销'),
        reason: '不能伪装成"失败",也不能什么都不说');
  });

  testWidgets('★★ 后端说要选却没给候选:说实话,不摆空面板',
      (WidgetTester t) async {
    final reg = _FakeReg(ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的章节',
      'data': <String, dynamic>{'needChapterChoice': true},
    }));
    await _pumpScan(t, reg: reg);
    expect(_outcome, contains('没有拿到可选项'));
  });

  // ⚠️ 这条是负控逼出来的:把「站点走 scanStation」改成「一律走 scanChapter」
  //   之后测试**照样全绿** —— 因为站点那条路径当时只有解析测试,
  //   没有端到端的。选错端点在真机上就是核销打不通。
  testWidgets('★★★ 站点选择走 scanStation,不是 scanChapter',
      (WidgetTester t) async {
    final reg = _FakeReg(ScanResult.fromBody(<String, dynamic>{
      'code': 500,
      'msg': '请选择要核销的站点',
      'data': <String, dynamic>{
        'needStationChoice': true,
        'stations': <dynamic>[
          <String, dynamic>{'registrationMerchantId': 77, 'name': '静安咖啡'},
        ],
      },
    }));
    await _pumpScan(t, reg: reg);
    await t.tap(find.byKey(const Key('scan-choice-77')));
    await t.pumpAndSettle();

    expect(reg.stationSeen, 77, reason: '站点这一步传的是中标记录 ID');
    expect(reg.chapterSeen, isNull, reason: '走错端点,核销在真机上打不通');
    expect(_outcome, '核销成功');
  });

  testWidgets('iOS 原生 Sheet 保持 message、候选顺序与精确 ScanChoice', (
    WidgetTester t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    final Completer<bool> showCompleter = Completer<bool>();
    MethodCall? nativeCall;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      nativeCall = call;
      return showCompleter.future;
    });
    addTearDown(() {
      if (!showCompleter.isCompleted) showCompleter.complete(false);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final reg = _FakeReg(
      ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapters': <dynamic>[
            <String, dynamic>{'id': 11, 'name': '第一站·手冲'},
            <String, dynamic>{'id': 12, 'name': '第二站·拉花'},
          ],
        },
      }),
    );
    await _pumpScan(t, reg: reg, settleAfterTap: false);
    await t.pump();

    expect(nativeCall?.method, 'showTemplateSheet');
    final Map<Object?, Object?> arguments =
        nativeCall!.arguments! as Map<Object?, Object?>;
    final Map<Object?, Object?> content =
        arguments['content']! as Map<Object?, Object?>;
    expect(arguments['backgroundZoomScale'], 1.0);
    expect(content['title'], '请选择要核销的章节');
    final List<Object?> sections = content['sections']! as List<Object?>;
    final List<Object?> rows =
        (sections.single! as Map<Object?, Object?>)['rows']! as List<Object?>;
    expect(
      rows.map((Object? row) => (row! as Map<Object?, Object?>)['title']),
      <String>['第一站·手冲', '第二站·拉花'],
    );
    final Map<Object?, Object?> second = rows[1]! as Map<Object?, Object?>;
    expect(second['buttonDismissesSheet'], isTrue);
    expect(second['buttonSemanticLabel'], '第二站·拉花');
    final Map<Object?, Object?> buttonStyle =
        second['buttonStyle']! as Map<Object?, Object?>;
    expect(buttonStyle['buttonHeight'], 48.0);
    expect(buttonStyle['pressedScale'], 1.0);
    expect(buttonStyle['pressedOpacity'], 0.86);
    expect(buttonStyle['pressAnimationDuration'], 0.0);

    await _sendPlatformMethodCall(channel, 'buttonPressed', <String, Object?>{
      'actionId': second['buttonActionId'],
    });
    showCompleter.complete(true);
    await t.pumpAndSettle();

    expect(reg.chapterSeen, 12);
    expect(_outcome, '核销成功');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('原生 Sheet 交互关闭未选择时返回 null，不提交核销', (WidgetTester t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => true,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final reg = _FakeReg(
      ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapters': <dynamic>[
            <String, dynamic>{'id': 11, 'name': '第一站'},
          ],
        },
      }),
    );
    await _pumpScan(t, reg: reg);

    expect(reg.chapterCalls, 0);
    expect(_outcome, contains('还没核销'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('原生 Sheet shown=false 时回退原 Flutter Sheet', (
    WidgetTester t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => false,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final reg = _FakeReg(
      ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapters': <dynamic>[
            <String, dynamic>{'id': 11, 'name': '第一站'},
          ],
        },
      }),
    );
    await _pumpScan(t, reg: reg);
    expect(find.byKey(const Key('scan-choice-11')), findsOneWidget);
    await t.tap(find.byKey(const Key('scan-choice-11')));
    await t.pumpAndSettle();

    expect(reg.chapterSeen, 11);
    expect(_outcome, '核销成功');
    debugDefaultTargetPlatformOverride = null;
  });

  for (final MapEntry<String, Object> failure in <String, Object>{
    'MissingPlugin': MissingPluginException('sheet unavailable'),
    'PlatformException': PlatformException(
      code: 'presentation_failed',
      message: 'sheet unavailable',
    ),
  }.entries) {
    testWidgets('原生 Sheet ${failure.key} 时回退原 Flutter Sheet', (
      WidgetTester t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        throw failure.value;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final reg = _FakeReg(
        ScanResult.fromBody(<String, dynamic>{
          'code': 500,
          'msg': '请选择要核销的章节',
          'data': <String, dynamic>{
            'needChapterChoice': true,
            'chapters': <dynamic>[
              <String, dynamic>{'id': 11, 'name': '第一站'},
            ],
          },
        }),
      );
      await _pumpScan(t, reg: reg);
      expect(find.byKey(const Key('scan-choice-11')), findsOneWidget);
      await t.tap(find.byKey(const Key('scan-choice-11')));
      await t.pumpAndSettle();

      expect(reg.chapterSeen, 11);
      expect(_outcome, '核销成功');
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('原生 Sheet 展示中的第二次调用复用进行中结果，不伪装取消', (WidgetTester t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    final Completer<bool> showCompleter = Completer<bool>();
    String? actionId;
    int nativeShowCalls = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      if (call.method != 'showTemplateSheet') return null;
      nativeShowCalls += 1;
      final Map<Object?, Object?> arguments =
          call.arguments! as Map<Object?, Object?>;
      final Map<Object?, Object?> content =
          arguments['content']! as Map<Object?, Object?>;
      final List<Object?> sections = content['sections']! as List<Object?>;
      final List<Object?> rows =
          (sections.single! as Map<Object?, Object?>)['rows']! as List<Object?>;
      actionId =
          (rows.single! as Map<Object?, Object?>)['buttonActionId'] as String?;
      return showCompleter.future;
    });
    addTearDown(() {
      if (!showCompleter.isCompleted) showCompleter.complete(false);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final reg = _FakeReg(
      ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapters': <dynamic>[
            <String, dynamic>{'id': 11, 'name': '第一站'},
          ],
        },
      }),
    );
    late BuildContext sheetContext;
    late WidgetRef providerRef;
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          registrationApiProvider.overrideWithValue(reg),
        ].cast(),
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              providerRef = ref;
              return Builder(
                builder: (BuildContext inner) {
                  sheetContext = inner;
                  return const Scaffold();
                },
              );
            },
          ),
        ),
      ),
    );

    final Future<String> first = resolveScanChoice(
      context: sheetContext,
      ref: providerRef,
      result: reg.first,
      code: 'CODE',
    );
    await t.pump();
    final Future<String> second = resolveScanChoice(
      context: sheetContext,
      ref: providerRef,
      result: reg.first,
      code: 'CODE',
    );
    await t.pump();
    expect(nativeShowCalls, 1);

    await _sendPlatformMethodCall(channel, 'buttonPressed', <String, Object?>{
      'actionId': actionId,
    });
    showCompleter.complete(true);
    expect(await Future.wait(<Future<String>>[first, second]), <String>[
      '核销成功',
      '核销成功',
    ]);
    expect(reg.chapterCalls, 1, reason: '并发点击不能把同一张票核销两次');
    debugDefaultTargetPlatformOverride = null;
  });
}

/// ⚠️ 扫码页本体要相机,widget 测试里起不来,所以直接驱动**同一份**
///   第二步逻辑(resolveScanChoice)—— 它已经从页面里抽成顶层函数,
///   页面调的就是这个。
///   第一版这里放了个空的 _Harness、什么都没调,三条断言全是空跑的。
String? _outcome;

Future<void> _pumpScan(
  WidgetTester t, {
  required _FakeReg reg,
  bool settleAfterTap = true,
}) async {
  _outcome = null;
  await t.binding.setSurfaceSize(const Size(390, 800));
  await t.pumpWidget(ProviderScope(
      overrides: <dynamic>[
        registrationApiProvider.overrideWithValue(reg),
        couponApiProvider.overrideWithValue(_FakeCoupon()),
        groupCodeApiProvider.overrideWithValue(_FakeGroup()),
      ].cast(),
      child: MaterialApp(
        home: Consumer(
          builder: (BuildContext c, WidgetRef ref, _) => Scaffold(
            body: Center(
              child: Builder(
                builder: (BuildContext inner) =>
                    Text(_outcome ?? '(等待)', key: const Key('outcome')),
              ),
            ),
            floatingActionButton: Builder(
              builder: (BuildContext inner) => FloatingActionButton(
                onPressed: () async {
                  try {
                    _outcome = await resolveScanChoice(
                      context: inner,
                      ref: ref,
                      result: reg.first,
                      code: 'CODE',
                    );
                  } catch (e) {
                    _outcome = e.toString().replaceFirst('Exception: ', '');
                  }
                  (inner as Element).markNeedsBuild();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byType(FloatingActionButton));
  if (settleAfterTap) await t.pumpAndSettle();
}

Future<void> _sendPlatformMethodCall(
  MethodChannel channel,
  String method,
  Object? arguments,
) async {
  final ByteData message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, message, (_) {});
}
