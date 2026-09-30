import 'dart:async';
import 'dart:ui' as ui;

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/im/route_picker_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TopicApi implements TopicApi {
  _TopicApi(this.result);

  final Future<List<Topic>> result;

  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CupertinoButton(
              onPressed: () async {
                selected = await pickRouteToShare(context);
                if (mounted) setState(() {});
              },
              child: const Text('选择路线'),
            ),
            Text('selected:${selected ?? '-'}'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('路线 Sheet 使用 Apple 原生列表并保留顺序、返回值和辅助功能', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topicApiProvider.overrideWithValue(
            _TopicApi(
              Future<List<Topic>>.value(<Topic>[
                Topic(id: 7, name: '夜游苏河', introduction: '从桥上读懂城市'),
                Topic(id: 9, name: '梧桐漫步'),
              ]),
            ),
          ),
        ],
        child: const CupertinoApp(home: _Host()),
      ),
    );

    await tester.tap(find.text('选择路线'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(CupertinoListSection), findsOneWidget);
    expect(find.byType(CupertinoListTile), findsNWidgets(2));

    final Finder first = find.byKey(const Key('route-pick-7'));
    final Finder second = find.byKey(const Key('route-pick-9'));
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.getSize(first).height, greaterThanOrEqualTo(44));

    final firstData = tester
        .getSemantics(find.bySemanticsLabel('选择夜游苏河，从桥上读懂城市'))
        .getSemanticsData();
    expect(firstData.flagsCollection.isButton, isTrue);
    expect(firstData.hasAction(ui.SemanticsAction.tap), isTrue);

    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('selected:7'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('路线 Sheet 保留 Apple 原生加载态', (WidgetTester tester) async {
    final Completer<List<Topic>> pending = Completer<List<Topic>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topicApiProvider.overrideWithValue(_TopicApi(pending.future)),
        ],
        child: const CupertinoApp(home: _Host()),
      ),
    );

    await tester.tap(find.text('选择路线'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CupertinoListSection), findsNothing);
  });

  testWidgets('路线 Sheet 保留空态文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topicApiProvider.overrideWithValue(
            _TopicApi(Future<List<Topic>>.value(<Topic>[])),
          ),
        ],
        child: const CupertinoApp(home: _Host()),
      ),
    );

    await tester.tap(find.text('选择路线'));
    await tester.pumpAndSettle();

    expect(find.text('没有找到路线'), findsOneWidget);
    expect(find.text('还没有可分享的路线'), findsOneWidget);
    expect(find.byType(CupertinoListSection), findsNothing);
  });
}
