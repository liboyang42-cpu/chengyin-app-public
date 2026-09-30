import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/orders/order_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

RegistrationDetail _detail({
  int? registrationStatus,
  int? paymentStatus,
  int? verificationStatus,
  bool? refundable,
  String? createTime,
  String? paymentTime,
  String? verificationTime,
  String? manualRefundCaseStatus,
  bool hasRefundApplication = false,
  int? refundApplicationStatus,
  int? refundPayoutStatus,
  double? refundAmount,
  String? refundPayoutTime,
  String? refundUpdateTime,
  String? refundInfoReason,
  String? ownerStartDate,
  String? ownerEndDate,
}) => RegistrationDetail(
  id: 1,
  ownerType: 2,
  ownerId: 9,
  entitlements: const <Entitlement>[],
  registrationStatus: registrationStatus,
  paymentStatus: paymentStatus,
  verificationStatus: verificationStatus,
  refundable: refundable,
  createTime: createTime,
  paymentTime: paymentTime,
  verificationTime: verificationTime,
  manualRefundCaseStatus: manualRefundCaseStatus,
  hasRefundApplication: hasRefundApplication,
  refundApplicationStatus: refundApplicationStatus,
  refundPayoutStatus: refundPayoutStatus,
  refundAmount: refundAmount,
  refundPayoutTime: refundPayoutTime,
  refundUpdateTime: refundUpdateTime,
  refundInfoReason: refundInfoReason,
  ownerStartDate: ownerStartDate,
  ownerEndDate: ownerEndDate,
);

/// 固定「现在」:2026-09-19 12:00 东八区。
final DateTime _now = DateTime.parse('2026-09-19T12:00:00+08:00');

void main() {
  group('toDisplayTime(后端墙钟 → YYYY-MM-DD HH:mm)', () {
    test('空格分隔与 T 分隔都吃,秒被舍掉', () {
      expect(toDisplayTime('2026-09-18 14:03:22'), '2026-09-18 14:03');
      expect(toDisplayTime('2026-09-18T14:03:22'), '2026-09-18 14:03');
    });

    test('epoch 秒(10位)/毫秒(13位)按东八区渲染', () {
      final int ms = DateTime.utc(
        2026,
        9,
        18,
        4,
        23,
        22,
      ).millisecondsSinceEpoch;
      expect(toDisplayTime(ms ~/ 1000), '2026-09-18 12:23');
      expect(toDisplayTime('$ms'), '2026-09-18 12:23');
    });

    test('取不到给空串(时间线该行不印时间)', () {
      expect(toDisplayTime(null), '');
      expect(toDisplayTime(''), '');
      expect(toDisplayTime('不是时间'), '');
    });
  });

  group('summarizeOrderState', () {
    test('人工售后盖过一切,refundText 回落兜底句', () {
      final s = summarizeOrderState(
        _detail(
          registrationStatus: 2,
          manualRefundCaseStatus: 'PENDING_ASSESSMENT',
        ),
        now: _now,
      );
      expect(s.key, 'manual_refund');
      expect(s.text, '人工售后');
      expect(s.refundText, '请查看订单的人工处理进度');
    });

    test('退款终态只认 payout_status:1/4 已退款,2/3 处理中', () {
      expect(
        summarizeOrderState(
          _detail(
            registrationStatus: 3,
            hasRefundApplication: true,
            refundPayoutStatus: 1,
          ),
          now: _now,
        ).key,
        'refunded',
      );
      final s = summarizeOrderState(
        _detail(
          registrationStatus: 2,
          hasRefundApplication: true,
          refundPayoutStatus: 2,
        ),
        now: _now,
      );
      expect(s.key, 'refunding');
      expect(s.refundText, '原路退款异常，平台正在人工处理');
    });

    test('零元单不给在途承诺;驳回不是退款中', () {
      expect(
        summarizeOrderState(
          _detail(
            registrationStatus: 1,
            hasRefundApplication: true,
            refundApplicationStatus: 0,
            refundAmount: 0,
          ),
          now: _now,
        ).key,
        'pending_payment',
      );
      expect(
        summarizeOrderState(
          _detail(
            registrationStatus: 2,
            hasRefundApplication: true,
            refundApplicationStatus: 2,
            refundAmount: 10,
          ),
          now: _now,
        ).key,
        'in_progress', // 驳回回落到订单真实状态(无起止信息 → 进行中)
      );
    });

    test('status=0 待审核 → 退款审核中(不给「预计N工作日」)', () {
      final s = summarizeOrderState(
        _detail(
          registrationStatus: 2,
          hasRefundApplication: true,
          refundApplicationStatus: 0,
          refundAmount: 20,
        ),
        now: _now,
      );
      expect(s.key, 'refunding');
      expect(s.text, '退款审核中');
      expect(s.refundText, '退款申请已提交，等待平台审核');
    });

    test('待支付/已取消/已过期/状态更新中', () {
      expect(
        summarizeOrderState(_detail(registrationStatus: 1), now: _now).key,
        'pending_payment',
      );
      expect(
        summarizeOrderState(_detail(registrationStatus: 3), now: _now).key,
        'cancelled',
      );
      expect(
        summarizeOrderState(_detail(registrationStatus: 4), now: _now).text,
        '已过期',
      );
      expect(
        summarizeOrderState(_detail(registrationStatus: 9), now: _now).text,
        '订单状态更新中',
      );
    });

    test('已核销 → 已完成;refundable=false → 不可退款(reason 透传)', () {
      expect(
        summarizeOrderState(
          _detail(registrationStatus: 2, verificationStatus: 1),
          now: _now,
        ).key,
        'completed',
      );
      final s = summarizeOrderState(
        _detail(
          registrationStatus: 2,
          refundable: false,
          refundInfoReason: '已核销或已过开始时间不可退',
        ),
        now: _now,
      );
      expect(s.key, 'non_refundable');
      expect(s.refundText, '已核销或已过开始时间不可退');
    });

    test('按 owner 起止推 未开始/进行中/已结束', () {
      expect(
        summarizeOrderState(
          _detail(registrationStatus: 2, ownerStartDate: '2026-09-25 10:00:00'),
          now: _now,
        ).key,
        'not_started',
      );
      expect(
        summarizeOrderState(
          _detail(
            registrationStatus: 2,
            ownerStartDate: '2026-09-18 10:00:00',
            ownerEndDate: '2026-09-19 20:00:00',
          ),
          now: _now,
        ).key,
        'in_progress',
      );
      final s = summarizeOrderState(
        _detail(
          registrationStatus: 2,
          ownerStartDate: '2026-09-10 10:00:00',
          ownerEndDate: '2026-09-11 10:00:00',
        ),
        now: _now,
      );
      expect(s.key, 'completed');
      expect(s.refundText, '活动已结束');
    });
  });

  group('buildOrderTimeline(顺序与文案逐行对齐真源)', () {
    test('未支付:创建 → 等待支付(current),后面不再排', () {
      final rows = buildOrderTimeline(
        _detail(registrationStatus: 1, createTime: '2026-09-18 09:00:00'),
        now: _now,
      );
      expect(rows.map((r) => r.label), <String>['订单已创建', '等待支付']);
      expect(rows[0].time, '2026-09-18 09:00');
      expect(rows[0].done, isTrue);
      expect(rows[1].time, '完成后更新');
      expect(rows[1].done, isFalse);
    });

    test('已取消(未支付):创建 → 订单已取消', () {
      final rows = buildOrderTimeline(
        _detail(registrationStatus: 3, createTime: '2026-09-18 09:00:00'),
        now: _now,
      );
      expect(rows.map((r) => r.label), <String>['订单已创建', '订单已取消']);
      expect(rows[1].time, '');
      expect(rows[1].done, isTrue);
    });

    test('已支付未核销:创建 → 支付已完成 → 等待到店核销(current)', () {
      final rows = buildOrderTimeline(
        _detail(
          registrationStatus: 2,
          paymentStatus: 2,
          createTime: '2026-09-18 09:00:00',
          paymentTime: '2026-09-18 09:01:00',
          ownerStartDate: '2026-09-20 10:00:00',
        ),
        now: _now,
      );
      expect(rows.map((r) => r.label), <String>['订单已创建', '支付已完成', '等待到店核销']);
      expect(rows[2].time, '完成后更新');
    });

    test('已核销:核销行带时间、done', () {
      final rows = buildOrderTimeline(
        _detail(
          registrationStatus: 2,
          paymentStatus: 2,
          verificationStatus: 1,
          verificationTime: '2026-09-20 10:05:00',
        ),
        now: _now,
      );
      expect(rows.last.label, '权益已核销');
      expect(rows.last.time, '2026-09-20 10:05');
      expect(rows.last.done, isTrue);
    });

    test('退款分支排在支付之后、核销之前,时间取 payoutTime→updateTime', () {
      final rows = buildOrderTimeline(
        _detail(
          registrationStatus: 2,
          paymentStatus: 2,
          hasRefundApplication: true,
          refundPayoutStatus: 1,
          refundPayoutTime: '2026-09-21 08:00:00',
        ),
        now: _now,
      );
      expect(rows.map((r) => r.label), <String>['订单已创建', '支付已完成', '已退款']);
      expect(rows.last.time, '2026-09-21 08:00');
      expect(rows.last.done, isTrue);

      final processing = buildOrderTimeline(
        _detail(
          registrationStatus: 2,
          paymentStatus: 2,
          hasRefundApplication: true,
          refundApplicationStatus: 1,
          refundAmount: 30,
          refundUpdateTime: '2026-09-21 09:00:00',
        ),
        now: _now,
      );
      expect(processing.last.label, '退款处理中');
      expect(processing.last.time, '2026-09-21 09:00');
      expect(processing.last.done, isFalse);
    });

    test('人工售后:核销行说「尚未核销」,再追加工单行', () {
      final rows = buildOrderTimeline(
        _detail(
          registrationStatus: 2,
          paymentStatus: 2,
          manualRefundCaseStatus: 'NO_REFUND',
          createTime: '2026-09-18 09:00:00',
          paymentTime: '2026-09-18 09:01:00',
        ),
        now: _now,
      );
      expect(rows.map((r) => r.label), <String>[
        '订单已创建',
        '支付已完成',
        '尚未核销',
        '请查看订单的人工处理进度',
      ]);
      expect(rows[2].time, ''); // 人工售后不写「完成后更新」
      expect(rows.last.done, isTrue); // NO_REFUND 是终态
    });
  });
}
