import 'dart:ui' as ui;

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';
import 'package:chengyin_app/feature/publish/publish_pro_sheets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCategoryApi extends CategoryApi {
  _FakeCategoryApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<List<Category>> list({String? type}) async => <Category>[
    Category(id: 11, name: '城市漫步'),
    Category(id: 12, name: '建筑观察'),
  ];
}

class _SheetHost extends StatefulWidget {
  const _SheetHost();

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  String result = '未提交';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          CupertinoButton(
            key: const Key('open-chapter'),
            onPressed: () async {
              final ChapterSheetResult? value = await showChapterSheet(
                context,
                name: '',
                description: '',
                isEdit: true,
                isCity: false,
              );
              if (mounted && value != null) {
                setState(() => result = value.deleted ? '删除' : value.name);
              }
            },
            child: const Text('章节'),
          ),
          CupertinoButton(
            key: const Key('open-chapter-city'),
            onPressed: () async {
              final ChapterSheetResult? value = await showChapterSheet(
                context,
                name: '第一章',
                description: '',
                isEdit: true,
                isCity: true,
                audioUrl: 'https://cdn/ch.mp3',
                atmospherePreset: 'NIGHT',
              );
              if (mounted && value != null) {
                setState(
                  () => result = value.deleted
                      ? '删除'
                      : '${value.atmospherePreset}/${value.audioUrl}',
                );
              }
            },
            child: const Text('城市章节'),
          ),
          CupertinoButton(
            key: const Key('open-chapter-recruit'),
            onPressed: () async {
              final ChapterSheetResult? value = await showChapterSheet(
                context,
                name: '第一章',
                description: '',
                isEdit: true,
                isCity: false,
                merchantPoolEditable: true,
                recruitEnabled: 1,
                termsMode: 'PERK',
                categoryId: 7,
                categoryName: '餐饮',
                maxMerchant: 3,
                perkMinValue: '50',
              );
              if (mounted && value != null) {
                setState(
                  () => result =
                      '${value.recruitEnabled}/${value.termsMode}/'
                      '${value.categoryId}/${value.maxMerchant}/'
                      '${value.perkMinValue}',
                );
              }
            },
            child: const Text('主理人章节'),
          ),
          CupertinoButton(
            key: const Key('open-chapter-recruit-blank'),
            onPressed: () async {
              final ChapterSheetResult? value = await showChapterSheet(
                context,
                name: '第一章',
                description: '',
                isEdit: true,
                isCity: false,
                merchantPoolEditable: true,
              );
              if (mounted && value != null) {
                setState(
                  () => result =
                      '${value.recruitEnabled}/${value.categoryId}/'
                      '${value.categoryName}',
                );
              }
            },
            child: const Text('主理人空章节'),
          ),
          CupertinoButton(
            key: const Key('open-mode'),
            onPressed: () async {
              final int? value = await showModePickerSheet(context, current: 1);
              if (mounted && value != null) setState(() => result = '模式$value');
            },
            child: const Text('模式'),
          ),
          Text(result),
        ],
      ),
    );
  }
}

class _RichSheetHost extends ConsumerStatefulWidget {
  const _RichSheetHost({this.topicImage = false, this.nodeImage = false});

  final bool topicImage;
  final bool nodeImage;

  @override
  ConsumerState<_RichSheetHost> createState() => _RichSheetHostState();
}

class _RichSheetHostState extends ConsumerState<_RichSheetHost> {
  late final PublishDraft draft = PublishDraft()
    ..name = '静安漫步'
    ..productType = kProductFreeExplore
    ..imgArr = widget.topicImage ? 'https://img.example/topic.jpg' : '';
  String result = '未提交';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: <Widget>[
          CupertinoButton(
            key: const Key('open-category'),
            onPressed: () => showCategorySheet(
              context,
              ref: ref,
              draft: draft,
              onChanged: () => setState(() {}),
            ),
            child: const Text('类别'),
          ),
          CupertinoButton(
            key: const Key('open-topic'),
            onPressed: () => showTopicDetailSheet(
              context,
              ref: ref,
              draft: draft,
              myClubs: <Club>[
                Club(id: 1, name: '城瘾俱乐部'),
                Club(id: 2, name: '建筑观察社'),
              ],
              onChanged: () => setState(() {}),
              onCategoryTap: () {},
            ),
            child: const Text('主题'),
          ),
          CupertinoButton(
            key: const Key('open-node'),
            onPressed: () async {
              final NodeSheetResult? value = await showNodeSheet(
                context,
                ref: ref,
                draft: draft,
                node: widget.nodeImage
                    ? (PublishNode()
                        ..name = '武康大楼'
                        ..imgUrl = 'https://img.example/node.jpg')
                    : null,
              );
              if (mounted && value != null) {
                setState(() => result = value.node.name);
              }
            },
            child: const Text('节点'),
          ),
          CupertinoButton(
            key: const Key('open-check'),
            onPressed: () async {
              final bool? value = await showPublishCheckSheet(
                context,
                blocking: <PublishCheckItem>[],
                advisory: <PublishCheckItem>[
                  PublishCheckItem(label: '建议补充封面', tab: 0),
                ],
              );
              if (mounted && value != null) {
                setState(() => result = '检查$value');
              }
            },
            child: const Text('检查'),
          ),
          CupertinoButton(
            key: const Key('open-success'),
            onPressed: () async {
              final String? value = await showPublishSuccessSheet(
                context,
                name: '静安漫步',
                topicId: 7,
                chapterCount: 2,
                nodeCount: 5,
                isCity: true,
              );
              if (mounted && value != null) {
                setState(() => result = '成功$value');
              }
            },
            child: const Text('成功'),
          ),
          Text(result),
          Text('类别:${draft.categoryNames.join(',')}'),
        ],
      ),
    );
  }
}

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          categoryApiProvider.overrideWithValue(_FakeCategoryApi()),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const _SheetHost(),
        ),
      ),
    );
  }

  Future<void> pumpRichHost(
    WidgetTester tester, {
    bool topicImage = false,
    bool nodeImage = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          categoryApiProvider.overrideWithValue(_FakeCategoryApi()),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: _RichSheetHost(topicImage: topicImage, nodeImage: nodeImage),
        ),
      ),
    );
  }

  /// 章节 sheet 是整页滚动的 ListView:承接段展开后「完成」会落到屏外,
  /// 直接 tap 会打空(warnIfMissed)。先滚到位再点 —— 真人走的就是这条滚动。
  Future<void> tapChapterComplete(WidgetTester tester) async {
    final Finder complete = find.byKey(const Key('chapter-complete'));
    await tester.ensureVisible(complete);
    await tester.pumpAndSettle();
    await tester.tap(complete);
    await tester.pumpAndSettle();
  }

  testWidgets('章节编辑使用可滚动 Cupertino sheet 与系统文本输入，字段合同不变', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('编辑章节'), findsOneWidget);
    expect(find.text('章节名称'), findsOneWidget);
    expect(find.text('这一章讲什么？（选填）'), findsOneWidget);

    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].maxLength, 30);
    expect(fields[0].keyboardType, TextInputType.text);
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[0].clearButtonMode, OverlayVisibilityMode.editing);
    expect(fields[1].maxLength, 500);
    expect(fields[1].keyboardType, TextInputType.multiline);
    expect(fields[1].textInputAction, TextInputAction.newline);

    final Finder complete = find.byKey(const Key('chapter-complete'));
    final Finder delete = find.byKey(const Key('chapter-delete'));
    expect(tester.getSize(complete).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(delete).height, greaterThanOrEqualTo(44));

    await tester.enterText(find.byType(CupertinoTextField).first, '第一章');
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(find.text('第一章'), findsOneWidget);
  });

  testWidgets('城市定向章节:音频行与五档配色都在，选择会带回结果', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-city')));
    await tester.pumpAndSettle();

    // 城市定向正文只在故事流写,所以这一档没有第二个输入框。
    expect(find.text('章节音频'), findsOneWidget);
    expect(find.text('玩家进入本章时自动播放'), findsOneWidget);
    // 已有音频 ⇒ 露出的是文件行 + 移除,不是「添加音频」。
    expect(find.byKey(const Key('chapter-audio-add')), findsNothing);
    expect(find.byKey(const Key('chapter-audio-clear')), findsOneWidget);
    expect(find.text('已上传的音频'), findsOneWidget);

    expect(find.text('章节配色'), findsOneWidget);
    for (final a in kChapterAtmospheres) {
      expect(find.byKey(Key('chapter-atmosphere-${a.value}')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('chapter-atmosphere-RED')));
    await tester.pumpAndSettle();
    await tapChapterComplete(tester);
    expect(find.text('RED/https://cdn/ch.mp3'), findsOneWidget);
  });

  testWidgets('★ 存量氛围别名读回来要能显示 —— 不选也不会退成默认黑', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-city')));
    await tester.pumpAndSettle();
    await tapChapterComplete(tester);
    // 传进去的是存量值 NIGHT,归一到 BLUE 而不是 DEFAULT。
    expect(find.text('BLUE/https://cdn/ch.mp3'), findsOneWidget);
  });

  testWidgets('★ 删除章节先二次确认 —— 垃圾桶图标预告的后果必须真的发生', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chapter-delete')));
    await tester.pumpAndSettle();
    // 确认弹窗出来了,章节还没被删。
    expect(find.text('删除这一章?'), findsOneWidget);
    expect(find.text('删除'), findsWidgets);

    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('未提交'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chapter-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('★ 商家承接整段只对俱乐部主理人露出', (WidgetTester tester) async {
    await pumpHost(tester);
    // 普通身份(merchantPoolEditable 默认 false)开的那张:整段都不该在。
    await tester.tap(find.byKey(const Key('open-chapter')));
    await tester.pumpAndSettle();
    expect(
      find.text('商家承接'),
      findsNothing,
      reason: '玩家/商家看得到却开不了，开了要到发布时才被后端拒',
    );
    expect(find.byKey(const Key('chapter-recruit-toggle')), findsNothing);
    await tapChapterComplete(tester);

    await tester.tap(find.byKey(const Key('open-chapter-recruit')));
    await tester.pumpAndSettle();
    expect(find.text('商家承接'), findsOneWidget);
    expect(find.byKey(const Key('chapter-recruit-toggle')), findsOneWidget);
  });

  testWidgets('主理人:已配好的承接原样回显，完成后原样带回', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-recruit')));
    await tester.pumpAndSettle();

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('给权益'), findsOneWidget);
    expect(find.text('只引流'), findsOneWidget);

    await tapChapterComplete(tester);
    expect(find.text('1/PERK/7/3/50'), findsOneWidget);
  });

  testWidgets('★★ 开了承接却没选品类 —— 当场拦住，不让它到发布时才被后端拒', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-recruit-blank')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chapter-recruit-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chapter-recruit-category')), findsOneWidget);

    await tapChapterComplete(tester);
    // 弹窗没关,结果也没回传 —— 拦住了。
    expect(
      find.text('未提交'),
      findsOneWidget,
      reason: '放它过去 = 用户在发布时撞一个自己修不了的报错',
    );
    expect(find.textContaining('必须选择适合商家品类'), findsWidgets);

    // 选完品类就能过。
    await tester.tap(find.byKey(const Key('chapter-recruit-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市漫步'));
    await tester.pumpAndSettle();
    await tapChapterComplete(tester);
    expect(find.text('1/11/城市漫步'), findsOneWidget);
  });

  testWidgets('★ 切到只引流会把权益门槛清干净 —— 带着它后端会拒', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-recruit')));
    await tester.pumpAndSettle();

    expect(find.text('权益门槛 (¥)'), findsOneWidget);
    await tester.tap(find.text('只引流'));
    await tester.pumpAndSettle();
    expect(find.text('权益门槛 (¥)'), findsNothing, reason: '只引流档没有权益门槛这回事');

    await tapChapterComplete(tester);
    expect(find.text('1/TRAFFIC/7/3/null'), findsOneWidget);
  });

  testWidgets('★ 只引流转一圈再回给权益，门槛不许自己长回来', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-chapter-recruit')));
    await tester.pumpAndSettle();

    // Key 挂在外层 _NumberBox 上,输入框是它的孩子。
    String perkText() => tester
        .widget<CupertinoTextField>(
          find.descendant(
            of: find.byKey(const Key('chapter-recruit-perk')),
            matching: find.byType(CupertinoTextField),
          ),
        )
        .controller!
        .text;

    // 进来时是给权益档，门槛 50。
    expect(perkText(), '50');

    await tester.tap(find.text('只引流'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('给权益'));
    await tester.pumpAndSettle();

    // 切走那一下就该把它清干净：留着的话用户以为没设，其实还带着 50 上送。
    expect(perkText(), '', reason: '门槛在切档时没被清掉，转一圈回来它又生效了');
    await tapChapterComplete(tester);
    expect(find.text('1/PERK/7/3/null'), findsOneWidget);
  });

  testWidgets('模式切换先暂选再确认，顺序文案和取消语义与小程序一致', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-mode')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoRadio<int>), findsNWidgets(2));
    expect(find.text('这个主题怎么玩？'), findsOneWidget);
    expect(find.text('城市定向'), findsOneWidget);
    expect(find.text('自由探索'), findsOneWidget);
    expect(find.textContaining('另外复制一份新草稿再切'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('城市定向')).dy,
      lessThan(tester.getTopLeft(find.text('自由探索')).dy),
    );

    await tester.tap(find.byKey(const Key('mode-option-2')));
    await tester.pump();
    expect(find.text('未提交'), findsOneWidget, reason: '点选只是暂选，不能偷改返回值');

    final Finder confirm = find.byKey(const Key('mode-confirm'));
    expect(tester.getSize(confirm).height, greaterThanOrEqualTo(44));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('模式2'), findsOneWidget);
  });

  testWidgets('关闭类别是唯一、有名称且可执行的 VoiceOver 按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-category')));
    await tester.pumpAndSettle();

    final Finder action = find.bySemanticsLabel('关闭类别选择');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category-close')), findsNothing);
    semantics.dispose();
  });

  testWidgets('类别多选使用 Cupertino 复选与确认事务，取消不偷写草稿', (WidgetTester tester) async {
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-category')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoCheckbox), findsNWidgets(2));
    expect(find.text('城市漫步'), findsOneWidget);
    expect(find.text('建筑观察'), findsOneWidget);
    expect(find.text('已选择 0 个'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-11')));
    await tester.pump();
    expect(find.text('已选择 1 个'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category-close')));
    await tester.pumpAndSettle();
    expect(find.text('类别:'), findsOneWidget, reason: '关闭只丢弃暂选，不能写入草稿');

    await tester.tap(find.byKey(const Key('open-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category-12')));
    await tester.tap(find.byKey(const Key('category-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('类别:建筑观察'), findsOneWidget);
  });

  testWidgets('主题富内容使用系统输入、开关与俱乐部 Action Sheet，字段顺序不变', (
    WidgetTester tester,
  ) async {
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-topic')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(3));
    expect(find.byType(TextField), findsNothing);
    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].maxLength, 30);
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].maxLength, 1000);
    expect(fields[1].keyboardType, TextInputType.multiline);
    expect(fields[2].textInputAction, TextInputAction.done);

    expect(find.text('主题描述'), findsOneWidget);
    expect(find.textContaining('主题类别', findRichText: true), findsOneWidget);
    final Finder sheetList = find
        .descendant(
          of: find.byType(CupertinoPageScaffold),
          matching: find.byType(ListView),
        )
        .first;
    Future<void> reveal(Finder target) async {
      for (int i = 0; i < 12 && target.evaluate().isEmpty; i++) {
        await tester.drag(sheetList, const Offset(0, -220));
        await tester.pump();
      }
    }

    final Finder portrait = find.textContaining('竖版封面', findRichText: true);
    await reveal(portrait);
    expect(portrait, findsOneWidget);
    await reveal(find.text('剧情详情'));
    expect(find.text('剧情详情'), findsOneWidget);

    // 完成奖励(开关,关着只发通关勋章)与发布到创意广场两张卡都在这一屏。
    await reveal(find.text('归属俱乐部'));
    expect(find.text('完成奖励'), findsOneWidget);
    expect(find.text('关着：只发通关勋章'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNWidgets(2));
    // 2026-09-09 途中彩蛋整卡撤除后这张半屏变短,reveal 的定量拖拽会把这一行停在
    // 可视区边缘 —— 点得到 hit-test 却打不开 Action Sheet。先 ensureVisible 再点。
    await tester.ensureVisible(find.text('归属俱乐部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('归属俱乐部'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('城瘾俱乐部'), findsOneWidget);
    expect(find.text('建筑观察社'), findsOneWidget);
    expect(find.text('不挂靠俱乐部'), findsOneWidget);
  });

  testWidgets('关闭节点是唯一、有名称且可执行的 VoiceOver 按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-node')));
    await tester.pumpAndSettle();

    final Finder action = find.bySemanticsLabel('关闭节点编辑');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-close')), findsNothing);
    semantics.dispose();
  });

  testWidgets('节点编辑使用系统输入与开关，完成返回节点数据', (WidgetTester tester) async {
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-node')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].maxLength, 40);
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].maxLength, 500);
    expect(fields[1].keyboardType, TextInputType.multiline);

    await tester.enterText(find.byType(CupertinoTextField).first, '武康大楼');
    await tester.tap(find.byKey(const Key('node-complete')));
    await tester.pumpAndSettle();
    expect(find.text('武康大楼'), findsOneWidget);
  });

  testWidgets('主题横图删除按钮保留 16pt 图标并提供 44pt 热区与 VoiceOver 名称', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpRichHost(tester, topicImage: true);
    await tester.tap(find.byKey(const Key('open-topic')));
    await tester.pumpAndSettle();

    final Finder sheetList = find
        .descendant(
          of: find.byType(CupertinoPageScaffold),
          matching: find.byType(ListView),
        )
        .first;
    const Key removeKey = Key('topic-landscape-remove-0');
    for (int i = 0; i < 12 && find.byKey(removeKey).evaluate().isEmpty; i++) {
      await tester.drag(sheetList, const Offset(0, -180));
      await tester.pump();
    }

    final Finder remove = find.byKey(removeKey);
    expect(remove, findsOneWidget);
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('删除图片'), findsOneWidget);
    expect(
      find.descendant(
        of: remove,
        matching: find.byIcon(CupertinoIcons.xmark_circle_fill),
      ),
      findsOneWidget,
    );

    await tester.tap(remove);
    await tester.pump();
    expect(find.byKey(removeKey), findsNothing);
    semantics.dispose();
  });

  testWidgets('节点照片删除按钮保留 16pt 图标并提供 44pt 热区与 VoiceOver 名称', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpRichHost(tester, nodeImage: true);
    await tester.tap(find.byKey(const Key('open-node')));
    await tester.pumpAndSettle();

    final Finder sheetList = find
        .descendant(
          of: find.byType(CupertinoPageScaffold),
          matching: find.byType(ListView),
        )
        .first;
    const Key removeKey = Key('node-photo-remove-0');
    for (int i = 0; i < 16 && find.byKey(removeKey).evaluate().isEmpty; i++) {
      await tester.drag(sheetList, const Offset(0, -180));
      await tester.pump();
    }

    final Finder remove = find.byKey(removeKey);
    expect(remove, findsOneWidget);
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('删除节点照片 1'), findsOneWidget);
    expect(
      find.descendant(
        of: remove,
        matching: find.byIcon(CupertinoIcons.xmark_circle_fill),
      ),
      findsOneWidget,
    );

    await tester.tap(remove);
    await tester.pump();
    expect(find.byKey(removeKey), findsNothing);
    semantics.dispose();
  });

  testWidgets('发布检查与成功结果继续保持原返回语义', (WidgetTester tester) async {
    await pumpRichHost(tester);
    await tester.tap(find.byKey(const Key('open-check')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    // 小程序这一层的标题是「发布确认」(fabu/index.wxml 的 .pop-top .tit)。
    expect(find.text('发布确认'), findsOneWidget);
    expect(find.text('建议补充封面'), findsOneWidget);
    final Finder proceed = find.byKey(const Key('publish-check-continue'));
    expect(tester.getSize(proceed).height, greaterThanOrEqualTo(44));
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(find.text('检查true'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-success')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    // ★ 这时候只是提交完、还在审核里 —— 眉标不许写成「已发布」。
    expect(find.text('已提交'), findsOneWidget);
    expect(find.textContaining('审核通过后即可对外售票'), findsOneWidget);
    expect(find.textContaining('静安漫步'), findsOneWidget);
    expect(find.textContaining('城市定向 · 2 章 5 节点'), findsOneWidget);
    await tester.tap(find.byKey(const Key('publish-success-preview')));
    await tester.pumpAndSettle();
    expect(find.text('成功preview'), findsOneWidget);
  });
}
