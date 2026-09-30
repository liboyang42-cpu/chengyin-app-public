@Tags(<String>['needs-macos-fonts'])
// 布局贴着视口边缘;没有 macOS 中文字体时文字变高,RenderFlex 溢出 19px。
// CI 跑在自托管 Mac 上,这条用例在 CI 上会跑;tag 是给非 macOS 机器本地排除用的。
library;

import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/merchant_scan_page.dart';
import 'package:chengyin_app/feature/roam/stamp_camera_page.dart';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const MethodChannel _scannerMethod = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/method',
);
const EventChannel _scannerOrientation = EventChannel(
  'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
);
const EventChannel _scannerEvents = EventChannel(
  'dev.steenbakker.mobile_scanner/scanner/event',
);

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 集邮相机对游客是登录门,这一组测的是页内导航与几何,所以给已登录态。
final List<dynamic> _loggedIn = <dynamic>[
  authControllerProvider.overrideWith(
    () => _FixedAuth(
      AuthState(
        initialized: true,
        user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
      ),
    ),
  ),
];

Widget _host(
  Widget page,
  String label, {
  List<dynamic> overrides = const <dynamic>[],
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Builder(
        builder: (BuildContext context) => Center(
          child: CupertinoButton(
            onPressed: () => Navigator.of(
              context,
            ).push<void>(CupertinoPageRoute<void>(builder: (_) => page)),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('商家扫码使用原生全屏导航且返回时释放页面', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _scannerMethod,
      (MethodCall call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _scannerOrientation,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink? events) {},
        onCancel: (Object? arguments) {},
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _scannerEvents,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink? events) {},
        onCancel: (Object? arguments) {},
      ),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _scannerMethod,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _scannerOrientation,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _scannerEvents,
        null,
      );
    });

    await tester.pumpWidget(_host(const MerchantScanPage(), '打开商家扫码'));
    await tester.tap(find.text('打开商家扫码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(MobileScanner), findsOneWidget);
    final Finder title = find.widgetWithText(CyPageTitle, '核销玩家票');
    expect(title, findsOneWidget);
    expect(
      tester.getTopLeft(title).dy,
      closeTo(kToolbarHeight, 0.1),
      reason: '换成 44pt 原生导航后，相机取景区的原 56pt 起点不能上移',
    );
    expect(find.bySemanticsLabel('手动输入'), findsOneWidget);

    final Finder back = find.byType(CupertinoNavigationBarBackButton);
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('打开商家扫码'), findsOneWidget);
    expect(find.byType(MobileScanner), findsNothing);
  });

  testWidgets('集邮相机原生透明导航不越过用途说明请求权限', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(const StampCameraPage(), '打开集邮相机', overrides: _loggedIn),
    );
    await tester.tap(find.text('打开集邮相机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final CupertinoNavigationBar navigationBar = tester.widget(
      find.byType(CupertinoNavigationBar),
    );
    expect(navigationBar.backgroundColor, Colors.transparent);
    expect(navigationBar.border, isNull);
    expect(
      tester.getSize(find.byKey(const Key('stamp-camera-viewport'))),
      const Size(390, 844),
      reason: '原生透明导航不能改变 Canon 机身与裁切框的全屏 viewport',
    );
    expect(find.byKey(const Key('stamp-camera-purpose')), findsOneWidget);
    expect(find.byType(CameraPreview), findsNothing);
    final Semantics crop = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((Semantics item) => item.properties.label == '裁切框大小');
    final Semantics shutter = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((Semantics item) => item.properties.label == '拍摄城市邮票');
    expect(crop.properties.value, '74%');
    expect(crop.properties.increasedValue, '79%');
    expect(crop.properties.decreasedValue, '69%');
    expect(crop.properties.onIncrease, isNotNull);
    expect(crop.properties.onDecrease, isNotNull);
    expect(shutter.properties.button, isTrue);

    await tester.tap(find.text('暂不'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('需要使用相机拍摄城市邮票'), findsOneWidget);
    expect(find.byKey(const Key('stamp-purpose-retry')), findsOneWidget);
    expect(find.byType(CameraPreview), findsNothing);

    final Finder back = find.byType(CupertinoNavigationBarBackButton);
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('打开集邮相机'), findsOneWidget);
  });
}
