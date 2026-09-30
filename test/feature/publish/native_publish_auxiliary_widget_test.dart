import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/models/ai_quota.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/ai_draft_sheet.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';
import 'package:chengyin_app/feature/publish/publish_pro_story_editor.dart';
import 'package:chengyin_app/feature/square/square_compose_page.dart';

void main() {
  testWidgets('广场发布保留小程序字段顺序并使用 iOS 输入与按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SquareComposePage())),
    );

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    final CupertinoTextField content = tester.widget(
      find.byKey(const Key('square-compose-content')),
    );
    expect(content.placeholder, '有什么新鲜好玩的分享吗？');
    expect(find.text('地点'), findsWidgets);
    expect(find.text('关联城市内容'), findsOneWidget);
    expect(find.byKey(const Key('square-compose-save-draft')), findsOneWidget);
    expect(find.byKey(const Key('square-compose-submit')), findsOneWidget);

    final Rect location = tester.getRect(find.text('地点').first);
    final Rect activity = tester.getRect(find.text('关联城市内容'));
    expect(location.top, lessThan(activity.top), reason: '保留先地点、后关联城市内容的顺序');
  });

  testWidgets('AI 起草用 Cupertino sheet 和系统多行键盘', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiQuotaProvider.overrideWith((Ref ref) async => const AiQuota()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showAiDraftSheet(context),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    final CupertinoTextField field = tester.widget(
      find.byKey(const Key('ai-idea-input')),
    );
    expect(field.placeholder, '描述你想做的路线');
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.textInputAction, TextInputAction.newline);
    expect(
      tester.getSize(find.byKey(const Key('ai-generate'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('故事流 sheet 的章节名与正文都使用系统键盘且插入点可触达', (WidgetTester tester) async {
    final PublishChapter chapter = PublishChapter()
      ..name = '第一章'
      ..blocks = <StoryBlock>[StoryBlock.text('b1', '原故事')];
    final PublishDraft draft = PublishDraft()
      ..chapters = <PublishChapter>[chapter];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showStoryEditorSheet(
              context,
              draft: draft,
              chapterIndex: 0,
              onChapterNameChanged: (String name) => chapter.name = name,
              onStoryChanged: (PublishChapter value) =>
                  draft.chapters[0] = value,
              onInsertNodeAt: (_) {},
              onEditNode: (_) {},
            ),
            child: const Text('打开故事流'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开故事流'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byKey(const Key('story-editor-chapter-name')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('b1')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('story-insert-0'))).height,
      greaterThanOrEqualTo(44),
    );

    await tester.enterText(find.byKey(const ValueKey<String>('b1')), '新故事');
    await tester.pump();
    expect(draft.chapters[0].blocks!.first.content, '新故事');
  });

  testWidgets('节点块向 VoiceOver 提供编辑与长按选中动作', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final PublishNode node = PublishNode()
      ..localId = 'node-1'
      ..name = '咖啡站'
      ..address = '静安寺';
    final PublishChapter chapter = PublishChapter()
      ..name = '第一章'
      ..nodes = <PublishNode>[node]
      ..blocks = <StoryBlock>[StoryBlock.node('block-1', 'node-1')];
    final PublishDraft draft = PublishDraft()
      ..chapters = <PublishChapter>[chapter];
    String? edited;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showStoryEditorSheet(
              context,
              draft: draft,
              chapterIndex: 0,
              onChapterNameChanged: (String name) => chapter.name = name,
              onStoryChanged: (PublishChapter value) =>
                  draft.chapters[0] = value,
              onInsertNodeAt: (_) {},
              onEditNode: (String id) => edited = id,
            ),
            child: const Text('打开节点故事流'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开节点故事流'));
    await tester.pumpAndSettle();

    final Finder action = find.bySemanticsLabel('编辑节点 咖啡站');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(data.hasAction(ui.SemanticsAction.longPress), isTrue);

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: tester.getSemantics(action).id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(edited, 'node-1');

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.longPress,
        nodeId: tester.getSemantics(action).id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    // 小程序这一格的 aria-label 是「删除节点块」;App 再加节点名(读屏听得出删的是哪个)。
    expect(find.bySemanticsLabel('删除节点块 咖啡站'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('★★ 故事流媒体按文字/图片/音频/节点排列，上传成功前不落块', (WidgetTester tester) async {
    final PublishChapter chapter = PublishChapter()
      ..name = '第一章'
      ..blocks = <StoryBlock>[StoryBlock.text('b1', '原故事')];
    final PublishDraft draft = PublishDraft()
      ..chapters = <PublishChapter>[chapter];
    final Completer<String?> upload = Completer<String?>();
    StoryMediaType? requestedType;

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showStoryEditorSheet(
              context,
              draft: draft,
              chapterIndex: 0,
              onChapterNameChanged: (String name) => chapter.name = name,
              onStoryChanged: (PublishChapter value) =>
                  draft.chapters[0] = value,
              onInsertNodeAt: (_) {},
              onEditNode: (_) {},
              pickAndUploadMedia: (StoryMediaType type) {
                requestedType = type;
                return upload.future;
              },
            ),
            child: const Text('打开媒体故事流'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开媒体故事流'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('story-insert-0')));
    await tester.pump();

    const List<String> labels = <String>['＋ 文字', '＋ 图片', '＋ 音频', '＋ 节点'];
    final List<double> positions = labels
        .map((String label) => tester.getCenter(find.text(label)).dx)
        .toList();
    expect(positions, orderedEquals(positions.toList()..sort()));

    await tester.tap(find.text('＋ 图片'));
    await tester.pump();
    expect(requestedType, StoryMediaType.image);
    expect(
      draft.chapters[0].blocks!.length,
      1,
      reason: '选了文件但上传未回 URL 时不能先落空壳块',
    );
    expect(find.text('图片上传中…'), findsOneWidget);

    upload.complete('https://cdn/story.jpg');
    await tester.pumpAndSettle();
    expect(draft.chapters[0].blocks!.first.type, 'image');
    expect(draft.chapters[0].blocks!.first.url, 'https://cdn/story.jpg');

    final String mediaKey = draft.chapters[0].blocks!.first.key;
    final Finder media = find.byKey(Key('story-media-$mediaKey'));
    expect(media, findsOneWidget, reason: '图片上传成功后要显示真媒体块');
    expect(find.byKey(Key('story-media-remove-$mediaKey')), findsNothing);
    await tester.longPress(media);
    await tester.pump();
    final Finder remove = find.byKey(Key('story-media-remove-$mediaKey'));
    expect(remove, findsOneWidget, reason: '小程序只在长按选中后显示删除键');
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
    await tester.tap(remove);
    await tester.pump();
    expect(draft.chapters[0].blocks!.map((StoryBlock b) => b.type), <String>[
      'text',
    ]);
  });

  testWidgets('音频块只显示编辑卡，不伪造播放回执', (WidgetTester tester) async {
    final PublishChapter chapter = PublishChapter()
      ..name = '第一章'
      ..blocks = <StoryBlock>[
        StoryBlock.audio('audio-1', 'https://cdn/story.m4a'),
      ];
    final PublishDraft draft = PublishDraft()
      ..chapters = <PublishChapter>[chapter];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showStoryEditorSheet(
              context,
              draft: draft,
              chapterIndex: 0,
              onChapterNameChanged: (String name) => chapter.name = name,
              onStoryChanged: (PublishChapter value) =>
                  draft.chapters[0] = value,
              onInsertNodeAt: (_) {},
              onEditNode: (_) {},
            ),
            child: const Text('打开音频块'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开音频块'));
    await tester.pumpAndSettle();
    expect(find.text('音频片段'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_circle_fill), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('story-media-audio-1')),
        matching: find.byType(CupertinoButton),
      ),
      findsNothing,
      reason: '小程序编辑器没有真播放回执，App 不能用假播放按钮充数',
    );
  });

  testWidgets('媒体上传失败使用页内轻提示且不落空壳块', (WidgetTester tester) async {
    addTearDown(CyNativeNotice.hide);
    final PublishChapter chapter = PublishChapter()
      ..name = '第一章'
      ..blocks = <StoryBlock>[StoryBlock.text('b1', '原故事')];
    final PublishDraft draft = PublishDraft()
      ..chapters = <PublishChapter>[chapter];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showStoryEditorSheet(
              context,
              draft: draft,
              chapterIndex: 0,
              onChapterNameChanged: (String name) => chapter.name = name,
              onStoryChanged: (PublishChapter value) =>
                  draft.chapters[0] = value,
              onInsertNodeAt: (_) {},
              onEditNode: (_) {},
              pickAndUploadMedia: (_) =>
                  Future<String?>.error(StateError('图片上传失败')),
            ),
            child: const Text('打开失败用例'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开失败用例'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('story-insert-0')));
    await tester.pump();
    await tester.tap(find.text('＋ 图片'));
    await tester.pumpAndSettle();

    expect(draft.chapters[0].blocks!.length, 1);
    // S7:纯告知不弹 alert(原为「知道了」单按钮 CupertinoAlertDialog)。
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('图片上传失败'), findsOneWidget);
  });
}
