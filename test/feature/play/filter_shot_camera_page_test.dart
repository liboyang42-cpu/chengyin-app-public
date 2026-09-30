import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';

import 'package:chengyin_app/feature/play/filter_shot_camera.dart';
import 'package:chengyin_app/feature/play/filter_shot_camera_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('滤镜相机用原生全屏导航,不再是 Material Scaffold/AppBar', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(_app(camera: _FakeCameraGateway()));

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(CupertinoNavigationBar, '暗夜搜证'), findsOneWidget);
  });

  testWidgets('用途同意前零初始化，权限拒绝后 fail-closed', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final _FakeCameraGateway camera = _FakeCameraGateway(
      initializeError: const FilterShotCameraException(
        FilterShotCameraFailure.permissionDenied,
      ),
    );
    int openSettingsCount = 0;

    await tester.pumpWidget(
      _app(
        camera: camera,
        openSettings: () async {
          openSettingsCount += 1;
          return true;
        },
      ),
    );
    expect(camera.initializeCount, 0);
    expect(find.textContaining('仅在本次滤镜拍摄中使用'), findsOneWidget);
    expect(find.textContaining('点提交后才上传滤镜成片'), findsOneWidget);
    expect(find.textContaining('原图不上传并清理'), findsOneWidget);
    expect(find.byKey(const Key('filter-shot-capture')), findsNothing);

    await tester.tap(find.text('同意并打开相机'));
    await tester.pumpAndSettle();

    expect(camera.initializeCount, 1);
    expect(find.text('未获得相机权限'), findsOneWidget);
    expect(
      find.byKey(const Key('filter-shot-capture')),
      findsNothing,
      reason: '权限被拒后不能降级成未经滤镜的普通图片提交',
    );
    await tester.tap(find.text('打开系统设置'));
    await tester.pump();
    expect(openSettingsCount, 1);
  });

  testWidgets('点暂不使用不会触发相机权限', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final _FakeCameraGateway camera = _FakeCameraGateway();
    await tester.pumpWidget(_app(camera: camera));

    expect(find.text('未成年人请在监护人陪同下使用。'), findsOneWidget);
    await tester.tap(find.text('暂不使用'));
    await tester.pump();

    expect(camera.initializeCount, 0);
  });

  testWidgets('只在已同意时随前后台释放和重建相机', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final _FakeCameraGateway camera = _FakeCameraGateway();
    await tester.pumpWidget(_app(camera: camera));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.initializeCount, 0, reason: '未同意时 resumed 也不得初始化相机');

    await tester.tap(find.text('同意并打开相机'));
    await tester.pumpAndSettle();
    expect(camera.initializeCount, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(find.text('异常热源扫描中'), findsOneWidget);
    expect(
      find.byKey(const Key('filter-shot-night-signature')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(camera.disposeCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.initializeCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
  });

  testWidgets('快速切回前台会在延迟释放完成后重建相机', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final Completer<void> release = Completer<void>();
    final _FakeCameraGateway camera = _FakeCameraGateway(
      disposeBarrier: release.future,
    );
    await tester.pumpWidget(_app(camera: camera));
    await tester.tap(find.text('同意并打开相机'));
    await tester.pump();
    expect(camera.initializeCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    release.complete();
    await tester.pump();

    expect(camera.initializeCount, 2, reason: '快速 resumed 不能卡在无相机预览状态');
  });

  testWidgets('拍摄后只提交合成 PNG 一次并清理原图和临时图', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final Directory temp = Directory.systemTemp.createTempSync(
      'filter-page-test-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final File source = File('${temp.path}/camera-original.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final File composite = File('${temp.path}/filtered.png');
    final _FakeCameraGateway camera = _FakeCameraGateway(source: source);
    int rendererCount = 0;
    int submitCount = 0;
    File? submitted;

    await tester.pumpWidget(
      _app(
        camera: camera,
        renderer: (File input, FilterShotConfig config) async {
          rendererCount += 1;
          expect(input.path, source.path);
          expect(config.style, FilterShotStyle.nightVision);
          composite.writeAsBytesSync(<int>[137, 80, 78, 71]);
          return composite;
        },
        onSubmit: (File file) async {
          submitCount += 1;
          submitted = file;
        },
        fileCleaner: _deleteSync,
      ),
    );
    await tester.tap(find.text('同意并打开相机'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('filter-shot-capture')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(rendererCount, 1);
    expect(source.existsSync(), isFalse, reason: '相机原图应在合成后立即删除');
    expect(composite.existsSync(), isTrue);
    expect(find.text('提交照片'), findsOneWidget);

    // 主干把动作按钮换成了原生 CyNativeButton(label 传文案,不是 child)。
    final CyNativeButton submitButton = tester.widget<CyNativeButton>(
      find.byWidgetPredicate(
        (Widget widget) => widget is CyNativeButton && widget.label == '提交照片',
      ),
    );
    submitButton.onPressed!();
    submitButton.onPressed!();
    await tester.pump();
    expect(submitCount, 1);
    expect(submitted?.path, composite.path);

    await tester.pump(const Duration(milliseconds: 100));
    expect(submitCount, 1);
    expect(composite.existsSync(), isFalse, reason: '提交回调消费文件后不留临时合成图');
  });

  testWidgets('提交失败保留同一张合成图供用户重试', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final Directory temp = Directory.systemTemp.createTempSync(
      'filter-retry-test-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final File source = File('${temp.path}/source.jpg')
      ..writeAsBytesSync(<int>[1]);
    final File composite = File('${temp.path}/filtered.png');
    final _FakeCameraGateway camera = _FakeCameraGateway(source: source);
    int submitCount = 0;

    await tester.pumpWidget(
      _app(
        camera: camera,
        renderer: (_, _) async {
          composite.writeAsBytesSync(<int>[137, 80, 78, 71]);
          return composite;
        },
        onSubmit: (_) async {
          submitCount += 1;
          if (submitCount == 1) throw StateError('network');
        },
        fileCleaner: _deleteSync,
      ),
    );
    await tester.tap(find.text('同意并打开相机'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('filter-shot-capture')));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('提交照片'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(submitCount, 1);
    expect(find.text('提交失败，请重试'), findsOneWidget);
    expect(composite.existsSync(), isTrue);

    await tester.tap(find.text('提交照片'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(submitCount, 2);
    expect(composite.existsSync(), isFalse);
  });

  testWidgets('提交中系统返回键不得退出或删除待上传成片', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final Directory temp = Directory.systemTemp.createTempSync(
      'filter-pop-test-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final File source = File('${temp.path}/source.jpg')
      ..writeAsBytesSync(<int>[1]);
    final File composite = File('${temp.path}/filtered.png');
    final Completer<void> submission = Completer<void>();
    final _FakeCameraGateway camera = _FakeCameraGateway(source: source);

    await tester.pumpWidget(
      _pushedApp(
        FilterShotCameraPage(
          title: '暗夜搜证',
          config: const FilterShotConfig(FilterShotStyle.nightVision),
          cameraGateway: camera,
          renderer: (_, _) async {
            composite.writeAsBytesSync(<int>[137, 80, 78, 71]);
            return composite;
          },
          onSubmit: (_) => submission.future,
          openSettings: () async => true,
          fileCleaner: _deleteSync,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-filter-shot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并打开相机'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-shot-capture')));
    await tester.pump();
    await tester.tap(find.text('提交照片'));
    await tester.pump();
    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isFalse,
      reason: '合成/上传未完成前必须显式阻断 route pop',
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('提交中…'), findsOneWidget);
    expect(composite.existsSync(), isTrue, reason: '上传未消费完前不得删文件');

    submission.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-shot-launcher')), findsOneWidget);
    expect(composite.existsSync(), isFalse);
  });

  testWidgets('合成失败后可重建相机，不降级提交原图', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final Directory temp = Directory.systemTemp.createTempSync(
      'filter-render-fail-test-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final File source = File('${temp.path}/source.jpg')
      ..writeAsBytesSync(<int>[1]);
    final _FakeCameraGateway camera = _FakeCameraGateway(source: source);

    await tester.pumpWidget(
      _app(
        camera: camera,
        renderer: (_, _) async => throw StateError('render'),
        fileCleaner: _deleteSync,
      ),
    );
    await tester.tap(find.text('同意并打开相机'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('filter-shot-capture')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(source.existsSync(), isFalse);
    expect(find.text('没能生成滤镜照片，请重拍'), findsOneWidget);
    expect(find.text('提交照片'), findsNothing);
    await tester.tap(find.text('重新打开相机'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(camera.initializeCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
  });

  testWidgets('pet POV 预览使用低机位几何引导', (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final _FakeCameraGateway camera = _FakeCameraGateway();
    await tester.pumpWidget(
      _app(
        camera: camera,
        config: const FilterShotConfig(FilterShotStyle.petPov),
      ),
    );
    await tester.tap(find.text('同意并打开相机'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-shot-pet-signature')), findsOneWidget);
    expect(find.text('异常热源扫描中'), findsNothing);
  });
}

Widget _app({
  required _FakeCameraGateway camera,
  FilterShotRenderer? renderer,
  Future<void> Function(File file)? onSubmit,
  FilterShotSettingsOpener? openSettings,
  FilterShotFileCleaner? fileCleaner,
  FilterShotConfig config = const FilterShotConfig(FilterShotStyle.nightVision),
}) {
  return MaterialApp(
    home: FilterShotCameraPage(
      title: '暗夜搜证',
      config: config,
      cameraGateway: camera,
      renderer: renderer ?? renderFilterShot,
      onSubmit: onSubmit ?? (_) async {},
      openSettings: openSettings ?? (() async => true),
      fileCleaner: fileCleaner ?? _deleteSync,
    ),
  );
}

Widget _pushedApp(FilterShotCameraPage page) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open-filter-shot'),
            onPressed: () => Navigator.of(
              context,
            ).push<void>(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('打开滤镜相机', key: Key('filter-shot-launcher')),
          ),
        ),
      ),
    ),
  );
}

Future<void> _deleteSync(File? file) async {
  if (file?.existsSync() ?? false) file!.deleteSync();
}

class _FakeCameraGateway implements FilterShotCameraGateway {
  _FakeCameraGateway({this.initializeError, this.source, this.disposeBarrier});

  final Object? initializeError;
  final File? source;
  final Future<void>? disposeBarrier;
  bool _initialized = false;
  int initializeCount = 0;
  int disposeCount = 0;
  int takePictureCount = 0;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
    if (initializeError != null) throw initializeError!;
    _initialized = true;
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('fake-camera-preview'), color: Colors.black);

  @override
  Future<File> takePicture() async {
    takePictureCount += 1;
    return source!;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await disposeBarrier;
    _initialized = false;
  }
}
