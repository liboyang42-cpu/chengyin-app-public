import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeParticipantApi implements ParticipantApi {
  _FakeParticipantApi({required this.listHandler});

  final Future<List<Participant>> Function() listHandler;
  String? savedName;
  String? savedPhone;
  int saveCalls = 0;

  @override
  Future<List<Participant>> list() => listHandler();

  @override
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    bool isDefault = false,
  }) async {
    saveCalls += 1;
    savedName = fullName;
    savedPhone = mobilePhone;
  }

  @override
  Future<void> remove(int id) async {}

  @override
  Future<void> setDefault(int id) async {}
}

class _Host extends StatelessWidget {
  const _Host({required this.preferNative});

  final bool preferNative;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: _PickerHome(preferNative: preferNative));
  }
}

class _PickerHome extends StatefulWidget {
  const _PickerHome({required this.preferNative});

  final bool preferNative;

  @override
  State<_PickerHome> createState() => _PickerHomeState();
}

class _PickerHomeState extends State<_PickerHome> {
  Participant? selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          CupertinoButton(
            onPressed: () async {
              final Participant? result = await pickParticipant(
                context,
                preferNative: widget.preferNative,
              );
              if (mounted) setState(() => selected = result);
            },
            child: const Text('打开参与人选择'),
          ),
          Text(
            selected == null ? '尚未选择' : '${selected!.id}:${selected!.fullName}',
          ),
        ],
      ),
    );
  }
}

Future<void> _pumpHost(
  WidgetTester tester,
  _FakeParticipantApi api, {
  bool preferNative = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [participantApiProvider.overrideWithValue(api)],
      child: _Host(preferNative: preferNative),
    ),
  );
}

void main() {
  const Participant first = Participant(
    id: 9,
    fullName: '林野',
    mobilePhone: '13800008001',
  );
  const Participant second = Participant(
    id: 3,
    fullName: '陈晨',
    mobilePhone: '13900006002',
  );

  testWidgets('加载态可见，列表保持接口顺序，点选后返回原始真实 id', (WidgetTester tester) async {
    final Completer<List<Participant>> pending = Completer<List<Participant>>();
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () => pending.future,
    );
    await _pumpHost(tester, api);

    await tester.tap(find.text('打开参与人选择'));
    await tester.pump();
    expect(find.byKey(const Key('participant-picker-loading')), findsOneWidget);

    pending.complete(const <Participant>[first, second]);
    await tester.pumpAndSettle();
    final Finder firstRow = find.byKey(const Key('participant-row-9'));
    final Finder secondRow = find.byKey(const Key('participant-row-3'));
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);
    expect(
      tester.getTopLeft(firstRow).dy,
      lessThan(tester.getTopLeft(secondRow).dy),
    );

    await tester.tap(secondRow);
    await tester.pumpAndSettle();
    expect(find.text('3:陈晨'), findsOneWidget);
  });

  testWidgets('错误态保留原因并可重试，取消返回不产生选择', (WidgetTester tester) async {
    int calls = 0;
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async {
        calls += 1;
        if (calls == 1) throw Exception('网络异常，请重试');
        return const <Participant>[first];
      },
    );
    await _pumpHost(tester, api);

    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    expect(find.text('没能读到参与人'), findsOneWidget);
    expect(find.text('网络异常，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('participant-row-9')), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('尚未选择'), findsOneWidget);
  });

  testWidgets('空态与新增入口逐字对齐小程序', (WidgetTester tester) async {
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => const <Participant>[],
    );
    await _pumpHost(tester, api);

    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    expect(find.text('选择参与人信息'), findsOneWidget);
    expect(find.text('暂无参与人信息'), findsOneWidget);
    expect(find.text('新增参与人信息'), findsOneWidget);
  });

  testWidgets('取消新增返回参与人选择层，不退出报名选择流程', (WidgetTester tester) async {
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => const <Participant>[first],
    );
    await _pumpHost(tester, api);
    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增参与人信息'));
    await tester.pumpAndSettle();
    expect(find.text('参与人信息'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('选择参与人信息'), findsOneWidget);
    expect(find.byKey(const Key('participant-row-9')), findsOneWidget);
    expect(find.text('尚未选择'), findsOneWidget);
  });

  testWidgets('新增表单验证文案、键盘与 44pt 保存命中区', (WidgetTester tester) async {
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => const <Participant>[],
    );
    await _pumpHost(tester, api);
    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增参与人信息'));
    await tester.pumpAndSettle();

    expect(find.text('参与人信息'), findsOneWidget);
    expect(find.text('用于报名联系和到场核验，不会公开展示，也不用于配送。'), findsOneWidget);
    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('手机号'), findsOneWidget);
    final Finder save = find.text('保存参与人信息');
    expect(
      tester
          .getSize(
            find
                .ancestor(of: save, matching: find.byType(CupertinoButton))
                .first,
          )
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(save);
    await tester.pump();
    expect(find.text('请输入姓名'), findsOneWidget);

    final Finder fields = find.byType(CupertinoTextFormFieldRow);
    await tester.enterText(fields.at(0), ' 林野 ');
    await tester.enterText(fields.at(1), '123');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('请输入正确的手机号'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fields.at(1),
              matching: find.byType(EditableText),
            ),
          )
          .keyboardType,
      TextInputType.phone,
    );
    expect(api.saveCalls, 0);
  });

  testWidgets('保存后必须回读新增 id，再把该参与人返回报名表单', (WidgetTester tester) async {
    var rows = const <Participant>[];
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => rows,
    );
    await _pumpHost(tester, api);
    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增参与人信息'));
    await tester.pumpAndSettle();

    final Finder fields = find.byType(CupertinoTextFormFieldRow);
    await tester.enterText(fields.at(0), ' 林野 ');
    await tester.enterText(fields.at(1), '13800008001');
    rows = const <Participant>[
      Participant(id: 77, fullName: '林野', mobilePhone: '13800008001'),
    ];
    await tester.tap(find.text('保存参与人信息'));
    await tester.pumpAndSettle();

    expect(api.saveCalls, 1);
    expect(api.savedName, '林野');
    expect(api.savedPhone, '13800008001');
    expect(find.text('77:林野'), findsOneWidget);
  });

  testWidgets('旧 iOS 或 MissingPlugin 时完整回退 Cupertino 选择器', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) => throw MissingPluginException(call.method),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => const <Participant>[first],
    );
    await _pumpHost(tester, api, preferNative: true);

    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPopupSurface), findsOneWidget);
    expect(find.byKey(const Key('participant-row-9')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('回读不到新 id 时不伪造、不重复保存，只允许重新读取', (WidgetTester tester) async {
    var rows = const <Participant>[first];
    final _FakeParticipantApi api = _FakeParticipantApi(
      listHandler: () async => rows,
    );
    await _pumpHost(tester, api);
    await tester.tap(find.text('打开参与人选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增参与人信息'));
    await tester.pumpAndSettle();

    final Finder fields = find.byType(CupertinoTextFormFieldRow);
    await tester.enterText(fields.at(0), '林野');
    await tester.enterText(fields.at(1), '13800008001');
    await tester.tap(find.text('保存参与人信息'));
    await tester.pumpAndSettle();
    expect(find.text('参与人已保存，但没能回读真实编号，请重试读取'), findsOneWidget);
    expect(find.text('重新读取参与人信息'), findsOneWidget);
    expect(api.saveCalls, 1);
    expect(find.text('9:林野'), findsNothing);

    rows = const <Participant>[
      first,
      Participant(id: 88, fullName: '林野', mobilePhone: '13800008001'),
    ];
    await tester.tap(find.text('重新读取参与人信息'));
    await tester.pumpAndSettle();
    expect(api.saveCalls, 1);
    expect(find.text('88:林野'), findsOneWidget);
  });
}
