import 'package:chengyin_app/core/widgets/cy_native_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel(
  'native_liquid_glass/native_flutter_sheet',
);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final NotifierProvider<_Counter, int> _counter =
    NotifierProvider<_Counter, int>(_Counter.new);

class _Host extends ConsumerStatefulWidget {
  const _Host({required this.detents});

  final CyNativeSheetDetents detents;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  String result = '未返回';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('宿主计数 ${ref.watch(_counter)}'),
            Text(result),
            CupertinoButton(
              onPressed: () async {
                final String? value = await showCyNativeSheet<String>(
                  context,
                  detents: widget.detents,
                  builder: (BuildContext context) => const _SheetBody(),
                );
                if (mounted) setState(() => result = value ?? 'null');
              },
              child: const Text('打开'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('sheet 计数 ${ref.watch(_counter)}'),
        Text(isCyNativeSheet(context) ? '原生承载' : '回退承载'),
        CupertinoButton(
          onPressed: () => ref.read(_counter.notifier).increment(),
          child: const Text('加一'),
        ),
        CupertinoButton(
          onPressed: () => Navigator.of(context).pop('完成值'),
          child: const Text('完成'),
        ),
        CupertinoButton(
          onPressed: () => showCyNativeSheet<void>(
            context,
            builder: (BuildContext context) =>
                Text(isCyNativeSheet(context) ? '原生(嵌套)' : '回退(嵌套)'),
          ),
          child: const Text('再开一个'),
        ),
      ],
    );
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  CyNativeSheetDetents detents = CyNativeSheetDetents.both,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: CupertinoApp(home: _Host(detents: detents)),
    ),
  );
}

Future<void> _nativeSays(WidgetTester tester, String method) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method)),
    (ByteData? _) {},
  );
}

bool _hostedByCupertinoSheetRoute(WidgetTester tester) {
  final BuildContext sheet = tester.element(find.byType(_SheetBody));
  return ModalRoute.of(sheet) is CupertinoSheetRoute;
}

void main() {
  final List<MethodCall> calls = <MethodCall>[];

  setUp(calls.clear);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockNative(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          calls.add(call);
          return reply(call);
        });
  }

  group('回退分支', () {
    testWidgets('Android 不碰原生通道，直接 showCupertinoSheet', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockNative((_) => null);
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(_hostedByCupertinoSheetRoute(tester), isTrue);
      expect(find.text('回退承载'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('完成值'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS 13–14:原生回 unsupported → showCupertinoSheet', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative((_) => throw PlatformException(code: 'unsupported'));
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(calls.map((MethodCall c) => c.method), <String>['present']);
      expect(_hostedByCupertinoSheetRoute(tester), isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('测试环境无原生插件(MissingPlugin)→ showCupertinoSheet', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative((_) => throw MissingPluginException());
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(_hostedByCupertinoSheetRoute(tester), isTrue);
      expect(find.text('回退承载'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('原生承载', () {
    testWidgets('参数下发、内容进 root overlay、Riverpod 共享、pop 值回传', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative((_) => null);
      await _pumpHost(tester, detents: CyNativeSheetDetents.medium);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(calls.first.method, 'present');
      expect(calls.first.arguments, <String, Object>{
        'detents': 'medium',
        'grabber': true,
        'dismissible': true,
      });
      expect(calls.map((MethodCall c) => c.method), contains('reveal'));
      expect(_hostedByCupertinoSheetRoute(tester), isFalse);
      expect(find.text('原生承载'), findsOneWidget);
      // opaque overlay entry 盖住下层页面(不绘制但保活)。
      expect(find.text('宿主计数 0'), findsNothing);

      await tester.tap(find.text('加一'));
      await tester.pump();
      expect(find.text('sheet 计数 1'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pump();
      expect(calls.last.method, 'dismiss');
      // 原生动画结束、主控制器接回之前，内容必须还在。
      expect(find.text('原生承载'), findsOneWidget);

      await _nativeSays(tester, 'dismissed');
      await tester.pumpAndSettle();

      expect(find.text('原生承载'), findsNothing);
      expect(find.text('完成值'), findsOneWidget);
      expect(find.text('宿主计数 1'), findsOneWidget);
      expect(calls.last.method, 'restored');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('系统下滑关闭 → 返回 null', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative((_) => null);
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await _nativeSays(tester, 'dismissed');
      await tester.pumpAndSettle();

      expect(find.text('原生承载'), findsNothing);
      expect(find.text('null'), findsOneWidget);
      expect(calls.map((MethodCall c) => c.method), isNot(contains('dismiss')));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('原生已有 sheet(already_presented)→ 回退 Flutter 承载再叠', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative((_) => throw PlatformException(code: 'already_presented'));
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      // 嵌套请求(登录 sheet 里的「手机号登录」)不能静默吞掉:
      // 回退 showCupertinoSheet 叠在当前内容里,入口点了必须有反应。
      expect(_hostedByCupertinoSheetRoute(tester), isTrue);
      expect(find.text('回退承载'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('原生 sheet 内容里再请求 sheet → 叠进当前 sheet 自己的 Navigator', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int presents = 0;
      mockNative((MethodCall call) {
        if (call.method == 'present' && ++presents > 1) {
          throw PlatformException(code: 'already_presented');
        }
        return null;
      });
      await _pumpHost(tester);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('原生承载'), findsOneWidget);

      await tester.tap(find.text('再开一个'));
      await tester.pumpAndSettle();

      expect(presents, 2);
      // 叠在承载 sheet 的嵌套 Navigator 里(推根 Navigator 会被 opaque
      // overlay entry 挡住不可见),且按回退承载出实色背景。
      final BuildContext nested = tester.element(find.text('回退(嵌套)'));
      expect(ModalRoute.of(nested), isA<CupertinoSheetRoute<void>>());
      expect(isCyNativeSheet(nested), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
