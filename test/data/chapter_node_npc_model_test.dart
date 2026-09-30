// 点位角色 + 门店声音状态两个模型。
//
// ★ 这两个模型存在的唯一理由是把**状态说准**:
//   · "没配过"和"没读到"必须分得开(前者是 0,后者是 null);
//   · 未知状态码不许猜 —— 猜错会把"上次生成失败"说成"已就绪"。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/chapter_node_npc.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';

void main() {
  group('点位角色:配没配过', () {
    test('★ 判据是 avatar,不是 name —— 小程序同判据(!!avatar)', () {
      expect(const ChapterNodeNpc(name: '阿福').configured, isFalse);
      expect(const ChapterNodeNpc(avatar: 'https://x/a.png').configured, isTrue);
      expect(
        const ChapterNodeNpc(avatar: '   ').configured,
        isFalse,
        reason: '全空格等于没配',
      );
    });

    test('★ 后端回 data:null 时解析成空角色,不是异常', () {
      const ChapterNodeNpc n = ChapterNodeNpc.empty;
      expect(n.configured, isFalse);
      expect(n.name, '');
      expect(n.voiceStatus, isNull);
    });
  });

  group('点位角色:声音四态', () {
    String label(int? s) => ChapterNodeNpc(voiceStatus: s).voiceLabel;

    test('0/1/2/3 逐字对齐小程序', () {
      expect(label(0), '未配置(可选)');
      expect(label(1), '声音生成中…(稍后自动刷新)');
      expect(label(2), '声音已就绪');
      expect(label(3), '上次生成失败,可以重新生成');
    });

    test('★ 未知码不猜:说"状态未知",别把失败说成已就绪', () {
      expect(label(9), '声音状态未知');
      expect(
        label(null),
        '声音状态未知',
        reason: '读不到 ≠ 未配置;兜成 0 会让商家以为从没录过',
      );
      expect(ChapterNodeNpc(voiceStatus: 9).isVoiceReady, isFalse);
    });

    test('★ voiceStatus 是字符串也认(后端有时带引号)', () {
      expect(
        ChapterNodeNpc.fromJson(<String, dynamic>{'voiceStatus': '2'}).voiceStatus,
        2,
      );
      expect(
        ChapterNodeNpc.fromJson(<String, dynamic>{}).voiceStatus,
        isNull,
        reason: '缺席要留 null,不能兜成 0',
      );
    });
  });

  group('点位角色:保存闸', () {
    test('★★ 名字必填 —— 与小程序同判据、同一句文案', () {
      expect(
        const ChapterNodeNpc(avatar: 'a.png').saveBlocker,
        '请填写角色名字',
      );
      expect(
        const ChapterNodeNpc(name: '   ', avatar: 'a.png').saveBlocker,
        '请填写角色名字',
      );
    });

    test('★ 形象也要有 —— 后端 _resolveAvatar 会直接拒', () {
      expect(
        const ChapterNodeNpc(name: '阿福').saveBlocker,
        '请先选一张形象照片',
      );
    });

    test('都齐了才放行', () {
      expect(
        const ChapterNodeNpc(name: '阿福', avatar: 'a.png').saveBlocker,
        isNull,
      );
    });
  });

  group('门店声音状态', () {
    test('四态文案与点位侧一致', () {
      String label(int s) => NpcVoiceStatus(voiceStatus: s).label;
      expect(label(0), '未配置(可选)');
      expect(label(1), '声音生成中…(稍后自动刷新)');
      expect(label(2), '声音已就绪');
      expect(label(3), '上次生成失败,可以重新生成');
      expect(label(7), '声音状态未知');
    });

    test('★ 空白录音地址等于没有地址', () {
      expect(
        NpcVoiceStatus.fromJson(<String, dynamic>{
          'voiceStatus': 2,
          'voiceSample': '  ',
        }).voiceSample,
        isNull,
      );
      expect(
        NpcVoiceStatus.fromJson(<String, dynamic>{
          'voiceStatus': 2,
          'voiceSample': ' https://x/v.mp3 ',
        }).voiceSample,
        'https://x/v.mp3',
      );
    });

    test('★ 缺 voiceStatus 时兜 0(未配置)—— 这条查询答的是"要不要显示进度"', () {
      expect(NpcVoiceStatus.fromJson(<String, dynamic>{}).voiceStatus, 0);
    });
  });
}
