// 点位码弹层(海报码 / 现场打卡码)。
//
// ★★ 两种码不是同一张码的两种画法,断言也必须分开:
//   · 海报码:长期有效 →「保存到相册」,没有倒计时、没有刷新;
//   · 现场打卡码:秒级过期 → 有倒计时,到点**自己**换新(让商家手动刷新
//     等于给玩家一张过期码),不许有"保存到相册"(保存下来的就是过期码)。
//
// ★ 真源:pages/merchant/game-node/index.js:556(live-checkin-code)、
//   pages/topic/merchantinfo/merchantinfo.js:2858(poster-code)。

import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/chapter_node_code_sheet.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({this.live, this.poster, this.fail = false});

  final Map<String, dynamic>? live;
  final Map<String, dynamic>? poster;
  final bool fail;
  int liveCalls = 0;

  @override
  Future<Map<String, dynamic>> chapterNodeLiveCheckinCode(int nodeId) async {
    liveCalls++;
    if (fail) throw MerchantApiException('打卡码暂时没能生成');
    return live ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> chapterNodePosterCode(int nodeId) async {
    if (fail) throw MerchantApiException('海报码暂时没能生成');
    return poster ?? <String, dynamic>{};
  }

  @override
  Future<Uint8List> fetchImageBytes(String url) async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  _FakeMerchantApi api,
  ChapterNodeCodeKind kind,
) async {
  // 弹层比默认 800x600 的测试视口高:不放大就会有一半按钮在可视区外,
  // tap 落空 —— 而 tap 落空**不报错**,只留一行 warnIfMissed 提示,
  // 断言就会表现成"点了没反应"的假红。
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
      overrides: [merchantApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showChapterNodeCodeSheet(
              context,
              nodeId: 5,
              kind: kind,
            ),
            child: const Text('开码'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('开码'));
  // 弹层是滑上来的:只 pump 一帧的话按钮还在屏幕外,
  // tap 会落空 —— 且**不报错**,只留一行警告,断言表现成"点了没反应"。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final List<Uint8List?> saved = <Uint8List?>[];

  setUp(() {
    saved.clear();
    // 相册写入是系统调用,测试里换成记账 —— 不换的话它会静默失败,
    // 于是"保存成功"是假绿。
    saveQrImageToAlbum = (Uint8List bytes, String name) async => saved.add(bytes);
  });

  testWidgets('★★ 海报码:给「保存到相册」,不给倒计时/刷新', (WidgetTester tester) async {
    await _open(
      tester,
      _FakeMerchantApi(
        poster: <String, dynamic>{'qrcodeUrl': 'https://x/p.png', 'code': 'CY1'},
      ),
      ChapterNodeCodeKind.poster,
    );

    expect(find.byKey(const Key('chapter-node-code-save')), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-refresh')), findsNothing);
    expect(find.byKey(const Key('chapter-node-code-countdown')), findsNothing);
    expect(find.text('本站打卡码'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chapter-node-code-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved.single, <int>[1, 2, 3], reason: '相册要的是字节,不是 URL');
  });

  testWidgets('★★ 现场码:有倒计时与「立即换一张」,不给保存', (WidgetTester tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi(
      live: <String, dynamic>{
        'qrcodeUrl': 'https://x/live.png',
        'code': 'CY-LIVE',
        'ttlMs': 60000,
      },
    );
    await _open(tester, api, ChapterNodeCodeKind.liveCheckin);

    expect(find.text('现场打卡码'), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-countdown')), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('chapter-node-code-save')),
      findsNothing,
      reason: '现场码存下来就是一张过期码,存它没有意义',
    );

    // 「立即换一张」真的会再取一次。
    await tester.tap(find.byKey(const Key('chapter-node-code-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.liveCalls, 2);
  });

  testWidgets('★★ 现场码过期后自己换新,不用商家手动点', (WidgetTester tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi(
      live: <String, dynamic>{
        'qrcodeUrl': 'https://x/live.png',
        'code': 'CY-LIVE',
        // 2 秒就过期 —— 等它自动换。
        'ttlMs': 2000,
      },
    );
    await _open(tester, api, ChapterNodeCodeKind.liveCheckin);
    expect(api.liveCalls, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      api.liveCalls,
      greaterThan(1),
      reason: '一张过期的现场码等于把打卡敞开给任何截图的人',
    );
  });

  testWidgets('★ 只有文本码没有图时,把码本身显示出来(而不是空卡)', (WidgetTester tester) async {
    await _open(
      tester,
      _FakeMerchantApi(
        live: <String, dynamic>{'code': 'CY-123456', 'ttlMs': 0},
      ),
      ChapterNodeCodeKind.liveCheckin,
    );
    expect(find.byKey(const Key('chapter-node-code-text')), findsOneWidget);
    expect(find.text('CY-123456'), findsOneWidget);
  });

  testWidgets('★★ 取码失败:说清失败并给重试,不摆一张空白码卡', (WidgetTester tester) async {
    await _open(
      tester,
      _FakeMerchantApi(fail: true),
      ChapterNodeCodeKind.poster,
    );
    expect(find.byKey(const Key('chapter-node-code-error')), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-retry')), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-save')), findsOneWidget);
    // 失败时保存键必须禁用 —— 没有图可存。
    final Finder save = find.byKey(const Key('chapter-node-code-save'));
    expect(
      tester.widget<CyNativeButton>(save).onPressed,
      isNull,
      reason: '没有图可存时按钮必须禁用,而不是点了没反应',
    );
  });
}
