import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';

void main() {
  CoopInviteRow row(Map<String, dynamic> extra) => CoopInviteRow.fromJson(<String, dynamic>{
        'id': 1,
        'fromId': 10,
        'toType': 'merchant',
        'toId': 20,
        ...extra,
      });

  group('文案', () {
    test('类型文案三档 + 未知兜底', () {
      expect(row(<String, dynamic>{'inviteType': 0}).typeText, '主题发布者 → 商家');
      expect(row(<String, dynamic>{'inviteType': 1}).typeText, '商家 → 俱乐部');
      expect(row(<String, dynamic>{'inviteType': 2}).typeText, '商家 → 商家承接节点');
      expect(row(<String, dynamic>{'inviteType': 9}).typeText, '合作');
    });
    test('状态六态文案', () {
      final expected = <int, String>{
        0: '待确认',
        1: '已接受',
        2: '已拒绝',
        3: '已取消',
        4: '已顶替',
        5: '已过期',
      };
      expected.forEach((int s, String t) {
        expect(row(<String, dynamic>{'status': s}).statusText, t, reason: 'status=$s');
      });
    });
  });

  test('历史商家节点邀约(inviteType=2)只读', () {
    expect(row(<String, dynamic>{'inviteType': 2}).legacyReadonly, isTrue);
    expect(row(<String, dynamic>{'inviteType': 0}).legacyReadonly, isFalse);
  });

  group('★ 联系方式只拼后端实际下发的字段', () {
    test('未接受态:后端不下发 leaderName/phone → 只有名称', () {
      final r = row(<String, dynamic>{
        'partner': <String, dynamic>{'name': '某俱乐部'},
      });
      expect(r.partnerName, '某俱乐部');
      expect(r.partnerContact, '', reason: '没有联系方式就是空,不能编一个');
    });
    test('已接受态:后端下发了负责人+电话', () {
      final r = row(<String, dynamic>{
        'partner': <String, dynamic>{'name': 'X', 'leaderName': '张三', 'phone': '13800001111'},
      });
      expect(r.partnerContact, '张三 · 13800001111');
    });
  });

  group('条款文案', () {
    test('三种报酬模式', () {
      expect(row(<String, dynamic>{'shareMode': 0}).termsText, '引流型 · 无分成');
      expect(row(<String, dynamic>{'shareMode': 1, 'shareRate': 20}).termsText, '分成型 · 票款 20.0%');
      expect(row(<String, dynamic>{'shareMode': 2, 'fixedFee': 15}).termsText, '固定型 · ¥15.0 / 核销人头');
    });
    test('没有条款 → null,不是空字符串占位', () {
      expect(row(<String, dynamic>{}).termsText, isNull);
    });
  });

  test('★ 主题标题:后端没有 topicName 字段,恒用「主题 #id」兜底', () {
    expect(row(<String, dynamic>{'topicId': 88}).topicText, '主题 #88');
    expect(row(<String, dynamic>{}).topicText, '');
  });

  group('★ 详情页才用得上的几行(列表放不下,但两页同一份整形)', () {
    test('招募倒计时:只有待确认才算,已过截止说事实不显示负数', () {
      final DateTime now = DateTime(2026, 9, 17, 12);
      expect(
        row(<String, dynamic>{
          'status': 0,
          'expireTime': '2026-09-20 12:00:00',
        }).countdownText(now),
        '招募剩 3 天',
      );
      expect(
        row(<String, dynamic>{
          'status': 0,
          'expireTime': '2026-09-17 18:00:00',
        }).countdownText(now),
        '招募剩 6 小时',
      );
      expect(
        row(<String, dynamic>{
          'status': 0,
          'expireTime': '2026-09-17 10:00:00',
        }).countdownText(now),
        '已过招募截止',
      );
      // 已接受/终态不算倒计时 —— 那时它已经不是一个还在跑的招募。
      expect(
        row(<String, dynamic>{
          'status': 1,
          'expireTime': '2026-09-20 12:00:00',
        }).countdownText(now),
        '',
      );
      // 后端没下发截止时间就不显示,不编一个。
      expect(row(<String, dynamic>{'status': 0}).countdownText(now), '');
    });

    test('保证金金额:后端没下发就不编一个数字出来', () {
      expect(
        row(<String, dynamic>{'depositOwed': true, 'depositAmount': 50}).depositDueText,
        '锁价后待缴 ¥50 保证金',
      );
      expect(
        row(<String, dynamic>{'depositOwed': true, 'depositAmount': 50.5}).depositDueText,
        '锁价后待缴 ¥50.50 保证金',
      );
      // ★ 小程序这里是 `depositAmount || 50` —— 会把「不知道」显示成 50 元。
      expect(
        row(<String, dynamic>{'depositOwed': true}).depositDueText,
        '锁价后需缴保证金',
        reason: '金额没下发就是不知道,不能说成 ¥50',
      );
      expect(row(<String, dynamic>{'depositOwed': false}).depositDueText, '');
      expect(
        row(<String, dynamic>{
          'inviteType': 2,
          'depositOwed': true,
          'depositAmount': 50,
        }).depositDueText,
        '',
        reason: '历史商家节点邀约只读,不显示要交钱',
      );
    });

    test('席位占用:游戏级看挂起,主题级看已接受,拿不到不编 0/0', () {
      final Map<String, dynamic> slots = <String, dynamic>{
        'byGame': <String, dynamic>{
          '7': <String, dynamic>{'pending': 2, 'cap': 3},
        },
        'byTopic': <String, dynamic>{
          '88': <String, dynamic>{'accepted': 1, 'cap': 5},
        },
      };
      expect(
        row(<String, dynamic>{'gameId': 7, 'topicId': 88}).slotText(slots),
        '本游戏挂起 2/3',
      );
      expect(
        row(<String, dynamic>{'topicId': 88}).slotText(slots),
        '本主题已接受 1/5',
      );
      expect(row(<String, dynamic>{'topicId': 99}).slotText(slots), '');
      expect(row(<String, dynamic>{'topicId': 88}).slotText(null), '');
    });

    test('理由 / 锁价 / 封面解析(封面按真源字段取)', () {
      final CoopInviteRow r = row(<String, dynamic>{
        'handleReason': '档期撞了',
        'termsFrozen': true,
        'topicCover': 'https://cdn.example.com/a.jpg',
      });
      expect(r.handleReason, '档期撞了');
      expect(r.termsFrozen, isTrue);
      expect(r.coverUrl, 'https://cdn.example.com/a.jpg');
      // 空串与缺席同处理,不留一个只有空格的封面地址。
      expect(row(<String, dynamic>{'cover': '   '}).coverUrl, isNull);
      expect(
        row(<String, dynamic>{'topicImgUrl': 'https://cdn.example.com/b.jpg'}).coverUrl,
        'https://cdn.example.com/b.jpg',
      );
    });

    test('slots 挂在列表响应顶层,不随行下发', () {
      final CoopInviteList list = CoopInviteList.fromJson(<String, dynamic>{
        'sent': <dynamic>[],
        'received': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'fromId': 10,
            'toType': 'merchant',
            'toId': 20,
            'topicId': 20,
          },
        ],
        'slots': <String, dynamic>{
          'byTopic': <String, dynamic>{
            '20': <String, dynamic>{'accepted': 2, 'cap': 5},
          },
        },
      });
      final CoopInviteRow r = list.received.single;
      expect(r.slotText(list.slots), '本主题已接受 2/5');
      expect(CoopInviteList.fromJson(<String, dynamic>{}).slots, isNull);
    });
  });

  group('CoopInviteList.fromJson', () {
    test('sent/received 分别解析,互不影响', () {
      final list = CoopInviteList.fromJson(<String, dynamic>{
        'sent': <dynamic>[
          <String, dynamic>{'id': 1, 'fromId': 1, 'toType': 'merchant', 'toId': 2},
        ],
        'received': <dynamic>[],
      });
      expect(list.sent.length, 1);
      expect(list.received, isEmpty);
    });
  });
}
