import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';

/// 专业发布编辑器纯逻辑层测试。
/// 对齐小程序 utils/publish/pro-editor-policy.js / pro-editor-story.js /
/// publish-ticket-schedule.js / publish-validator.js 的既有行为。
void main() {
  _chapterCarryOverParity();

  _parity();

  group('hasUsableCoords:「没有坐标」与「坐标是 0」都不算', () {
    PublishNode node({String? lng, String? lat}) => PublishNode()
      ..longitude = lng ?? ''
      ..latitude = lat ?? '';

    test('合法坐标', () {
      expect(hasUsableCoords(node(lng: '121.4737', lat: '31.2304')), isTrue);
    });

    test('★ 空串 / 缺失 = 没有值,不是 0', () {
      expect(hasUsableCoords(node()), isFalse);
      expect(hasUsableCoords(node(lng: '121.4')), isFalse);
    });

    test('★ "0" 是后端/POI 的常见空值,不能当有效坐标', () {
      expect(hasUsableCoords(node(lng: '0', lat: '31.2')), isFalse);
      expect(hasUsableCoords(node(lng: '121.4', lat: '0')), isFalse);
      expect(hasUsableCoords(node(lng: '0', lat: '0')), isFalse);
    });

    test('越界与非数值不算', () {
      expect(hasUsableCoords(node(lng: '181', lat: '31.2')), isFalse);
      expect(hasUsableCoords(node(lng: '121.4', lat: '-91')), isFalse);
      expect(hasUsableCoords(node(lng: 'abc', lat: '31.2')), isFalse);
    });
  });

  group('hasRealStory:占位文案不算真剧情', () {
    test('空白与占位文案都算没写', () {
      expect(hasRealStory(PublishChapter()..description = ''), isFalse);
      expect(hasRealStory(PublishChapter()..description = '  '), isFalse);
      expect(hasRealStory(PublishChapter()..description = '暂无描述'), isFalse);
      expect(hasRealStory(PublishChapter()..description = '暂无'), isFalse);
      expect(hasRealStory(PublishChapter()..description = '无'), isFalse);
    });

    test('有真内容算写了', () {
      expect(hasRealStory(PublishChapter()..description = '真实的剧情'), isTrue);
    });

    test('块化章节:只投影第一个节点块之前的文字', () {
      final chapter = PublishChapter()
        ..blocks = <StoryBlock>[
          StoryBlock.text('k1', '开头文字'),
          StoryBlock.node('k2', 'n1'),
          StoryBlock.text('k3', '节点后的文字不该算'),
        ];
      chapter.nodes.add(PublishNode()..localId = 'n1');
      expect(hasRealStory(chapter), isTrue);

      final empty = PublishChapter()
        ..blocks = <StoryBlock>[
          StoryBlock.text('k1', ''),
          StoryBlock.node('k2', 'n1'),
          StoryBlock.text('k3', '有字但排在节点后'),
        ];
      empty.nodes.add(PublishNode()..localId = 'n1');
      expect(hasRealStory(empty), isFalse);
    });
  });

  group('chapterStatesOf', () {
    PublishDraft draft({int productType = kProductCity}) => PublishDraft()
      ..productType = productType
      ..chapters = <PublishChapter>[
        PublishChapter()
          ..description = '第一章剧情'
          ..nodes = <PublishNode>[
            PublishNode()
              ..longitude = '121.4'
              ..latitude = '31.2',
            PublishNode()
              ..longitude = ''
              ..latitude = '',
          ],
      ];

    test('城市定向:剧情写完才允许建节点', () {
      final states = chapterStatesOf(draft());
      expect(states.single.storyRequired, isTrue);
      expect(states.single.storyDone, isTrue);
      expect(states.single.canAddNode, isTrue);
      expect(states.single.nodesMissingCoords, 1);
      expect(states.single.gameplayPending, isTrue);
    });

    test('★ 城市定向没剧情 → canAddNode=false(领域依赖)', () {
      final d = draft()..chapters.first.description = '';
      final states = chapterStatesOf(d);
      expect(states.single.storyDone, isFalse);
      expect(states.single.canAddNode, isFalse);
    });

    test('自由探索:剧情不是硬要求', () {
      final d = draft(productType: kProductFreeExplore)
        ..chapters.first.description = '';
      final states = chapterStatesOf(d);
      expect(states.single.storyRequired, isFalse);
      expect(states.single.canAddNode, isTrue);
    });

    test('玩法配齐后 gameplayPending 消失(配齐是噪音)', () {
      final d = draft();
      d.chapters.first.nodes.first.templateId = 9;
      d.chapters.first.nodes[1].templateId = 9;
      final states = chapterStatesOf(d);
      expect(states.single.gameplayConfigured, 2);
      expect(states.single.gameplayPending, isFalse);
    });
  });

  group('blockingIssuesOf', () {
    test('空草稿把主题级必填都列出来', () {
      final issues = blockingIssuesOf(PublishDraft(), <ChapterState>[]);
      expect(
        issues.map((i) => i.key),
        containsAll(<String>[
          'name',
          'subtitle',
          'description',
          'imgUrl',
          'chapters',
        ]),
      );
    });

    test('★ 自由探索缺 recruitDeadline = 后端硬约束,前端必须拦', () {
      final d = PublishDraft()..productType = kProductFreeExplore;
      final issues = blockingIssuesOf(d, <ChapterState>[]);
      expect(issues.any((i) => i.key == 'recruitDeadline'), isTrue);
      // 城市定向不需要这条。
      final city = blockingIssuesOf(PublishDraft(), <ChapterState>[]);
      expect(city.any((i) => i.key == 'recruitDeadline'), isFalse);
    });

    test('节点缺名称/缺地点逐条定位到章节与节点', () {
      final d = PublishDraft()
        ..chapters = <PublishChapter>[
          PublishChapter()
            ..description = '剧情'
            ..nodes = <PublishNode>[
              PublishNode()
                ..name = ''
                ..longitude = ''
                ..latitude = '',
            ],
        ];
      final issues = blockingIssuesOf(d, chapterStatesOf(d));
      final nodeIssues = issues.where((i) => i.key == 'node').toList();
      expect(nodeIssues.length, 2, reason: '缺名称 + 缺地点各一条');
      expect(nodeIssues[0].chapterIndex, 0);
      expect(nodeIssues[0].nodeIndex, 0);
    });
  });

  group('starterAction 三起点', () {
    test('城市定向 → 写第一章;自由探索 → 添加第一个探索节点;俱乐部 → 地点', () {
      expect(defaultAnchorFor(kProductCity, null), 'story');
      expect(defaultAnchorFor(kProductFreeExplore, null), 'node');
      expect(defaultAnchorFor(kProductCity, 7), 'place');
      expect(starterActionFor('story').label, '写第一章');
      expect(starterActionFor('node').label, '添加第一个探索节点');
      expect(starterActionFor('place').label, '添加第一个地点');
    });
  });

  group('票务:cityOrientationScheduleIssues / canSaveTicket', () {
    PublishTicket ticket({int mode = kProductCity}) => PublishTicket()
      ..mode = mode
      ..name = '早鸟票';

    test('集合时间空 / 结束不晚于开始', () {
      expect(
        cityOrientationScheduleIssues(ticket()).map((i) => i.field),
        containsAll(<String>['startTime', 'endTime']),
      );
      final t = ticket()
        ..startTime = '2026-09-01 10:00:00'
        ..endTime = '2026-09-01 09:00:00';
      expect(cityOrientationScheduleIssues(t).single.message, '集合结束时间必须晚于开始时间');
    });

    test('★ 城市定向必须有集合地点', () {
      expect(canSaveTicket(ticket()), isFalse);
      expect(
        canSaveTicket(ticket()..meetingPoint = '静安寺'),
        isFalse,
        reason: '时间还没填',
      );
      expect(
        canSaveTicket(
          ticket()
            ..meetingPoint = '静安寺'
            ..startTime = '2026-09-01 10:00:00'
            ..endTime = '2026-09-01 12:00:00',
        ),
        isTrue,
      );
    });

    test('自由探索不要求集合地点', () {
      final t = ticket(mode: kProductFreeExplore)
        ..startTime = '2026-09-01 10:00:00'
        ..endTime = '2026-09-01 12:00:00';
      expect(canSaveTicket(t), isTrue);
    });
  });

  group('normalizeDateTime', () {
    test('纯日期补默认时分', () {
      expect(
        normalizeDateTime('2026-09-01', '00:00:00'),
        '2026-09-01 00:00:00',
      );
      expect(
        normalizeDateTime('2026-09-01', '23:59:59'),
        '2026-09-01 23:59:59',
      );
    });

    test('带时分规整成 :ss,ISO 串也收', () {
      expect(
        normalizeDateTime('2026-09-01 10:30', '00:00:00'),
        '2026-09-01 10:30:00',
      );
      expect(
        normalizeDateTime('2026-09-01T10:30:45', '00:00:00'),
        '2026-09-01 10:30:45',
      );
    });

    test('★ 没有值 → null,不是空串', () {
      expect(normalizeDateTime('', '00:00:00'), isNull);
      expect(normalizeDateTime(null, '00:00:00'), isNull);
      expect(normalizeDateTime('垃圾', '00:00:00'), isNull);
    });
  });

  group('故事流命令', () {
    PublishChapter chapter() {
      final c = PublishChapter()..description = '开头';
      c.nodes.add(
        PublishNode()
          ..localId = 'n1'
          ..name = '节点一',
      );
      return c;
    }

    var keySeq = 100;
    String newKey() => 'k${keySeq++}';

    test('物化:description 成首块 + 节点按 sortID 排队', () {
      final c = chapter();
      c.nodes.first.sortID = 2;
      final n2 = PublishNode()
        ..localId = 'n2'
        ..sortID = 1;
      c.nodes.add(n2);
      materializeChapter(c, newKey);
      expect(c.blocks!.length, 3);
      expect(c.blocks![0].type, 'text');
      expect(c.blocks![0].content, '开头');
      expect(c.blocks![1].type, 'node');
      expect(c.blocks![1].nodeKey, 'n2', reason: '节点顺序由 sortID 决定');
      expect(c.description, '开头');
      expect(c.nodes.first.sortID, 1);
    });

    test('插文字块', () {
      final c = chapter();
      materializeChapter(c, newKey);
      final r = applyStoryCommand(
        c,
        InsertTextAtCommand(index: 1, blockKey: newKey()),
      );
      expect(r.insertedBlockKey, isNotNull);
      expect(r.chapter.blocks![1].type, 'text');
    });

    test('★★ 图片/音频块只承载 URL，copy 不丢媒体', () {
      final image = StoryBlock.image('img-1', 'https://cdn/image.jpg');
      final audio = StoryBlock.audio('audio-1', 'https://cdn/story.m4a');

      expect(image.copy().url, 'https://cdn/image.jpg');
      expect(image.copy().type, 'image');
      expect(audio.copy().url, 'https://cdn/story.m4a');
      expect(audio.copy().type, 'audio');
      expect(image.content, isEmpty);
      expect(audio.nodeKey, isEmpty);
    });

    test('★★ 已有媒体块物化时保留类型/URL，description 仍只投影文字', () {
      final c = chapter()
        ..blocks = <StoryBlock>[
          StoryBlock.text('text', '开头'),
          StoryBlock.image('image', ' https://cdn/image.jpg '),
          StoryBlock.audio('audio', ' https://cdn/story.m4a '),
          StoryBlock.node('node', 'n1'),
        ];

      materializeChapter(c, newKey);

      expect(c.blocks!.map((StoryBlock block) => block.type), <String>[
        'text',
        'image',
        'audio',
        'node',
      ]);
      expect(c.blocks![1].url, 'https://cdn/image.jpg');
      expect(c.blocks![2].url, 'https://cdn/story.m4a');
      expect(c.description, '开头');

      c.blocks![1] = StoryBlock.image('bad', '  ');
      expect(() => materializeChapter(c, newKey), throwsStateError);
    });

    test('★★ 先拿到 URL 才能插媒体，类型/空地址不合法必须红', () {
      final c = chapter();
      materializeChapter(c, newKey);
      final imageResult = applyStoryCommand(
        c,
        InsertMediaAtCommand(
          index: 1,
          blockKey: 'image-block',
          mediaType: StoryMediaType.image,
          url: ' https://cdn/image.jpg ',
        ),
      );
      expect(imageResult.chapter.blocks![1].type, 'image');
      expect(imageResult.chapter.blocks![1].url, 'https://cdn/image.jpg');
      expect(c.blocks!.length, 2, reason: '命令必须深拷贝，不能先往原草稿塞空壳');

      expect(
        () => applyStoryCommand(
          c,
          const InsertMediaAtCommand(
            index: 1,
            blockKey: 'empty-media',
            mediaType: StoryMediaType.audio,
            url: '  ',
          ),
        ),
        throwsStateError,
      );
    });

    test('★ 删除媒体只认 image/audio，不会误删同 key 其他块', () {
      final c = chapter();
      materializeChapter(c, newKey);
      final inserted = applyStoryCommand(
        c,
        const InsertMediaAtCommand(
          index: 1,
          blockKey: 'media',
          mediaType: StoryMediaType.audio,
          url: 'https://cdn/story.aac',
        ),
      );
      final removed = applyStoryCommand(
        inserted.chapter,
        const RemoveMediaCommand(blockKey: 'media'),
      );
      expect(removed.chapter.blocks!.any((b) => b.key == 'media'), isFalse);
      expect(
        () => applyStoryCommand(
          c,
          RemoveMediaCommand(blockKey: c.blocks!.first.key),
        ),
        throwsStateError,
      );
    });

    test('★ 同一节点不能重复出现在故事流', () {
      final c = chapter();
      materializeChapter(c, newKey);
      expect(
        () => applyStoryCommand(
          c,
          InsertNodeAtCommand(
            index: c.blocks!.length,
            node: c.nodes.first,
            blockKey: newKey(),
          ),
        ),
        throwsStateError,
      );
    });

    test('删节点 → removed 快照供撤销', () {
      final c = chapter();
      materializeChapter(c, newKey);
      final nodeBlock = c.blocks!.firstWhere((b) => b.type == 'node');
      final r = applyStoryCommand(
        c,
        RemoveNodeCommand(blockKey: nodeBlock.key),
      );
      expect(r.removed, isNotNull);
      expect(r.removed!.node.localId, 'n1');
      expect(r.chapter.nodes, isEmpty);
      expect(r.chapter.blocks!.length, 1);
    });

    test('每章最多 200 个内容块', () {
      var c = PublishChapter()..blocks = <StoryBlock>[];
      for (var i = 0; i < 200; i++) {
        final r = applyStoryCommand(
          c,
          InsertTextAtCommand(index: c.blocks!.length, blockKey: 'b$i'),
        );
        // 更新引用继续加。
        c = r.chapter;
      }
      expect(
        () => applyStoryCommand(
          c,
          InsertTextAtCommand(index: 200, blockKey: 'overflow'),
        ),
        throwsStateError,
      );
    });

    test('toPayloadChapter:nodeIndex 映射 + 剥本地字段 + 描述投影', () {
      final c = chapter();
      materializeChapter(c, newKey);
      // 在节点前插一段文字,节点 index 仍是 0。
      final r = applyStoryCommand(
        c,
        InsertTextAtCommand(index: 0, blockKey: newKey()),
      );
      r.chapter.blocks![0].content = '第一段';
      final payload = toPayloadChapter(r.chapter);
      final blocks = payload['blocks'] as List<dynamic>;
      expect(blocks.length, 3);
      expect(blocks[0], <String, dynamic>{'type': 'text', 'content': '第一段'});
      expect(blocks[2], <String, dynamic>{'type': 'node', 'nodeIndex': 0});
      expect(payload['description'], '第一段\n开头');
      final nodes = payload['nodes'] as List<dynamic>;
      expect(
        (nodes.first as Map<String, dynamic>).containsKey('_localId'),
        isFalse,
      );
    });

    test('★★ 媒体 payload 只有 {type,url}，且不泄漏进 description', () {
      final c = chapter();
      materializeChapter(c, newKey);
      var current = applyStoryCommand(
        c,
        const InsertMediaAtCommand(
          index: 1,
          blockKey: 'image',
          mediaType: StoryMediaType.image,
          url: 'https://cdn/image.jpg',
        ),
      ).chapter;
      current = applyStoryCommand(
        current,
        const InsertMediaAtCommand(
          index: 2,
          blockKey: 'audio',
          mediaType: StoryMediaType.audio,
          url: 'https://cdn/story.mp3',
        ),
      ).chapter;

      expect(current.description, '开头');
      final payload = toPayloadChapter(current);
      final blocks = payload['blocks'] as List<dynamic>;
      expect(blocks[1], <String, dynamic>{
        'type': 'image',
        'url': 'https://cdn/image.jpg',
      });
      expect(blocks[2], <String, dynamic>{
        'type': 'audio',
        'url': 'https://cdn/story.mp3',
      });
      expect(payload['description'], '开头');
    });
  });

  group('buildPublishValidationBag', () {
    PublishDraft base() => PublishDraft()
      ..name = '静安微旅行'
      ..subtitle = '一句话'
      ..description = '完整介绍'
      ..startDate = '2026-09-01'
      ..endDate = '2026-09-02'
      ..imgUrl = 'https://img/c.jpg'
      ..categoryIds = <int>[1]
      ..chapters = <PublishChapter>[
        PublishChapter()
          ..description = '剧情'
          ..nodes = <PublishNode>[
            PublishNode()
              ..name = '节点'
              ..longitude = '121.4'
              ..latitude = '31.2',
          ],
      ]
      ..tickets = <PublishTicket>[
        PublishTicket()
          ..name = '城市定向票'
          ..mode = kProductCity
          ..meetingPoint = '静安寺'
          ..startTime = '2026-09-01 10:00:00'
          ..endTime = '2026-09-01 12:00:00',
      ];

    test('全填满 → 有效', () {
      expect(buildPublishValidationBag(base()).isValid(), isTrue);
    });

    test('★ 票价 null(没填)拦;0(免费票)放行 —— 两种含义不能合并', () {
      final noPrice = base()..tickets.first.price = null;
      final bag = buildPublishValidationBag(noPrice);
      expect(bag.isValid(), isFalse);
      expect(bag.errors['ticketPrice0'], '请填写票价');

      final free = base()..tickets.first.price = 0;
      expect(
        buildPublishValidationBag(free).isValid(),
        isTrue,
        reason: '0 = 明确的免费票,不是没填',
      );
    });

    test('负价拦', () {
      final d = base()..tickets.first.price = -1;
      final bag = buildPublishValidationBag(d);
      expect(bag.errors['ticketPrice0'], '价格不能为负数');
    });

    test('节点没坐标拦,且定位到章', () {
      final d = base();
      d.chapters.first.nodes.first
        ..longitude = ''
        ..latitude = '';
      final bag = buildPublishValidationBag(d);
      expect(bag.isValid(), isFalse);
      expect(bag.errors['chapter0'], '第1章第1个节点还没有选地点');
    });

    test('★ 自由探索缺招商截止拦', () {
      final d = base()
        ..productType = kProductFreeExplore
        ..recruitDeadline = null;
      d.tickets.first.mode = kProductFreeExplore;
      final bag = buildPublishValidationBag(d);
      expect(bag.isValid(), isFalse);
      expect(bag.errors['recruitDeadline'], '请选择招商截止日期');
    });
  });

  group('buildTopicPayload', () {
    PublishDraft full() => PublishDraft()
      ..name = '静安微旅行'
      ..subtitle = '一句话'
      ..description = '完整介绍'
      ..startDate = '2026-09-01'
      ..endDate = '2026-09-02'
      ..imgUrl = 'https://img/c.jpg'
      ..imgArr = 'https://img/h1.jpg'
      ..categoryIds = <int>[1, 2]
      ..productType = kProductCity
      ..tickets = <PublishTicket>[
        PublishTicket()
          ..name = '早鸟票'
          ..price = 39
          ..mode = kProductFreeExplore
          ..meetingPoint = '静安寺'
          ..teamSize = 4
          ..startTime = '2026-09-01 10:00'
          ..endTime = '2026-09-01 12:00',
      ];

    test('票的 mode 一律覆盖为主题级 productType(混票会被后端拒)', () {
      final payload = buildTopicPayload(full());
      final tickets = payload['tickets'] as List<dynamic>;
      expect((tickets.first as Map<String, dynamic>)['mode'], kProductCity);
    });

    test('openClubPool 恒 0;openMerchantPool 归一 0/1', () {
      final payload = buildTopicPayload(full());
      expect(payload['openClubPool'], 0);
      expect(payload['openMerchantPool'], 0);
    });

    test('日期归一化带时间', () {
      final payload = buildTopicPayload(full());
      expect(payload['startDate'], '2026-09-01 00:00:00');
      expect(payload['endDate'], '2026-09-02 23:59:59');
    });

    test('★ 自由探索才上送 recruitDeadline', () {
      final explore = full()..productType = kProductFreeExplore;
      explore.recruitDeadline = '2026-08-30';
      final payload = buildTopicPayload(explore);
      expect(payload['recruitDeadline'], '2026-08-30 23:59:59');
      final city = buildTopicPayload(full());
      expect(city.containsKey('recruitDeadline'), isFalse);
    });

    test('WHITELIST 档只剩文案与图', () {
      final payload = buildTopicPayload(full());
      final slim = whitelistPayload(payload);
      // scope 例外:真源 WHITELIST 裁剪后仍带 scope(fabu submitForm),
      // 不然商家档编辑会被当成玩家请求。
      expect(slim.keys.toSet(), <String>{
        'name',
        'subtitle',
        'description',
        'imgUrl',
        'imgArr',
        'categoryIds',
        'scope',
      });
      expect(slim.containsKey('tickets'), isFalse);
      expect(slim.containsKey('startDate'), isFalse);
    });
  });

  group('buildPublishCheck', () {
    test('软建议不阻断:未配玩法/缺描述进 advisory', () {
      final d = PublishDraft()
        ..name = 'n'
        ..subtitle = 's'
        ..description = 'd'
        ..startDate = '2026-09-01'
        ..endDate = '2026-09-02'
        ..imgUrl = 'x'
        ..categoryIds = <int>[1]
        ..chapters = <PublishChapter>[
          PublishChapter()
            ..description = '剧情'
            ..nodes = <PublishNode>[
              PublishNode()
                ..name = 'n1'
                ..longitude = '121.4'
                ..latitude = '31.2',
            ],
        ]
        ..tickets = <PublishTicket>[
          PublishTicket()
            ..name = '票'
            ..mode = kProductCity
            ..meetingPoint = '静安寺'
            ..startTime = '2026-09-01 10:00:00'
            ..endTime = '2026-09-01 12:00:00',
        ];
      final check = buildPublishCheck(d);
      expect(check.blocking, isEmpty);
      expect(check.advisory.any((i) => i.label.contains('未配置玩法')), isTrue);
      expect(check.advisory.any((i) => i.label.contains('缺描述')), isTrue);
    });
  });
}

/// 2026-09-09 与小程序 fabu 页对齐的章节音频 / 章节配色 / 空音频块。
/// 口径真源:小程序 utils/chapter-atmosphere.js 与 utils/publish/pro-editor-story.js,
/// 两端改一边就要改另一边,否则同一条章节在两端显示成两个颜色。
void _parity() {
  group('章节配色归一', () {
    test('五档规范值原样通过', () {
      for (final a in kChapterAtmospheres) {
        expect(normalizeAtmosphere(a.value), a.value);
      }
    });

    test('★ 存量别名不能读废 —— 库里还存着 NIGHT/ARCHIVE/NEON/MOSS', () {
      expect(normalizeAtmosphere('NIGHT'), 'BLUE');
      expect(normalizeAtmosphere('ARCHIVE'), 'YELLOW');
      expect(normalizeAtmosphere('NEON'), 'RED');
      // 新色板里没有绿,苔野落回默认黑。
      expect(normalizeAtmosphere('MOSS'), 'DEFAULT');
    });

    test('★ 脏值与空值一律落回 DEFAULT,不原样透传到界面', () {
      expect(normalizeAtmosphere(null), 'DEFAULT');
      expect(normalizeAtmosphere(''), 'DEFAULT');
      expect(normalizeAtmosphere('  blue '), 'BLUE');
      expect(normalizeAtmosphere('PURPLE'), 'DEFAULT');
    });

    test('★ 白档是唯一浅色 —— 卡内文字要翻黑,靠的是这个色值', () {
      final white = kChapterAtmospheres.firstWhere((a) => a.value == 'WHITE');
      expect(white.color, 0xFFF5F6F8);
    });
  });

  group('章节音频与空音频块', () {
    PublishChapter chapter() => PublishChapter()
      ..name = '第一章'
      ..description = '开头';

    test('章节音频与配色跟着 payload 一起上送', () {
      final c = chapter()
        ..audioUrl = 'https://cdn/chapter.mp3'
        ..atmospherePreset = 'NEON';
      materializeChapter(c, () => 'k1');
      final payload = toPayloadChapter(c);
      expect(payload['audioUrl'], 'https://cdn/chapter.mp3');
      // 上送前归一:别名不能原样落库。
      expect(payload['atmospherePreset'], 'RED');
    });

    test('★ 没有章节音频时不上送空字段', () {
      final c = chapter();
      materializeChapter(c, () => 'k1');
      expect(toPayloadChapter(c).containsKey('audioUrl'), isFalse);
    });

    // App 侧是「先选文件再插块」,所以插入这一步空地址一律当场拒 ——
    // 编辑器里根本不会留下空块。下面这条挡的是另一条来路:早期小程序存过
    // url 为空的音频块,编辑既有主题时会把它读回来,不能原样再送回去。
    test('★ 插入媒体块时空地址当场被拒(图片与音频同一口径)', () {
      for (final StoryMediaType type in StoryMediaType.values) {
        final c = chapter();
        materializeChapter(c, () => 'k1');
        expect(
          () => applyStoryCommand(
            c,
            InsertMediaAtCommand(
              index: 0,
              blockKey: 'm1',
              mediaType: type,
              url: '  ',
            ),
          ),
          throwsStateError,
          reason: '放行空 url = 落一个点不开的空壳块',
        );
      }
    });

    test('★ 读回来的空音频块不再上送 —— 玩家端会读到一个不响的音频', () {
      final c = chapter();
      materializeChapter(c, () => 'k1');
      c.blocks!.add(StoryBlock.audio('a1', ''));
      final blocks = toPayloadChapter(c)['blocks'] as List<dynamic>;
      expect(blocks.where((b) => (b as Map)['type'] == 'audio'), isEmpty);
      expect(
        blocks.any((b) => (b as Map)['type'] == 'text'),
        isTrue,
        reason: '把别的块也一起过滤掉了',
      );
    });

    test('★负控:有地址的音频块照常上送', () {
      final c = chapter();
      materializeChapter(c, () => 'k1');
      c.blocks!.add(StoryBlock.audio('a1', 'https://cdn/x.mp3'));
      final blocks = toPayloadChapter(c)['blocks'] as List<dynamic>;
      expect(blocks.last, <String, dynamic>{
        'type': 'audio',
        'url': 'https://cdn/x.mp3',
      });
    });
  });
}

/// 2026-09-09 章节招商字段往返。
///
/// 后端更新章节是「整章删掉重建 + copyProperties」,载荷里少一个字段那一列就写 NULL。
/// 而这些字段 App 只读不写(没有界面),所以唯一的正确行为是**读回来什么就送回去什么**。
void _chapterCarryOverParity() {
  PublishChapter recruitChapter() => PublishChapter()
    ..localId = 'c1'
    ..name = '第一章'
    ..imgArr = 'https://cdn/ch.jpg'
    ..audioUrl = 'https://cdn/ch.mp3'
    ..atmospherePreset = 'NEON'
    ..recruitEnabled = 1
    ..categoryId = 7
    ..maxMerchant = 3
    ..perkMinValue = '50'
    ..termsMode = 'PERK'
    ..category = '餐饮'
    ..allowedValidationMethods = '1,3'
    ..maxNodeXp = 40
    ..calculatedDistance = 3.2
    ..nodes.add(
      PublishNode()
        ..localId = 'n1'
        ..name = '节点'
        ..longitude = '121.4'
        ..latitude = '31.2'
        ..sortID = 1,
    );

  PublishDraft draftOf(int productType, PublishChapter c) => PublishDraft()
    ..name = '测试'
    ..productType = productType
    ..recruitDeadline = '2026-12-01'
    ..chapters.add(c);

  Map<String, dynamic> firstChapter(Map<String, dynamic> payload) =>
      (payload['chapters'] as List<dynamic>).first as Map<String, dynamic>;

  group('章节招商/音频/配色必须原样往返', () {
    // 章节招商只有自由探索有,走的正是直排分支 —— 这一档漏字段就是线上那个 bug。
    test('★★ 自由探索(直排分支):品类/名额/门槛/开关/档位一个都不能少', () {
      final Map<String, dynamic> ch = firstChapter(
        buildTopicPayload(draftOf(kProductFreeExplore, recruitChapter())),
      );
      expect(ch['recruitEnabled'], 1);
      expect(ch['termsMode'], 'PERK');
      expect(
        ch['categoryId'],
        7,
        reason:
            '招商开着却不带品类 ⇒ 后端 assertChapterShape 当场拒整次保存，'
            '而 App 里没有品类选择器,用户修不了',
      );
      expect(ch['maxMerchant'], 3, reason: '名额被清空 = 招商名额静默变成不限/无效');
      expect(ch['perkMinValue'], '50', reason: '权益门槛被清空 = 商家白捡');
      expect(ch['category'], '餐饮', reason: '品类名和品类 ID 是同一列的两半,得一起走');
    });

    test('★★ App 没有界面的那几个也必须往返 —— 没界面不等于可以清空', () {
      for (final int productType in <int>[kProductFreeExplore, kProductCity]) {
        final PublishChapter c = recruitChapter();
        if (productType == kProductCity) materializeChapter(c, () => 'k1');
        final Map<String, dynamic> ch = firstChapter(
          buildTopicPayload(draftOf(productType, c)),
        );
        expect(
          ch['allowedValidationMethods'],
          '1,3',
          reason:
              '玩法边界是承接合同的一部分：被清空后商家侧 assertWithinTerms '
              '拿它比对会恒不命中，商家怎么配都被拒，且没人看得出为什么',
        );
        expect(ch['maxNodeXp'], 40, reason: '$productType 档丢了单节点探索值上限');
        expect(ch['calculatedDistance'], 3.2, reason: '$productType 档丢了章节里程');
      }
    });

    test('★★ 城市定向(块化分支)带同一组字段 —— 两条分支不许再各漂一份', () {
      final PublishChapter c = recruitChapter();
      materializeChapter(c, () => 'k1');
      final Map<String, dynamic> ch = firstChapter(
        buildTopicPayload(draftOf(kProductCity, c)),
      );
      expect(ch['categoryId'], 7);
      expect(ch['maxMerchant'], 3);
      expect(ch['perkMinValue'], '50');
    });

    test('★ 章节音频与配色在两条分支上都要送(音频两档都能配,不是只有城市定向)', () {
      for (final int productType in <int>[kProductFreeExplore, kProductCity]) {
        final PublishChapter c = recruitChapter();
        if (productType == kProductCity) materializeChapter(c, () => 'k1');
        final Map<String, dynamic> ch = firstChapter(
          buildTopicPayload(draftOf(productType, c)),
        );
        expect(
          ch['audioUrl'],
          'https://cdn/ch.mp3',
          reason: '$productType 档丢了章节音频',
        );
        // 上送前归一:存量别名不能原样落库。
        expect(ch['atmospherePreset'], 'RED', reason: '$productType 档丢了章节配色');
        expect(
          ch['imgArr'],
          'https://cdn/ch.jpg',
          reason: '$productType 档丢了章节封面',
        );
      }
    });

    test('★负控:没有值的字段不许凭空造一个 —— 空 ≠ 0', () {
      final PublishChapter c = PublishChapter()
        ..localId = 'c1'
        ..name = '第一章'
        ..nodes.add(
          PublishNode()
            ..localId = 'n1'
            ..name = '节点'
            ..longitude = '121.4'
            ..latitude = '31.2'
            ..sortID = 1,
        );
      final Map<String, dynamic> ch = firstChapter(
        buildTopicPayload(draftOf(kProductFreeExplore, c)),
      );
      expect(ch.containsKey('categoryId'), isFalse);
      expect(
        ch.containsKey('maxMerchant'),
        isFalse,
        reason: '兜一个 0 会把「没配过名额」写成「名额 0」,含义完全不同',
      );
      expect(ch.containsKey('perkMinValue'), isFalse);
      expect(ch.containsKey('audioUrl'), isFalse);
      expect(ch.containsKey('imgArr'), isFalse);
    });
  });

  group('发布同步广场默认值(gap-spec-player #6)', () {
    test('新建草稿 publishToCreative 默认 true —— 真源 fabu/index.js:128 data 默认开', () {
      expect(PublishDraft().publishToCreative, isTrue);
      expect(buildTopicPayload(PublishDraft())['publishToCreative'], 1);
    });
  });
}
