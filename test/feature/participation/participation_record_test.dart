import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  required int id,
  int ownerType = 1,
  int registrationStatus = 2,
  int verificationStatus = 0,
  Map<String, dynamic>? refundApplication,
  Map<String, dynamic>? refundInfo,
  String start = '2026-08-23 00:00:00',
  String end = '2026-08-24 23:59:59',
}) => <String, dynamic>{
  'id': id,
  'ownerType': ownerType,
  'ownerId': 90 + id,
  'registrationStatus': registrationStatus,
  'verificationStatus': verificationStatus,
  'refundApplication': refundApplication,
  'refundInfo': refundInfo,
  'purchaseKind': 3,
  if (ownerType == 1)
    'cmsTopic': <String, dynamic>{
      'name': '夜游苏河',
      'imgUrl': 'https://img.test/topic.jpg',
      'address': '苏河湾',
      'startDate': start,
      'endDate': end,
      'productType': 2,
    }
  else
    'cmsActivity': <String, dynamic>{
      'name': '街区快闪',
      'imgArr': <String>['https://img.test/activity.jpg'],
      'addressName': '静安寺',
      'startDate': start,
      'endDate': end,
    },
};

void main() {
  final DateTime now = DateTime.parse('2026-08-23T12:00:00Z');

  test('参与记录映射小程序标题、封面、时间、类型与地址', () {
    final ParticipationRecord record = ParticipationRecord.fromJson(
      _row(id: 7),
      now: now,
    );

    expect(record.id, 7);
    expect(record.sourceName, '夜游苏河');
    expect(record.coverUrl, 'https://img.test/topic.jpg');
    expect(record.dateText, '08.23 - 08.24');
    expect(record.typeLabel, '自由探索');
    expect(record.address, '苏河湾');
    expect(record.state, ParticipationState.inProgress);
    expect(record.stateText, '进行中');
  });

  test('四档筛选状态按已核销、时间顺序判定', () {
    final List<ParticipationRecord> rows = <ParticipationRecord>[
      ParticipationRecord.fromJson(
        _row(id: 1, start: '2026-08-24 00:00:00', end: '2026-08-25 00:00:00'),
        now: now,
      ),
      ParticipationRecord.fromJson(_row(id: 2), now: now),
      ParticipationRecord.fromJson(
        _row(id: 3, start: '2026-08-20 00:00:00', end: '2026-08-22 00:00:00'),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(
          id: 4,
          verificationStatus: 1,
          start: '2026-08-24 00:00:00',
          end: '2026-08-25 00:00:00',
        ),
        now: now,
      ),
    ];

    expect(
      rows.map((ParticipationRecord row) => row.state),
      <ParticipationState>[
        ParticipationState.notStarted,
        ParticipationState.inProgress,
        ParticipationState.completed,
        ParticipationState.completed,
      ],
    );
    expect(
      filterParticipations(
        rows,
        ParticipationFilter.completed,
      ).map((ParticipationRecord row) => row.id),
      <int>[3, 4],
    );
    expect(
      ParticipationFilter.values.map(
        (ParticipationFilter value) => value.label,
      ),
      <String>['全部', '未开始', '进行中', '已完成'],
    );
  });

  test('活动记录使用线下活动类型并取 imgArr 首图', () {
    final ParticipationRecord record = ParticipationRecord.fromJson(
      _row(id: 8, ownerType: 2),
      now: now,
    );

    expect(record.sourceName, '街区快闪');
    expect(record.coverUrl, 'https://img.test/activity.jpg');
    expect(record.typeLabel, '线下活动');
    expect(record.address, '静安寺');
  });

  test('未知 ownerType 不冒充线下活动，也不读取错误业务对象', () {
    final ParticipationRecord record = ParticipationRecord.fromJson(
      _row(id: 9, ownerType: 99),
      now: now,
    );

    expect(record.ownerType, 99);
    expect(record.typeLabel, '类型待确认');
    expect(record.sourceName, '活动信息待补充');
    expect(record.coverUrl, isEmpty);
    expect(record.address, '地点待定');
  });

  test('全部保留订单特殊状态，但三种进度筛选不能误收', () {
    final List<ParticipationRecord> rows = <ParticipationRecord>[
      ParticipationRecord.fromJson(
        _row(id: 11, registrationStatus: 1),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(id: 12, registrationStatus: 3),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(id: 13, refundApplication: <String, dynamic>{'payoutStatus': 1}),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(id: 14, refundApplication: <String, dynamic>{'payoutStatus': 0}),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(id: 15, refundInfo: <String, dynamic>{'refundable': false}),
        now: now,
      ),
      ParticipationRecord.fromJson(
        _row(id: 16, registrationStatus: 9),
        now: now,
      ),
    ];

    expect(rows.map((ParticipationRecord row) => row.stateText), <String>[
      '待支付',
      '已取消',
      '已退款',
      // payoutStatus==0 = 微信已受理原路退款:真源说「退款处理中」,
      // 不给「预计 N 个工作日」这种没人兑现的承诺。
      '退款处理中',
      '不可退款',
      '订单状态更新中',
    ]);
    expect(filterParticipations(rows, ParticipationFilter.all), rows);
    for (final ParticipationFilter filter in <ParticipationFilter>[
      ParticipationFilter.notStarted,
      ParticipationFilter.inProgress,
      ParticipationFilter.completed,
    ]) {
      expect(filterParticipations(rows, filter), isEmpty);
    }
  });

  test('真源状态机补档:已过期、人工售后、驳回与零元单回落到真实状态', () {
    ParticipationRecord rec(int id, Map<String, dynamic> extra) =>
        ParticipationRecord.fromJson(<String, dynamic>{
          ..._row(id: id),
          ...extra,
        }, now: now);

    // registrationStatus==4 = 后端 closeExpired 关单,以前落到「订单状态更新中」。
    expect(
      rec(21, <String, dynamic>{'registrationStatus': 4}).stateText,
      '已过期',
    );
    expect(
      rec(21, <String, dynamic>{'registrationStatus': 4}).state,
      ParticipationState.expired,
    );
    // manualRefundCaseStatus 有值 = 人工售后,优先级最高。
    final ParticipationRecord manual = rec(22, <String, dynamic>{
      'manualRefundCaseStatus': 1,
    });
    expect(manual.stateText, '人工售后');
    expect(manual.state, ParticipationState.manualRefund);
    // 退款申请被驳回(status==2)⇒ 不是退款中,回落到订单真实状态(进行中)。
    final ParticipationRecord rejected = rec(23, <String, dynamic>{
      'refundApplication': <String, dynamic>{'status': 2, 'payoutStatus': 5},
    });
    expect(rejected.state, ParticipationState.inProgress);
    expect(rejected.stateText, '进行中');
    // 零元单没有钱可退 ⇒ 不给在途承诺,同样回落。
    final ParticipationRecord zeroAmount = rec(24, <String, dynamic>{
      'refundApplication': <String, dynamic>{
        'status': 1,
        'payoutStatus': 5,
        'refundAmount': 0,
      },
    });
    expect(zeroAmount.state, ParticipationState.inProgress);
    // status==0 待审核 ⇒ 「退款审核中」,和「退款处理中」不是一档。
    expect(
      rec(25, <String, dynamic>{
        'refundApplication': <String, dynamic>{
          'status': 0,
          'payoutStatus': 5,
          'refundAmount': 9.9,
        },
      }).stateText,
      '退款审核中',
    );
  });
}
