import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timewindow_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timer_logic.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// `cy-playkit-timewindow`(时段限定)的**行为**门禁(2026-09-19 · a4-playkit-dedupe-a)。
///
/// 真源:`pages/play/components/playkit-timewindow/index.js`。
/// 这里钉三件事:
/// 1. 读数怎么走(按注入的时钟对时,不是累减);
/// 2. **到点不自己开门** —— 只回服务端问一次(`onRefresh`),问几次都要数得出来;
/// 3. 负控:宿主忙 / 数据缺的时候不许发出任何请求,也不许崩。
void main() {
  Widget host(Widget child) => CupertinoApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 780)),
      child: child,
    ),
  );

  PlayKitCard card({
    String title = '还没到开放时间',
    String eyebrow = '时段限定',
    Map<String, Object?> kit = const <String, Object?>{
      'openFrom': '23:00',
      'openTo': '01:00',
    },
  }) => PlayKitCard(
    kind: PlayKitKind.timeWindow,
    title: title,
    detail: '23:00 – 01:00',
    eyebrow: eyebrow,
    kit: kit,
  );

  PlayKitFullscreenContext context(
    PlayKitCard value, {
    bool enabled = true,
    VoidCallback? onRefresh,
  }) => PlayKitFullscreenContext(
    card: value,
    enabled: enabled,
    onRefresh: onRefresh,
  );

  testWidgets('未到点:显示时段与倒计时,一条请求都不发', (WidgetTester tester) async {
    int refreshes = 0;
    final DateTime now = DateTime(2026, 9, 17, 22, 0);
    await tester.pumpWidget(
      host(
        PlayKitTimeWindowView(
          data: context(card(), onRefresh: () => refreshes += 1),
          now: () => now,
        ),
      ),
    );

    expect(find.text('时段限定'), findsOneWidget);
    expect(find.text('开放时段 23:00 – 01:00'), findsOneWidget);
    expect(
      find.text('01:00:00'),
      findsOneWidget,
      reason: '22:00 距 23:00 还有一小时',
    );
    expect(find.text('后开播'), findsOneWidget);
    expect(find.text('重新检查'), findsNothing, reason: '没到点就没有要复核的东西');
    expect(refreshes, 0);

    // 真源那颗「订阅开播提醒」调的是微信订阅消息,iOS 侧没有等价物 ——
    // 不移植,也就绝不许出现这颗按钮(按不动等于骗人)。
    expect(find.text('订阅开播提醒'), findsNothing);
    expect(find.textContaining('不提供开播提醒'), findsOneWidget);
  });

  testWidgets('到点:归零 → 回服务端问**一次**,显示已到点与重新检查', (WidgetTester tester) async {
    int refreshes = 0;
    DateTime now = DateTime(2026, 9, 17, 22, 59, 59);
    await tester.pumpWidget(
      host(
        PlayKitTimeWindowView(
          data: context(card(), onRefresh: () => refreshes += 1),
          now: () => now,
        ),
      ),
    );
    expect(find.text('00:00:01'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(kCountdownTickInterval);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('已到开播时间'), findsOneWidget);
    expect(refreshes, 1, reason: '到点只问一次,不能每拍都问');

    // 再走几拍:计数不许涨(本地时钟不是权威,但也不是发报机)
    now = now.add(const Duration(seconds: 3));
    await tester.pump(kCountdownTickInterval);
    await tester.pump(kCountdownTickInterval);
    expect(refreshes, 1);
    expect(find.text('重新检查'), findsOneWidget);
  });

  testWidgets('点「重新检查」= 再问一次;宿主忙时按不动,也不发', (WidgetTester tester) async {
    int refreshes = 0;
    DateTime now = DateTime(2026, 9, 17, 22, 59, 59);
    await tester.pumpWidget(
      host(
        PlayKitTimeWindowView(
          data: context(card(), onRefresh: () => refreshes += 1),
          now: () => now,
        ),
      ),
    );
    now = now.add(const Duration(seconds: 1));
    await tester.pump(kCountdownTickInterval);
    expect(refreshes, 1);

    await tester.tap(find.text('重新检查'));
    await tester.pump();
    expect(refreshes, 2, reason: '手动复核是同一颗入口,不是第二条链路');

    // 负控:宿主忙(上一次动作还没回来)时,到点也不许插队去重取状态
    await tester.pumpWidget(const SizedBox.shrink());
    int busyRefreshes = 0;
    DateTime busyNow = DateTime(2026, 9, 17, 22, 59, 59);
    await tester.pumpWidget(
      host(
        PlayKitTimeWindowView(
          data: context(
            card(),
            enabled: false,
            onRefresh: () => busyRefreshes += 1,
          ),
          now: () => busyNow,
        ),
      ),
    );
    busyNow = busyNow.add(const Duration(seconds: 1));
    await tester.pump(kCountdownTickInterval);
    expect(busyRefreshes, 0, reason: '宿主忙的时候到点也不打扰');
    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    expect(button.onPressed, isNull, reason: '宿主忙 = 上一次动作还没回来');
    expect(busyRefreshes, 0);
  });

  testWidgets('空态:openFrom 缺失/格式不对 → 00:00:00,不崩,也不假装到点', (
    WidgetTester tester,
  ) async {
    int refreshes = 0;
    await tester.pumpWidget(
      host(
        PlayKitTimeWindowView(
          data: context(
            card(kit: const <String, Object?>{}),
            onRefresh: () => refreshes += 1,
          ),
          now: () => DateTime(2026, 9, 17, 12),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('后开播'), findsOneWidget);
    expect(
      find.text('开放时段 --:-- – --:--'),
      findsOneWidget,
      reason: '缺数据如实显示,不编造',
    );
    expect(refreshes, 0, reason: '开点都没配上,没有可复核的东西');
  });
}
