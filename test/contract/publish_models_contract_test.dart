import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';

/// 提交载荷字段契约:map 的 key 必须与后端 DTO 字段名逐一对齐。
///
/// ★ 后端 TopicCreateDTO / ChapterDTO / NodeDTO / ActivityTicketRequest /
///   ChapterBlockDTO 的字段名是硬契约 —— key 打错一个字,后端静默丢字段
///   (发布接口不报错),功能就无声无息地少一半。这份测试锁的是「key 名」,
///   不是实现细节。
void main() {
  PublishDraft full() => PublishDraft()
    ..name = 'n'
    ..subtitle = 's'
    ..description = 'd'
    ..startDate = '2026-09-01'
    ..endDate = '2026-09-02'
    ..imgUrl = 'c.jpg'
    ..imgArr = 'h1.jpg,h2.jpg'
    ..categoryIds = <int>[1]
    ..productType = kProductFreeExplore
    ..recruitDeadline = '2026-08-30'
    ..clubId = 5
    ..collaboratorIds = <int>[1, 2]
    ..selfPlay = true
    ..selfPlayPrice = '19.9'
    ..selfPlayQuota = '50'
    ..openMerchantPool = true
    ..publishToCreative = true
    ..tickets = <PublishTicket>[
      PublishTicket()
        ..name = '自由探索票'
        ..price = 19.9
        ..totalStock = 100
        ..mode = kProductFreeExplore
        ..meetingPoint = '静安寺'
        ..meetingPointLongitude = '121.44'
        ..meetingPointLatitude = '31.22'
        ..teamSize = 4
        ..startTime = '2026-09-01 10:00'
        ..endTime = '2026-09-02 22:00'
        ..saleStartTime = '2026-08-01'
        ..saleEndTime = '2026-08-31'
        ..description = '穿运动鞋',
    ]
    ..finishMedalName = '通关'
    ..finishMedalImg = 'm.jpg'
    ..completeRewardCouponId = 9
    ..chapters = <PublishChapter>[
      PublishChapter()
        ..name = '第一章'
        ..description = '剧情'
        ..nodes = <PublishNode>[
          PublishNode()
            ..name = '节点'
            ..description = '说明'
            ..address = '地址'
            ..longitude = '121.4'
            ..latitude = '31.2'
            ..imgUrl = 'n.jpg'
            ..templateId = 7
            ..sortID = 1
            ..nodeTime = 30,
        ],
    ];

  test('顶层 key 对齐 TopicCreateDTO', () {
    final p = buildTopicPayload(full());
    // 后端 TopicCreateDTO 字段名。
    expect(
      p.keys.toSet(),
      containsAll(<String>[
        'name',
        'subtitle',
        'description',
        'startDate',
        'endDate',
        'imgUrl',
        'imgArr',
        'categoryIds',
        'chapters',
        'collaboratorIds',
        'tickets',
        'productType',
        'openMerchantPool',
        'openClubPool',
        'recruitDeadline',
        'publishToCreative',
        'clubId',
        'audioUrl',
        'audioDuration',
        'selfPlay',
        'selfPlayPrice',
        'selfPlayQuota',
        'finishMedalName',
        'finishMedalImg',
        'completeRewardCouponId',
        'publishMode',
      ]),
    );
  });

  test('票 key 对齐 ActivityTicketRequest', () {
    final p = buildTopicPayload(full());
    final ticket =
        (p['tickets'] as List<dynamic>).first as Map<String, dynamic>;
    expect(
      ticket.keys.toSet(),
      containsAll(<String>[
        'name',
        'price',
        'mode',
        'startTime',
        'endTime',
        'totalStock',
        'description',
        'meetingPoint',
        'teamSize',
        'gatherLng',
        'gatherLat',
      ]),
    );
  });

  test('章节/节点/故事块 key 对齐 ChapterDTO / NodeDTO / ChapterBlockDTO', () {
    final d = full()..productType = kProductCity;
    // 城市定向:章节经故事流物化后走 toPayloadChapter。
    final chapter = d.chapters.first;
    materializeChapter(chapter, () => 'k1');
    chapter.blocks!.insertAll(1, <StoryBlock>[
      StoryBlock.image('image', 'https://cdn/image.jpg'),
      StoryBlock.audio('audio', 'https://cdn/story.m4a'),
    ]);
    final p = toPayloadChapter(chapter);
    expect(
      p.keys.toSet(),
      containsAll(<String>[
        'name',
        'description',
        'nodes',
        'blocks',
        'schemaVersion',
        'required',
        'recruitEnabled',
        'termsMode',
      ]),
    );
    final node = (p['nodes'] as List<dynamic>).first as Map<String, dynamic>;
    expect(
      node.keys.toSet(),
      containsAll(<String>[
        'name',
        'description',
        'address',
        'longitude',
        'latitude',
        'imgUrl',
        'templateId',
        'sortID',
        'nodeTime',
      ]),
    );
    final blocks = p['blocks'] as List<dynamic>;
    expect(blocks[1], <String, dynamic>{
      'type': 'image',
      'url': 'https://cdn/image.jpg',
    });
    expect(blocks[2], <String, dynamic>{
      'type': 'audio',
      'url': 'https://cdn/story.m4a',
    });
    final nodeBlock = blocks.last as Map<String, dynamic>;
    expect(nodeBlock['type'], 'node');
    expect(
      nodeBlock.containsKey('nodeIndex'),
      isTrue,
      reason: 'ChapterBlockDTO 文字用 content、媒体用 url、节点用 nodeIndex',
    );
  });

  test('★ 票的 mode 必须 == 主题 productType(混票会被后端拒)', () {
    final p = buildTopicPayload(full());
    final productType = p['productType'] as int;
    for (final t in p['tickets'] as List<dynamic>) {
      expect((t as Map<String, dynamic>)['mode'], productType);
    }
  });

  // 盘点 1369/1357:a1 线接上 ?scope=MERCHANT —— 真源 _doSubmit 恒带
  // `scope: operationScope`,缺了商家发布记到个人名下。
  test('★ scope 随 create/update 载荷上送;玩家入口为空串(真源同款)', () {
    expect(buildTopicPayload(full())['scope'], '');
    expect(buildTopicPayload(full(), scope: 'MERCHANT')['scope'], 'MERCHANT');
    // WHITELIST 裁剪档也必须留住 scope(真源裁剪后的 apiData 带 scope)。
    expect(
      whitelistPayload(buildTopicPayload(full(), scope: 'MERCHANT'))['scope'],
      'MERCHANT',
    );
    // 模型默认口径仍不带上送键。
    final p = buildTopicPayload(full());
    expect(p.containsKey('clubId'), isTrue, reason: 'full() 有 clubId');
  });
}
