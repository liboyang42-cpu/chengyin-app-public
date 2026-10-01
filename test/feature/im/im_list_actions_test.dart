import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('原生会话操作保持 标已读→免打扰→删除→取消 的真源顺序', (WidgetTester tester) async {
    final presenter = _ActionPresenter(selected: null);
    await _pump(tester, presenter: presenter, muted: false, unread: 2);

    await tester.longPress(find.text('阿林'));
    await tester.pump();

    expect(presenter.calls, 1);
    expect(
      presenter.items.map((ImConversationActionItem item) => item.id).toList(),
      <String>['read', 'mute', 'delete', 'cancel'],
    );
    expect(
      presenter.items
          .map((ImConversationActionItem item) => item.title)
          .toList(),
      <String>['标已读', '免打扰', '删除', '取消'],
    );
    expect(presenter.items[2].isDestructive, isTrue);
    expect(presenter.items.last.isCancel, isTrue);
  });

  testWidgets('已静音显示恢复提醒；未知态不伪装未静音且不调用 API', (WidgetTester tester) async {
    final mutedPresenter = _ActionPresenter(selected: null);
    await _pump(tester, presenter: mutedPresenter, muted: true);
    await tester.longPress(find.text('阿林'));
    await tester.pump();
    expect(mutedPresenter.items[1].title, '恢复提醒');

    final unknownPresenter = _ActionPresenter(selected: 'mute');
    final api = _FakeImApi();
    await _pump(tester, presenter: unknownPresenter, api: api, muted: null);
    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();

    expect(unknownPresenter.items[1].title, '提醒状态暂不可用');
    expect(api.muteValues, isEmpty);
    expect(find.textContaining('提醒状态暂不可用'), findsOneWidget);
  });

  testWidgets('标已读即使 unread=0 仍可调用，并按服务端真相刷新列表', (WidgetTester tester) async {
    final presenter = _ActionPresenter(selected: 'read');
    final api = _FakeImApi();
    var loads = 0;
    await _pump(
      tester,
      presenter: presenter,
      api: api,
      unread: 0,
      onLoad: () => loads += 1,
    );

    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();

    expect(api.readIds, <int>[7]);
    expect(loads, 2);
  });

  testWidgets('免打扰与恢复提醒传正确极性，成功后刷新', (WidgetTester tester) async {
    final api = _FakeImApi();
    var loads = 0;
    await _pump(
      tester,
      presenter: _ActionPresenter(selected: 'mute'),
      api: api,
      muted: false,
      onLoad: () => loads += 1,
    );
    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();
    expect(api.muteValues, <bool>[true]);
    expect(loads, 2);

    await _pump(
      tester,
      presenter: _ActionPresenter(selected: 'mute'),
      api: api,
      muted: true,
    );
    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();
    expect(api.muteValues, <bool>[true, false]);
  });

  testWidgets('删除保留危险确认文案；取消不删，确认后才刷新', (WidgetTester tester) async {
    final api = _FakeImApi();
    var loads = 0;
    await _pump(
      tester,
      presenter: _ActionPresenter(selected: 'delete'),
      api: api,
      onLoad: () => loads += 1,
    );
    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();

    expect(find.text('删除会话'), findsOneWidget);
    expect(find.text('删除后不会清除对方消息记录，确定删除这条会话吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.deletedIds, isEmpty);
    expect(loads, 1);

    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deletedIds, <int>[7]);
    expect(loads, 2);
  });

  testWidgets('原生插件失败回落 Cupertino；大字体/减弱动态下动作仍可读可取消', (
    WidgetTester tester,
  ) async {
    final api = _FakeImApi();
    await _pump(
      tester,
      presenter: _ActionPresenter(
        selected: null,
        error: MissingPluginException('native unavailable'),
      ),
      api: api,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
    );

    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    for (final label in <String>['标已读', '免打扰', '删除', '取消']) {
      expect(find.text(label), findsOneWidget);
    }
    final Finder deleteAction = find.ancestor(
      of: find.text('删除'),
      matching: find.byType(CupertinoActionSheetAction),
    );
    expect(tester.getSize(deleteAction).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.totalCalls, 0);
  });

  testWidgets('同一会话并发长按只呈现一层菜单，且 VoiceOver 能发现入口', (WidgetTester tester) async {
    final completer = Completer<String?>();
    final presenter = _ActionPresenter(selectedFuture: completer.future);
    await _pump(tester, presenter: presenter);
    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            widget.properties.label == '阿林，会话，长按显示操作',
      ),
      findsOneWidget,
    );

    await tester.longPress(find.text('阿林'));
    await tester.pump();
    await tester.longPress(find.text('阿林'));
    await tester.pump();
    expect(presenter.calls, 1);

    completer.complete(null);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('原生通道返回未知动作时 fail closed', (WidgetTester tester) async {
    final api = _FakeImApi();
    var loads = 0;
    await _pump(
      tester,
      presenter: _ActionPresenter(selected: 'unexpected'),
      api: api,
      onLoad: () => loads += 1,
    );

    await tester.longPress(find.text('阿林'));
    await tester.pumpAndSettle();

    expect(api.totalCalls, 0);
    expect(loads, 1);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ImConversationActionPresenter presenter,
  _FakeImApi? api,
  bool? muted = false,
  int unread = 1,
  VoidCallback? onLoad,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  final fakeApi = api ?? _FakeImApi();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(fakeApi),
        imConversationsProvider.overrideWith((Ref ref) async {
          onLoad?.call();
          return <Conversation>[
            Conversation(
              conversationId: 7,
              type: kImTypeSingle,
              counterparty: ImCounterparty(id: 8, nickname: '阿林', avatar: ''),
              lastMsgText: '周六见',
              unread: unread,
              muted: muted,
            ),
          ];
        }),
      ].cast(),
      child: MaterialApp(
        home: ImListPage(actionPresenter: presenter),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ActionPresenter implements ImConversationActionPresenter {
  _ActionPresenter({this.selected, this.selectedFuture, this.error});

  final String? selected;
  final Future<String?>? selectedFuture;
  final Object? error;
  int calls = 0;
  List<ImConversationActionItem> items = <ImConversationActionItem>[];

  @override
  bool get supportsNativeActionSheet => true;

  @override
  Future<String?> showActionSheet({
    required BuildContext context,
    required List<ImConversationActionItem> items,
  }) async {
    calls += 1;
    this.items = items;
    final Object? failure = error;
    if (failure != null) throw failure;
    return selectedFuture ?? Future<String?>.value(selected);
  }
}

class _FakeImApi implements ImApi {
  final List<int> readIds = <int>[];
  final List<bool> muteValues = <bool>[];
  final List<int> deletedIds = <int>[];

  int get totalCalls => readIds.length + muteValues.length + deletedIds.length;

  @override
  Future<void> read(int conversationId) async => readIds.add(conversationId);

  @override
  Future<ImReceipt> muteReceipt(int conversationId, {required bool muted}) async =>
      ImReceipt(muted ? ImReceiptKind.muted : ImReceiptKind.unmuted,
        serverMessage: await mute(conversationId, muted: muted));

  @override
  Future<String> mute(int conversationId, {required bool muted}) async {
    muteValues.add(muted);
    return muted ? '已开启免打扰' : '已关闭免打扰';
  }

  @override
  Future<ImReceipt> deleteConversationReceipt(int conversationId) async =>
      ImReceipt(ImReceiptKind.deleted, serverMessage: await deleteConversation(conversationId));

  @override
  Future<String> deleteConversation(int conversationId) async {
    deletedIds.add(conversationId);
    return '已删除';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
