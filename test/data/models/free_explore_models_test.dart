import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';

void main() {
  test('自由探索四个新字段按后端形状解析', () {
    final r = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7,
      'mode': 2,
      'topicDesc': '一个慢下来的下午',
      'selfPlay': true,
      'expiresAt': '2026-09-15 23:59:59',
      'total': 1,
      'doneCount': 0,
      'chapters': <dynamic>[
        <String, dynamic>{'chapterId': 100, 'name': '旧书与唱片', 'description': '午后两点'},
      ],
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': 1, 'name': '长乐路旧物店', 'address': '长乐路 139 号', 'sortId': 1,
          'chapterId': 100, 'businessTime': '12:00-21:00',
          'hookText': '你得先说出一个年份。',
          'npc': <String, dynamic>{'name': '阿旧', 'greeting': '你要找哪一年的?'},
          'perk': <String, dynamic>{'name': '到店赠明信片', 'redeemRule': '到店出示核销', 'validEnd': '2026-09-15 23:59:59'},
        },
      ],
    });

    expect(r.topicDesc, '一个慢下来的下午');
    expect(r.selfPlay, isTrue);
    expect(r.expiresAt, '2026-09-15 23:59:59');
    expect(r.chapters.single.title, '旧书与唱片');

    final n = r.nodes.single;
    expect(n.chapterId, 100);
    expect(n.businessTime, '12:00-21:00');
    expect(n.hookText, '你得先说出一个年份。');
    expect(n.npc!.name, '阿旧');
    expect(n.perk!.name, '到店赠明信片');
  });

  test('★负控:字段缺失一律为 null,不许猜默认值', () {
    final r = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7, 'mode': 1, 'total': 1, 'doneCount': 0,
      'nodes': <dynamic>[<String, dynamic>{'nodeId': 1, 'name': 'x', 'address': '', 'sortId': 1}],
    });
    expect(r.topicDesc, isNull);
    expect(r.expiresAt, isNull);
    expect(r.selfPlay, isFalse);
    expect(r.chapters, isEmpty);

    final n = r.nodes.single;
    expect(n.hookText, isNull);
    expect(n.chapterId, isNull);
    expect(n.npc, isNull, reason: '没有 npc 就不该造一个空壳,否则店铺卡会渲染出无名分身');
    expect(n.perk, isNull, reason: '没有 perk 就不该渲染「本店权益」整段');
  });

  // ★ 后端 /api/play/nodes 下发的章节键是 name / imgArr / audioUrl,**没有**
  //   meta / title / cover。之前按后三个名字解析,生产里三个恒 null,章节眉标、
  //   卡背标题、收缩顶栏眉标全部静默消失,而 fixture 用构造函数直接造对象、
  //   绕过了解析层,一条测试都没红。这条就钉解析层本身。
  //   负控:把 fromJson 改回读 j['meta']/j['title']/j['cover'],本条必红。
  test('★章节按后端真实键规范化:title←name / meta←下标 / cover←imgArr 首图', () {
    final r = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7, 'mode': 2, 'total': 2, 'doneCount': 0,
      'chapters': <dynamic>[
        <String, dynamic>{
          'chapterId': 100, 'name': '晨间烘焙', 'description': '面包出炉的时间',
          'imgArr': 'https://img/a.jpg,https://img/b.jpg',
          'audioUrl': 'https://cdn/ch100.mp3',
        },
        <String, dynamic>{'chapterId': 200, 'description': '午后两点'},
      ],
    });

    final PlayChapter first = r.chapters.first;
    expect(first.chapterId, 100);
    expect(first.meta, '第 1 章', reason: '后端不发 meta/idxLabel,眉标按数组下标生成');
    expect(first.title, '晨间烘焙', reason: '后端下发的键是 name,不是 title');
    expect(first.description, '面包出炉的时间');
    expect(first.cover, 'https://img/a.jpg', reason: '封面取 imgArr 逗号拆首图,后端不发 cover');
    expect(first.audioUrl, 'https://cdn/ch100.mp3');

    final PlayChapter second = r.chapters.last;
    expect(second.meta, '第 2 章', reason: '序号跟着数组下标走,不是跟着 chapterId');
    expect(second.title, '第 2 章', reason: '没 name 回落序号,照小程序 buildChapterCards');
    expect(second.cover, isNull, reason: '没 imgArr 就没封面,不许造一个空串当图源');
    expect(second.audioUrl, isNull);
  });

  test('★负控:name 为空串一律为 null,没名字的分身/权益等于没有', () {
    expect(PlayNpcBrief.fromJson(<String, dynamic>{'name': '', 'greeting': 'x'}), isNull);
    expect(PlayPerk.fromJson(<String, dynamic>{'name': ''}), isNull);
  });
}
