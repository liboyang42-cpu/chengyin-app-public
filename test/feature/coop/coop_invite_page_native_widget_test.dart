import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/coop_invite.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/coop/coop_invite_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TopicApi implements TopicApi {
  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    expect(isMy, 1, reason: '选择源必须与后端发起人授权闸同为「我发布的」');
    return <Topic>[Topic(id: 11, name: '静安夜行'), Topic(id: 12, name: '徐汇书店巡礼')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget page, {List<dynamic> overrides = const <dynamic>[]}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(theme: AppTheme.dark(), home: page),
  );
}

void main() {
  testWidgets('固定预填俱乐部不能被删，固定费用用数字键盘且先校验', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        const CoopInvitePage(
          topicId: 9,
          topicName: '夜行路线',
          type: CoopInviteType.club,
          toId: 7,
          toName: '黑胶俱乐部',
          originApplyId: 66,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('① 关联主题'), findsOneWidget);
    expect(find.text('② 合作条款'), findsOneWidget);
    expect(find.text('③ 邀请对象'), findsOneWidget);
    expect(find.text('黑胶俱乐部'), findsOneWidget);
    expect(find.byKey(const Key('coop-pick-targets')), findsNothing);
    expect(find.byKey(const Key('coop-remove-target-7')), findsNothing);

    await tester.tap(find.text('固定带队费'));
    await tester.pump();
    final Finder fee = find.byKey(const Key('coop-fixed-fee'));
    expect(fee, findsOneWidget);
    expect(
      tester.widget<CupertinoTextField>(fee).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('coop-send-invite')))
          .onPressed,
      isNull,
      reason: '后端要求 fixedFee > 0，前端必须 fail closed',
    );

    await tester.enterText(fee, '12.50');
    await tester.pump();
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('coop-send-invite')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('coop-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('编辑邀约语'), findsOneWidget);
    expect(find.byKey(const Key('coop-invite-message')), findsOneWidget);
    expect(find.byKey(const Key('coop-confirm-invite')), findsOneWidget);
  });

  testWidgets('无 topicId 入口可用 Cupertino Sheet 选择我发布的主题', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const CoopInvitePage(),
        overrides: <dynamic>[topicApiProvider.overrideWithValue(_TopicApi())],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-pick-topic')));
    await tester.pumpAndSettle();
    expect(
      find.byType(CupertinoPageScaffold),
      findsNWidgets(2),
      reason: '发起邀请主页与主题选择 Sheet 都是 Cupertino 页面容器',
    );
    expect(find.text('选择我发布的主题'), findsWidgets);
    final Finder topicButton = find.ancestor(
      of: find.text('静安夜行'),
      matching: find.byType(CupertinoButton),
    );
    tester.widget<CupertinoButton>(topicButton).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('静安夜行'), findsOneWidget);
    expect(find.byKey(const Key('coop-pick-topic')), findsNothing);
  });
}
