// 「+」= 动作菜单(图片 / 位置 / 路线),对齐小程序 im/chat 的 plus 面板
// (`plusSheetItems: ['图片','位置','路线']`)。
//
// ★ 此前「+」直连路线选择器 —— 小程序能发的三样里 App 只有一样,
//   而且点「+」得到的是一张路线 sheet,不是"选择要发什么"。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_image_source_sheet.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _FakeImApi implements ImApi {
  /// 上传失败时抛什么(默认不抛)。
  Object? uploadError;

  /// 记下每一次 send 的原始参数 —— 断言"发出去的到底是什么"。
  final List<({String content, int msgType, String? extraJson})> sent = [];

  final List<String> uploaded = [];

  @override
  Future<ChatPage> messages(int conversationId,
          {int cursorId = 0, int size = 30}) async =>
      ChatPage(list: <ChatMessage>[]);

  @override
  Future<void> read(int conversationId) async {}

  @override
  Future<String> uploadImage(String filePath) async {
    if (uploadError != null) throw uploadError!;
    uploaded.add(filePath);
    return 'https://oss.invalid/chat-${uploaded.length}.jpg';
  }

  @override
  Future<ChatMessage> send(int conversationId,
      {required String content,
      int msgType = kMsgText,
      String? extraJson}) async {
    sent.add((content: content, msgType: msgType, extraJson: extraJson));
    return ChatMessage(
      id: 100 + sent.length,
      conversationId: conversationId,
      senderId: 1,
      msgType: msgType,
      content: content,
      extraJson: extraJson,
      createTime: '2026-01-15 20:20:00',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTopicApi implements TopicApi {
  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) async => <Topic>[
    Topic(id: 7, name: '沿江夜骑'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpChat(
  WidgetTester tester, {
  _FakeImApi? api,
  ImImagePicker? picker,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(api ?? _FakeImApi()),
        topicApiProvider.overrideWithValue(_FakeTopicApi()),
        if (picker != null) imImagePickerProvider.overrideWithValue(picker),
      ].cast(),
      child: const MaterialApp(
        home: ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★★ 「+」弹动作菜单:图片 / 位置 / 路线(与小程序 plus 面板同集合)', (
    WidgetTester tester,
  ) async {
    await _pumpChat(tester);

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();

    for (final String label in <String>['图片', '位置', '路线']) {
      expect(find.text(label), findsOneWidget, reason: '小程序能发的 $label,这里也要有');
    }
  });

  testWidgets('★ 「+」→ 图片:来源选择(拍照 / 从相册选择 / 取消)', (
    WidgetTester tester,
  ) async {
    await _pumpChat(tester);

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('★ 「+」→ 路线:选路线 sheet 照旧可达', (WidgetTester tester) async {
    await _pumpChat(tester);

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('路线'));
    await tester.pumpAndSettle();

    expect(find.text('选择路线'), findsWidgets);
    expect(find.text('沿江夜骑'), findsOneWidget);
  });

  testWidgets('★★ 图片全链路:取图 → 上传 OSS → 以 msg_type=2 发出(URL 是 content)', (
    WidgetTester tester,
  ) async {
    final _FakeImApi api = _FakeImApi();
    await _pumpChat(
      tester,
      api: api,
      picker: (CyImagePickSource source) async {
        expect(source, CyImagePickSource.gallery);
        return XFile('/tmp/照片.jpg');
      },
    );

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(api.uploaded, <String>['/tmp/照片.jpg']);
    expect(api.sent, hasLength(1));
    final sent = api.sent.single;
    expect(sent.msgType, kMsgImage, reason: '图片必须是 msg_type=2');
    expect(
      sent.content,
      'https://oss.invalid/chat-1.jpg',
      reason: 'content 是 OSS URL 本身 —— 不是「[图片]」这类展示文案',
    );
    expect(sent.extraJson, isNull);
  });

  testWidgets('★ 上传失败:给后端原文提示,不假装发出去了', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi()
      ..uploadError = Exception('图片安全检查不通过');
    await _pumpChat(
      tester,
      api: api,
      picker: (CyImagePickSource source) async => XFile('/tmp/照片.jpg'),
    );

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('图片安全检查不通过'), findsOneWidget);
    expect(api.sent, isEmpty, reason: '没上传成功就不该发出任何消息');
  });

  testWidgets('★ 取图失败:给一句解释,不是崩掉', (WidgetTester tester) async {
    await _pumpChat(
      tester,
      picker: (CyImagePickSource source) async => throw Exception('picker 不可用'),
    );

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('没能打开相册或相机，请重试'), findsOneWidget);
  });
}
