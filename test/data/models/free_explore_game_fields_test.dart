import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';

void main() {
  test('有玩法时七个字段都解析出来(duration 按后端真实形状:数字)', () {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': 'x', 'address': '', 'sortId': 1,
      // ★ CmsMemberTemplate.duration 是 Long,`m.put("duration", tpl.getDuration())`
      //   直发数字。喂 '15 分钟' 是自造形状,会把类型错配盖住。
      'hasGame': true, 'gameTitle': '找一本 1998', 'duration': 15,
      'difficulty': '轻松', 'players': '1–2 人', 'requiredMaterials': '一张纸巾',
      'ruleInstructions': '进店对老板说出一个年份\n翻到扉页',
    });
    expect(n.hasGame, isTrue);
    expect(n.gameTitle, '找一本 1998');
    expect(n.duration, 15, reason: '模型存分钟数本身,单位由展示层拼');
    expect(n.players, '1–2 人');
    expect(n.requiredMaterials, '一张纸巾');
    expect(n.ruleInstructions, contains('年份'));
  });

  test('★duration 缺失或解析不出来是 null,不落回 0(「0 分钟」是编出来的)', () {
    PlayNode of(Object? v) => PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'duration': v,
    });
    expect(of(null).duration, isNull);
    expect(of('').duration, isNull);
    expect(of('随便').duration, isNull);
    expect(of('20').duration, 20, reason: '真发字符串数字也要收得下');
  });

  test('★节点的语音导览:屏③ 音频键的音源(后端 :594 tpl.getAudioUrl)', () {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'audioUrl': 'https://cdn.example.com/node-1.mp3',
    });
    expect(n.audioUrl, 'https://cdn.example.com/node-1.mp3');
  });

  test('★负控:audioUrl 缺失 / 空串都是 null —— 渲一颗按不出声的键就是假入口', () {
    PlayNode of(Map<String, dynamic> extra) =>
        PlayNode.fromJson(<String, dynamic>{
          'nodeId': 1,
          'name': 'x',
          'address': '',
          'sortId': 1,
          ...extra,
        });
    // hasGame=false 时后端整条 removeAll 掉 audioUrl(:682-687),端上就是收不到。
    expect(of(<String, dynamic>{'hasGame': false}).audioUrl, isNull);
    expect(of(<String, dynamic>{'audioUrl': ''}).audioUrl, isNull);
    expect(of(<String, dynamic>{'audioUrl': '   '}).audioUrl, isNull);
  });

  test('★节点语音导览与章节背景旁白是两条,不许互相顶替', () {
    // 后端 :594 发在 node 上、:736 发在 chapter 上,同名不同物。
    final r = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 1,
      'mode': 2,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': 7,
          'name': 'x',
          'address': '',
          'sortId': 1,
          'chapterId': 100,
          'hasGame': true,
          'audioUrl': 'https://cdn.example.com/node-7.mp3',
        },
      ],
      'chapters': <dynamic>[
        <String, dynamic>{
          'chapterId': 100,
          'name': '旧书与唱片',
          'audioUrl': 'https://cdn.example.com/chapter-narration.mp3',
        },
      ],
    });
    final n = r.nodes.single;
    expect(n.audioUrl, 'https://cdn.example.com/node-7.mp3');
    expect(
      r.chapterOf(n)!.audioUrl,
      'https://cdn.example.com/chapter-narration.mp3',
    );
    expect(
      n.audioUrl,
      isNot(r.chapterOf(n)!.audioUrl),
      reason: '两条同名不同物 —— 解析层就把它们混起来的话页面无从分辨',
    );
  });

  test('★负控:hasGame 缺失时为 false;gameTitle 单独缺失时也为 null', () {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
    });
    expect(n.hasGame, isFalse);
    expect(n.gameTitle, isNull);
    // 后端 !arrived 会单摘 gameTitle 却留下 hasGame=true,所以两者互相推不出来。
  });

  // 后端 ApiPlayProgressController:458-497 对到店态节点合法投影的字段。
  // 只接这七个;answerReveal / feedbackText 是防作弊 reveal / answer 动作结果,
  // fragmentText / cardHookLong 是模板创作器字段 —— 节点列表里没有,不许造。
  test('★叙事与到店态七个字段按后端节点接口解析', () {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'gameTitle': '猜年代小游戏',
      'arrived': true,
      'storyText': '店主收唱片二十年,最爱聊六七十年代的爵士。',
      'storyImg': 'https://cdn.example.com/story.jpg',
      'audioUrl': 'https://cdn.example.com/guide.mp3',
      'audioDuration': 42,
      'photoRequireDesc': '拍下唱片内页的年份',
      'unlockAfterNodeId': 11,
      'locked': true,
    });
    expect(n.storyText, '店主收唱片二十年,最爱聊六七十年代的爵士。');
    expect(n.storyImg, 'https://cdn.example.com/story.jpg');
    expect(n.audioUrl, 'https://cdn.example.com/guide.mp3');
    expect(n.audioDuration, 42, reason: '后端 audioDuration 是数字,单位由展示层决定');
    expect(n.photoRequireDesc, '拍下唱片内页的年份');
    expect(n.unlockAfterNodeId, 11);
    expect(n.locked, isTrue);
  });

  test('★负控:新增字段缺失一律 null / locked 默认 false,不猜默认值', () {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
    });
    expect(n.storyText, isNull);
    expect(n.storyImg, isNull);
    expect(n.audioUrl, isNull);
    expect(n.audioDuration, isNull, reason: '缺失不落回 0 —— 编出来的时长比不显示更糟');
    expect(n.photoRequireDesc, isNull);
    expect(n.unlockAfterNodeId, isNull);
    expect(n.locked, isFalse);
  });

  test('★负控:audioDuration 解析不出来是 null,数字字符串收得下', () {
    PlayNode of(Object? v) => PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'audioDuration': v,
    });
    expect(of(null).audioDuration, isNull);
    expect(of('').audioDuration, isNull);
    expect(of('随便').audioDuration, isNull);
    expect(of('30').audioDuration, 30, reason: '真发字符串数字也要收得下');
  });

  test('★负控:unlockAfterNodeId 非法值解析为 null,不伪造 0', () {
    PlayNode of(Object? v) => PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'unlockAfterNodeId': v,
    });
    expect(of(null).unlockAfterNodeId, isNull);
    expect(of('').unlockAfterNodeId, isNull);
    expect(of('随便').unlockAfterNodeId, isNull);
    expect(of('11').unlockAfterNodeId, 11, reason: '真发字符串数字也要收得下');
    expect(of(0).unlockAfterNodeId, 0, reason: '0 是合法整数;伪造只针对解析不出来的值');
  });

  test('★locked 容错语义:true / 1 / "true" / "1" 认作锁定,false / 0 / 缺失不锁', () {
    PlayNode of(Object? v) => PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'locked': v,
    });
    expect(of(true).locked, isTrue);
    expect(of(1).locked, isTrue);
    expect(of('true').locked, isTrue);
    expect(of('1').locked, isTrue);
    expect(of(false).locked, isFalse);
    expect(of(0).locked, isFalse);
    expect(of(null).locked, isFalse);
  });
}
