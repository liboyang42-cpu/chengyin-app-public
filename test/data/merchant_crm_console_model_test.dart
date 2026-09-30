// CRM 运营台(客户名册 / 分群 / 触达)的模型门禁。
//
// ★ 判据全部来自小程序快照 `pages/merchant/customer/index.js`:
//   `isCustomerRow`(畸形行整页 fail-closed)/ `shapeRow`(展示文案)/
//   `_queryKey`(查询六键)/ `_segmentFilter`(保存分群形状)/
//   `shapeCampaign`(触达任务)/ `createRequestId`(幂等号格式)。

import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  int memberId = 42,
  String name = '张三',
  String? phone = '13812341234',
  String tier = 'pending',
  String sourceType = 'TOPIC',
  String lastTime = '2026-09-10 12:00:00',
  String lastAction = '核销了夜跑咖啡路线',
  String? latestNote,
  String? contactHint,
}) => <String, dynamic>{
  'memberId': memberId,
  'name': name,
  'avatar': null,
  'phone': phone,
  'contactHint': contactHint,
  'latestNote': latestNote,
  'arrivedCount': 2,
  'pendingCount': 0,
  'refundedCount': 0,
  'paidAmount': 199.0,
  'lastTime': lastTime,
  'lastAction': lastAction,
  'tier': tier,
  'sourceType': sourceType,
};

void main() {
  group('查询体逐键对齐快照 _queryKey', () {
    test('六键 + 分页,空值发 null 不省键', () {
      const CrmCustomerQuery query = CrmCustomerQuery();
      expect(query.toJson(), <String, dynamic>{
        'pageNum': 1,
        'pageSize': 20,
        'keyword': '',
        'segment': 'all',
        'tagId': null,
        'sourceType': null,
        'sourceStart': null,
        'sourceEnd': null,
      });
    });

    test('带筛选时逐键透传', () {
      const CrmCustomerQuery query = CrmCustomerQuery(
        pageNum: 3,
        keyword: '张',
        segment: 'repeat',
        tagId: 7,
        sourceType: 2,
        sourceStart: '2026-08-01',
        sourceEnd: '2026-08-31',
      );
      final Map<String, dynamic> json = query.toJson();
      expect(json['pageNum'], 3);
      expect(json['keyword'], '张');
      expect(json['segment'], 'repeat');
      expect(json['tagId'], 7);
      expect(json['sourceType'], 2);
    });

    test('保存分群:all 折成 null(快照 _segmentFilter)', () {
      const CrmCustomerQuery query = CrmCustomerQuery(
        segment: 'all',
        tagId: 9,
      );
      final CrmSegmentFilter filter = query.toFilter();
      expect(filter.segment, isNull);
      expect(filter.tagId, 9);
      expect(filter.toJson()['segment'], isNull);
    });

    test('sameQuery 忽略分页,只看筛选', () {
      const CrmCustomerQuery a = CrmCustomerQuery(keyword: '张', pageNum: 1);
      const CrmCustomerQuery b = CrmCustomerQuery(keyword: '张', pageNum: 5);
      const CrmCustomerQuery c = CrmCustomerQuery(keyword: '李', pageNum: 5);
      expect(a.sameQuery(b), isTrue);
      expect(a.sameQuery(c), isFalse);
    });
  });

  group('★ 行解析 fail-closed(快照 isCustomerRow)', () {
    test('合法行全字段解析', () {
      final CrmCustomerRow? row = CrmCustomerRow.tryParse(_row());
      expect(row, isNotNull);
      expect(row!.memberId, 42);
      expect(row.displayName, '张三');
      expect(row.tierText, '待核销');
      expect(row.tierIsWarning, isTrue);
      expect(row.phoneText, '13812341234');
    });

    test('任一字段不合法整行 null', () {
      expect(CrmCustomerRow.tryParse(_row(memberId: 0)), isNull);
      expect(CrmCustomerRow.tryParse(_row(name: '   ')), isNull);
      expect(CrmCustomerRow.tryParse(_row(tier: 'whatever')), isNull);
      expect(CrmCustomerRow.tryParse(_row(sourceType: 'OTHER')), isNull);
      expect(CrmCustomerRow.tryParse(_row(lastTime: '乱写')), isNull);
      expect(CrmCustomerRow.tryParse(_row(lastAction: '  ')), isNull);
      final Map<String, dynamic> broken = _row();
      broken['arrivedCount'] = -1;
      expect(CrmCustomerRow.tryParse(broken), isNull);
    });

    test('缺 tier / 缺时间也算畸形(不猜默认值)', () {
      final Map<String, dynamic> noTier = _row()..remove('tier');
      expect(CrmCustomerRow.tryParse(noTier), isNull);
      final Map<String, dynamic> noTime = _row()..remove('lastTime');
      expect(CrmCustomerRow.tryParse(noTime), isNull);
    });

    test('数字时间戳按毫秒转 ISO(relativeTime 能算)', () {
      final CrmCustomerRow? row = CrmCustomerRow.tryParse(
        _row(lastTime: 'unused')..['lastTime'] = 1757467200000,
      );
      expect(row, isNotNull);
      expect(DateTime.tryParse(row!.lastTime!), isNotNull);
    });
  });

  group('展示文案(快照 shapeRow/TIER_TEXT)', () {
    test('没留姓名:空白名字本身就是畸形行,parse 阶段就拦掉', () {
      expect(CrmCustomerRow.tryParse(_row(name: ' ')), isNull);
    });

    test('分层五档 + 未知不印英文', () {
      expect(CrmCustomerRow.tryParse(_row(tier: 'repeat'))!.tierText, '复购');
      expect(CrmCustomerRow.tryParse(_row(tier: 'dormant'))!.tierText, '沉睡');
      expect(CrmCustomerRow.tryParse(_row(tier: 'abnormal'))!.tierText, '异常');
      expect(CrmCustomerRow.tryParse(_row(tier: 'new'))!.tierText, '新客');
    });

    test('actionText 两截都可能空,不拼孤零零的「· 」', () {
      final DateTime now = DateTime(2026, 9, 13, 12);
      final CrmCustomerRow row = CrmCustomerRow.tryParse(_row())!;
      expect(row.actionText(now), '核销了夜跑咖啡路线 · 3 天前');
    });
  });

  group('分页回包(快照 _fetch 的 shape 校验)', () {
    test('total 缺失或非整数 → 整页 null', () {
      expect(CrmCustomerPageData.tryParse(<String, dynamic>{'rows': <dynamic>[]}), isNull);
      expect(
        CrmCustomerPageData.tryParse(<String, dynamic>{'total': '12', 'rows': <dynamic>[]}),
        isNull,
      );
    });

    test('任一畸形行 → 整页 null,不静默丢行', () {
      expect(
        CrmCustomerPageData.tryParse(<String, dynamic>{
          'total': 2,
          'rows': <dynamic>[_row(), _row(memberId: 0)],
        }),
        isNull,
      );
    });

    test('segmentCounts 缺档 → null,不伪造 0;summaryText 三态', () {
      final CrmCustomerPageData page = CrmCustomerPageData.tryParse(<String, dynamic>{
        'total': 12,
        'rows': <dynamic>[_row()],
        'segmentCounts': <String, dynamic>{'all': 12, 'monthlyNew': 3},
      })!;
      expect(page.segmentCounts['repeat'], isNull);
      expect(page.summaryText(), '12 位 · 本月新增 3');
      final CrmCustomerPageData noMonthly = CrmCustomerPageData.tryParse(<String, dynamic>{
        'total': 12,
        'rows': <dynamic>[],
        'segmentCounts': <String, dynamic>{'all': 12},
      })!;
      expect(noMonthly.summaryText(), '12 位');
      final CrmCustomerPageData none = CrmCustomerPageData.tryParse(<String, dynamic>{
        'total': 0,
        'rows': <dynamic>[],
      })!;
      expect(none.summaryText(), '客户数量加载中');
    });

    test('标签候选过滤非法项', () {
      final List<CrmAvailableTag> tags = CrmAvailableTag.parseList(<dynamic>[
        <String, dynamic>{'id': 3, 'tagName': ' 高价值 ', 'tagColor': '#123456'},
        <String, dynamic>{'id': 0, 'tagName': '坏的'},
        <String, dynamic>{'id': 4, 'tagName': '  '},
      ]);
      expect(tags.length, 1);
      expect(tags.single.tagName, '高价值');
      expect(tags.single.tagColor, '#123456');
    });
  });

  group('分群 / 券', () {
    test('保存分群行解析 + filter 透传', () {
      final List<CrmSavedSegment> rows = CrmSavedSegment.parseList(<dynamic>[
        <String, dynamic>{
          'id': 5,
          'name': '复购客',
          'filter': <String, dynamic>{'segment': 'repeat', 'tagId': 9},
        },
        <String, dynamic>{'id': 0, 'name': '坏的'},
      ]);
      expect(rows.length, 1);
      expect(rows.single.name, '复购客');
      expect(rows.single.filter!.segment, 'repeat');
      expect(rows.single.filter!.tagId, 9);
    });

    test('券列表只收正 id', () {
      final List<CrmCoupon> coupons = CrmCoupon.parseList(<dynamic>[
        <String, dynamic>{'id': 9, 'name': '满减券'},
        <String, dynamic>{'id': 'x', 'name': '坏的'},
      ]);
      expect(coupons.length, 1);
      expect(coupons.single.name, '满减券');
    });
  });

  group('触达任务(快照 shapeCampaign)', () {
    test('预览缺字段回 0,recipientLimit 兜底 200', () {
      final CrmCampaignPreview preview = CrmCampaignPreview.tryParse(
        <String, dynamic>{'totalCount': 12, 'deliverableCount': 9},
      )!;
      expect(preview.totalCount, 12);
      expect(preview.deliverableCount, 9);
      expect(preview.recipientLimit, 200);
      expect(CrmCampaignPreview.tryParse('x'), isNull);
    });

    test('任务四档标题 + 历史列表标题兜底', () {
      CrmCampaignTask task(String status) =>
          CrmCampaignTask.tryParse(<String, dynamic>{'id': 8, 'status': status})!;
      expect(task('SUCCESS').statusText, '发送成功');
      expect(task('PARTIAL_FAILED').statusText, '部分完成');
      expect(task('NO_ELIGIBLE').statusText, '暂无可触达人群');
      expect(task('SENDING').statusText, '处理中');
      expect(
        CrmCampaignTask.tryParse(<String, dynamic>{'id': 8, 'channel': 'COUPON'})!.listTitle,
        '优惠券触达',
      );
      expect(
        CrmCampaignTask.tryParse(<String, dynamic>{'id': 8, 'title': '周末提醒'})!.listTitle,
        '周末提醒',
      );
    });

    test('逐人回执:送达 / 失败原因 / 待处理', () {
      final CrmCampaignTask task = CrmCampaignTask.tryParse(<String, dynamic>{
        'id': 8,
        'status': 'PARTIAL_FAILED',
        'retryableCount': 2,
        'recipients': <dynamic>[
          <String, dynamic>{'recipientId': 9, 'customerName': '林青', 'status': 'DELIVERED', 'messageReceiptId': 66},
          <String, dynamic>{'recipientId': 10, 'customerName': '王五', 'status': 'FAILED', 'failureMessage': '已退订'},
          <String, dynamic>{'recipientId': 11, 'customerName': '赵六', 'status': 'PENDING'},
        ],
      })!;
      expect(task.retryableCount, 2);
      expect(task.isPartialFailed, isTrue);
      expect(task.recipients[0].statusText(), '已送达');
      expect(task.recipients[0].messageReceiptId, 66);
      expect(task.recipients[1].statusText(), '已退订');
      expect(task.recipients[2].statusText(), '待处理');
    });
  });

  test('幂等号格式对齐快照 createRequestId', () {
    final String a = newCrmRequestId('batch-tag');
    final String b = newCrmRequestId('batch-tag');
    expect(a.startsWith('crm-batch-tag-'), isTrue);
    expect(b.startsWith('crm-batch-tag-'), isTrue);
    expect(a, isNot(b));
  });

  test('送达规则文案两档', () {
    expect(crmDeliveryStatusText('CONSENT_REQUIRED'), '仅触达已同意客户');
    expect(crmDeliveryStatusText('WHATEVER'), '规则待同步');
    expect(crmDeliveryStatusText(''), '规则待同步');
  });
}
