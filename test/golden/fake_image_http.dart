// 快照用的假图片 HTTP:测试环境真 HttpClient 恒 400,页面上任何 Image.network
// 都只能停在加载中 —— 那会把「图已就位」和「图挂了」拍成同一张,而二维码/封面
// 恰恰是这些页的主体。Flutter 官方测试钩子 debugNetworkImageHttpClientProvider
// 允许换成假客户端,这里喂一张**程序生成的确定性样张**。
//
// 用法(顺序有讲究):
//   await installFakeNetworkImages(tester);
//   ...pumpWidget...
//   await tester.runAsync(() => Future<void>.delayed(...)); // 解码走 dart:ui 真异步
//   await tester.pump();                                    // 图就位
//   拍照后 restoreFakeNetworkImages()(或 addTearDown)
//
// 与 pages_fulfil_golden_test.dart 里那份同源;那页在本轮不在手上,不合并。

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List? _png;

/// 程序生成的样张:白底 + 确定性点阵 + 三处定位角(形状像二维码)。
Future<Uint8List> _samplePng() async {
  final Uint8List? cached = _png;
  if (cached != null) return cached;
  const int grid = 21;
  const double size = 120;
  final double cell = size / grid;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, size, size),
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );
  final ui.Paint ink = ui.Paint()..color = const Color(0xFF0F172B);
  final Random rng = Random(7);
  for (int y = 0; y < grid; y++) {
    for (int x = 0; x < grid; x++) {
      final bool inFinder =
          (x < 7 && y < 7) || (x >= grid - 7 && y < 7) || (x < 7 && y >= grid - 7);
      if (!inFinder && rng.nextDouble() < 0.45) {
        canvas.drawRect(ui.Rect.fromLTWH(x * cell, y * cell, cell, cell), ink);
      }
    }
  }
  for (final (int fx, int fy) in <(int, int)>[(0, 0), (grid - 7, 0), (0, grid - 7)]) {
    canvas.drawRect(ui.Rect.fromLTWH(fx * cell, fy * cell, 7 * cell, 7 * cell), ink);
    canvas.drawRect(
      ui.Rect.fromLTWH((fx + 2) * cell, (fy + 2) * cell, 3 * cell, 3 * cell),
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
  }
  final ui.Image image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  return _png = data!.buffer.asUint8List();
}

/// 装上假 HttpClient(所有 http(s) 图片都返回同一张样张)。
///
/// ★ 样张要在 `runAsync` 里生成:`Picture.toImage` / `toByteData` 走的是引擎
///   真异步,在 testWidgets 的假时钟 zone 里 await 它 = **永远不返回**
///   (实测挂满 10 分钟直到超时)。`setUpAll` 生成也行,但那要求每个用例文件
///   自己记得,不如这里收口。
Future<void> installFakeNetworkImages(WidgetTester tester) async {
  final Uint8List? bytes = await tester.runAsync(_samplePng);
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(bytes!);
}

void restoreFakeNetworkImages() =>
    debugNetworkImageHttpClientProvider = null;

/// 等图片解码(必须在 runAsync 里,否则真实异步任务不推进)。
Future<void> settleNetworkImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.bytes);
  final Uint8List bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest(bytes);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpClient 不支持: $invocation');
}

class _FakeHttpRequest extends Stream<List<int>> implements HttpClientRequest {
  _FakeHttpRequest(this.bytes);
  final Uint8List bytes;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse(bytes);

  @override
  Future<HttpClientResponse> get done async => _FakeHttpResponse(bytes);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[bytes]).listen(
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

class _FakeHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeHttpResponse(this.bytes);
  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[bytes]).listen(
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
