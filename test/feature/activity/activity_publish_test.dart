import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/activity_publish.dart';

void main() {
  final t0 = DateTime(2026, 9, 1, 10);
  final t1 = DateTime(2026, 9, 1, 18);

  TicketDraft ticket({
    String name = '标准票',
    double? price = 99,
    DateTime? s,
    DateTime? e,
    int? stock = 20,
  }) => TicketDraft(
    name: name,
    price: price,
    startTime: s ?? t0,
    endTime: e ?? t1,
    totalStock: stock,
  );

  ActivityPublishForm form({
    String name = '夜跑咖啡',
    DateTime? s,
    DateTime? e,
    List<TicketDraft>? tickets,
  }) => ActivityPublishForm(
    name: name,
    description: '沿苏河湾跑一圈',
    imgUrl: 'https://img.example/cover.jpg',
    addressName: '静安公园',
    startDate: s ?? t0,
    endDate: e ?? t1,
    templateId: 31,
    categoryIds: const <int>[2, 7],
    tickets: tickets ?? <TicketDraft>[ticket()],
  );

  group('★ 价格:没填 ≠ 免费', () {
    test('price 为 null → 提示填价格,不当成免费', () {
      expect(
        ticket(price: null).blocker,
        '请填写价格(免费填 0)',
        reason: '默认成 0 会让用户以为自己设了免费票',
      );
    });
    test('price 为 0 → 就是免费,放行', () {
      expect(ticket(price: 0).blocker, isNull);
    });
    test('负价挡住', () {
      expect(ticket(price: -1).blocker, '价格不能为负');
    });
  });

  group('★ 库存:没填 ≠ 0 张', () {
    test('null → 提示填', () {
      expect(ticket(stock: null).blocker, '请填写总库存');
    });
    test('0 → 挡住(0 张票的活动没意义)', () {
      expect(ticket(stock: 0).blocker, '总库存要大于 0');
    });
  });

  group('★ 时间自洽(后端只判非空,不判先后)', () {
    test('结束早于开始 → 挡住', () {
      expect(form(s: t1, e: t0).blocker, '结束时间要晚于开始时间');
    });
    test('结束等于开始 → 也挡住(零时长没意义)', () {
      expect(form(s: t0, e: t0).blocker, '结束时间要晚于开始时间');
    });
    test('正常先后 → 放行', () {
      expect(form().canSubmit, isTrue);
    });
  });

  group('★★ 票的履约窗口不能超出活动窗口', () {
    // 后端只对票做 @NotNull,不校验它与活动时间的关系 ——
    // 履约期跑到活动之后,会出现"活动都结束了票还能核销"。
    test('履约开始早于活动开始 → 挡住', () {
      final f = form(
        tickets: <TicketDraft>[
          ticket(s: t0.subtract(const Duration(hours: 1))),
        ],
      );
      expect(f.blocker, contains('履约开始早于活动开始'));
    });
    test('履约结束晚于活动结束 → 挡住', () {
      final f = form(
        tickets: <TicketDraft>[ticket(e: t1.add(const Duration(hours: 1)))],
      );
      expect(f.blocker, contains('履约结束晚于活动结束'));
    });
    test('刚好贴边 → 放行', () {
      expect(
        form(
          tickets: <TicketDraft>[ticket(s: t0, e: t1)],
        ).canSubmit,
        isTrue,
      );
    });
    test('报错带票名,方便定位是哪一张', () {
      final f = form(
        tickets: <TicketDraft>[
          ticket(name: '早鸟票', e: t1.add(const Duration(hours: 1))),
        ],
      );
      expect(f.blocker, startsWith('早鸟票:'));
    });
    test('没名字的票用序号指认', () {
      final f = form(tickets: <TicketDraft>[ticket(name: '  ')]);
      expect(f.blocker, startsWith('第 1 张票:'));
    });
  });

  group('必填与顺序', () {
    test('按填写顺序逐条报,不一次报一堆', () {
      expect(ActivityPublishForm().blocker, '请填写活动标题');
      expect(const ActivityPublishForm(name: 'X').blocker, '请填写活动地点');
      expect(
        const ActivityPublishForm(name: 'X', addressName: '静安公园').blocker,
        '请填写活动说明',
      );
      expect(
        const ActivityPublishForm(
          name: 'X',
          addressName: '静安公园',
          description: '活动说明',
        ).blocker,
        '请选择活动开始时间',
      );
    });
  });

  group('提交体', () {
    test('名称与描述裁空白', () {
      final j = form(name: '  夜跑咖啡  ').toJson();
      expect(j['name'], '夜跑咖啡');
    });
    test('票列表带出去', () {
      expect((form().toJson()['tickets'] as List<dynamic>).length, 1);
    });
    test('对齐小程序的分类、封面数组和我的模板字段', () {
      final Map<String, dynamic> json = form().toJson();
      expect(json['categoryIds'], '2,7');
      expect(json['imgUrl'], 'https://img.example/cover.jpg');
      expect(json['imgArr'], 'https://img.example/cover.jpg');
      expect(json['templateId'], 31);
    });
    test('日期按后端 JsonFormat 发本地时间，不发 ISO T/时区后缀', () {
      final Map<String, dynamic> json = form().toJson();
      expect(json['startDate'], '2026-09-01 10:00:00');
      expect(json['endDate'], '2026-09-01 18:00:00');
      final Map<String, dynamic> ticketJson =
          (json['tickets'] as List<dynamic>).single as Map<String, dynamic>;
      expect(ticketJson['startTime'], '2026-09-01 10:00:00');
      expect(ticketJson['endTime'], '2026-09-01 18:00:00');
    });
  });

  group('★ 发布失败四分:身份 / 配额 / 内容 / 故障', () {
    test('不是主理人 → 不给重试', () {
      final e = ActivityPublishException('仅俱乐部主理人可发布活动');
      expect(e.isNotClubLeader, isTrue);
      expect(e.retryable, isFalse, reason: '重试不会让他变成主理人');
    });
    test('配额用尽 → 不给重试', () {
      for (final String m in <String>['本月发布配额已用尽', '已达发布上限', '额度不足']) {
        expect(ActivityPublishException(m).retryable, isFalse, reason: m);
      }
    });
    test('内容被拒 → 不给重试(要改文字)', () {
      expect(ActivityPublishException('内容含有违规信息').retryable, isFalse);
    });
    test('★ 真故障 → 给重试', () {
      for (final String m in <String>['网络异常', '请稍后重试', '服务不可用']) {
        expect(ActivityPublishException(m).retryable, isTrue, reason: m);
      }
    });
    test('四类互不误判', () {
      final fault = ActivityPublishException('网络异常');
      expect(fault.isNotClubLeader, isFalse);
      expect(fault.isQuotaExceeded, isFalse);
      expect(fault.isContentRejected, isFalse);
    });
  });
}
