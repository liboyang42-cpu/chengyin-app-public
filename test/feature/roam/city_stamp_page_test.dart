import 'package:chengyin_app/feature/roam/city_stamp_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

/// 城市贴纸 / 今日城市签(投资损面:投一张才换一张)。
///
/// 两半各管一件事:
///   ① 源码结构断言 —— 「先 create 再 exchange、create 失败绝不 exchange」
///      这条时序跑 Widget 测试要真相机 + 真上传,而**接反了不会报错**,
///      只会成为资损面(没投出去却换到了别人的票)。照 stamp_camera_idem_test
///      的先例,用时序断言钉住。
///   ② Widget 断言 —— 三步的入口文案与相机用途说明(合规:先弹用途再申请)。
/// 取某个方法体(从签名到配对的右花括号)。
String _bodyOf(String source, String signature) {
  final int at = source.indexOf(signature);
  expect(at, greaterThan(0), reason: '断言写法失效:找不到 $signature');
  final int open = source.indexOf('{', at);
  int depth = 1;
  int i = open + 1;
  while (i < source.length && depth > 0) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    i++;
  }
  return source.substring(open + 1, i - 1);
}

void main() {
  group('★★ 投一张换一张:时序不许反', () {
    final String code = codeOf('lib/feature/roam/city_stamp_page.dart');

    test('图先上传 → create 存下自己那张 → 才 exchange 换别人的', () {
      final String deliverBody = _bodyOf(code, 'Future<void> _deliver()');
      final int upload = deliverBody.indexOf('.uploadImage(');
      final int create = deliverBody.indexOf('.createStamp(');
      final int exchange = deliverBody.indexOf('.stampExchange(');

      expect(upload, greaterThan(0));
      expect(create, greaterThan(upload), reason: '本地临时路径别人看不到,必须先上传换可外链 URL');
      expect(exchange, greaterThan(create), reason: '没投成就不该换 —— 这是这个玩法唯一的资损面');
      expect(
        deliverBody,
        contains('.stampExchange(created.id)'),
        reason: '换票必须拿 create 回执的 id,不能用别的数',
      );
    });

    test('create 抛错走 _failDeliver(在同一段 try 里,不会掉到 exchange)', () {
      final String deliverBody = _bodyOf(code, 'Future<void> _deliver()');
      expect(
        deliverBody,
        contains('} on RoamApiException'),
        reason: 'create 抛错必须直接还按钮,不许继续换票',
      );
      expect(deliverBody, contains('_failDeliver(error.message)'));
      // 两个请求之间不许出现 catch —— 出现了就意味着 create 的错被吞掉后还会往下走
      final String between = deliverBody.substring(
        deliverBody.indexOf('.createStamp('),
        deliverBody.indexOf('.stampExchange('),
      );
      expect(between.contains('catch'), isFalse);
    });

    test('换不到只是空态:reason 透传,不是「失败」弹窗', () {
      expect(code.contains('exchanged.reason'), isTrue);
      expect(code.contains('还没有可以换的票'), isTrue);
    });

    test('「收下，出发」的闸:换到了票但没看 TA 那句就拦', () {
      final String body = _bodyOf(code, 'void _done()');
      expect(body.contains('_got && !_revealed'), isTrue);
      expect(body.contains('先看看 TA 留给你的那句'), isTrue);
    });

    test('已投出之后不许再重拍(重拍会把投出去的证据清掉)', () {
      final String body = _bodyOf(code, 'void _retake()');
      expect(body.contains('if (_sent) return;'), isTrue);
    });
  });

  group('Widget:入口与合规', () {
    Future<void> pump(WidgetTester tester, {String kind = 'sign'}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: CityStampPage(kind: kind, place: '武康路')),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('今日城市签:标题 / 站名 / 投一张换一张的说明', (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('今日城市签'), findsOneWidget);
      expect(find.text('拍一张 武康路 的样子'), findsOneWidget);
      expect(find.text('投一张,换一张 —— 写是代价,看是回报。'), findsOneWidget);
      expect(find.text('拍一张'), findsOneWidget);
    });

    testWidgets('从城市贴纸入口进来标题跟着变(kind=sticker)', (WidgetTester tester) async {
      await pump(tester, kind: 'sticker');
      expect(find.text('城市贴纸'), findsOneWidget);
    });

    testWidgets('相机先弹用途说明,点「暂不」不会去碰相机', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('拍一张'));
      await tester.pumpAndSettle();

      expect(find.text('开启相机拍一张'), findsOneWidget);
      expect(find.text('相机只用于拍这一张城市贴纸,不会录音,也不会后台拍摄。'), findsOneWidget);

      await tester.tap(find.text('暂不'));
      await tester.pumpAndSettle();

      // 没有用途同意就不申请权限、不进写签步
      expect(find.text('给下一个来这里的人留一句'), findsNothing);
    });
  });
}
