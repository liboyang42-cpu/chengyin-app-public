// 资金域状态文案。逐条对齐小程序 pages/merchant/ledger,**任何合并都是 bug**。
//
// ★★★ 这些分支对商家意味着不同动作:
//   「待主题结算」vs「待结算」= 两种等法
//   「已入个人账户」vs「平台已打款」= 两个去处
//   「本期无需打款」vs「调整待处理」= 一个不用管、一个要处理
//   合并任意两条,商家就会按错的方式行动。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/merchant/finance_state_text.dart';

void main() {
  group('★★★ 单条记录', () {
    test('待结算按结算路径分两种说法', () {
      expect(
        financeStateText(
            displayState: 'PENDING_SETTLEMENT', settlementRoute: 'COOP_ORDER'),
        '待主题结算',
      );
      expect(financeStateText(displayState: 'PENDING_SETTLEMENT'), '待结算');
    });

    test('已结算按去处分两种说法', () {
      expect(
        financeStateText(
            displayState: 'SETTLED', destination: 'PERSONAL_ACCOUNT'),
        '已入个人账户',
      );
      expect(financeStateText(displayState: 'SETTLED'), '平台已打款');
    });

    test('★★ 零现金:有原因说原因,没原因说事实 —— 不替服务端编理由', () {
      expect(
        financeStateText(
            displayState: 'NO_CASH_SETTLEMENT', noCashReason: '本单已由俱乐部全额承担'),
        '本单已由俱乐部全额承担',
      );
      // 结算条目(MerchantSettlementEntry)后端不下发 noCashReason。
      expect(financeStateText(displayState: 'NO_CASH_SETTLEMENT'),
          '本次不产生现金结算');
    });

    test('★★★ 认不出的状态说「状态待确认」,不许猜成「待结算」', () {
      for (final String? s in <String?>[null, '', 'FUTURE_STATE']) {
        expect(financeStateText(displayState: s), '状态待确认',
            reason: '猜成「待结算」会让商家以为钱在路上');
      }
    });

    test('其余四态逐条', () {
      expect(financeStateText(displayState: 'ADJUSTMENT_PENDING'), '调整中');
      expect(financeStateText(displayState: 'ADJUSTED'), '已调整');
      expect(
          financeStateText(displayState: 'REVERSED_BEFORE_SETTLEMENT'), '核销已撤销');
      expect(financeStateText(displayState: 'LEDGER_ERROR'), '结算数据异常,已上报');
    });
  });

  group('★★★ 对公打款批次(四层分支)', () {
    String t({
      String? display,
      String? net,
      String? pay,
      String? invoice,
      String? hold,
    }) =>
        batchStateText(
          displayState: display,
          netDirection: net,
          paymentState: pay,
          invoiceState: invoice,
          holdState: hold,
        );

    test('结算异常盖过一切 —— 商家该等平台处理,不是等打款', () {
      expect(t(display: 'LEDGER_ERROR', net: 'ZERO', pay: 'PAID'),
          '结算数据异常,已上报');
    });

    test('本期无需打款 ≠ 待对账', () {
      expect(t(net: 'ZERO'), '本期无需打款');
    });

    test('反方向(商家欠平台)要说「调整待处理」,不是「待对账」', () {
      expect(t(net: 'MERCHANT_OWES_PLATFORM'), '调整待处理',
          reason: '说成待对账,商家会一直等一笔永远不会来的打款');
    });

    test('冻结中说「结算处理中」', () {
      expect(t(hold: 'FROZEN', pay: 'PAID'), '结算处理中');
    });

    test('已打款按开票态分两种', () {
      expect(t(pay: 'PAID', invoice: 'ISSUED'), '平台已打款 · 已开票');
      expect(t(pay: 'PAID', invoice: 'NONE'), '平台已打款 · 未开票');
    });

    test('已确认 / 兜底', () {
      expect(t(pay: 'CONFIRMED'), '已确认');
      expect(t(), '待对账');
    });
  });

  test('★★ 发票态认不出来时整块不显示,不写「未开票」', () {
    expect(invoiceText('NONE'), '未开票');
    expect(invoiceText('ISSUED'), '已开票');
    expect(invoiceText('RED'), '已红冲');
    expect(invoiceText(null), isNull,
        reason: '「拿不到」和「没开」是两件事 —— 后者会让商家去催开票');
    expect(invoiceText('WHATEVER'), isNull);
  });

  test('★ 语义色 1:1 映射,不含业务判断', () {
    expect(financeTone('PENDING_SETTLEMENT'), FinanceTone.warning);
    expect(financeTone('SETTLED'), FinanceTone.success);
    expect(financeTone('ADJUSTMENT_PENDING'), FinanceTone.danger);
    expect(financeTone('LEDGER_ERROR'), FinanceTone.danger);
    expect(financeTone('ADJUSTED'), FinanceTone.neutral);
    expect(financeTone('FUTURE'), FinanceTone.neutral);
    // 批次的色只看两件事。
    expect(batchTone(displayState: 'LEDGER_ERROR', paymentState: 'PAID'),
        FinanceTone.danger);
    expect(batchTone(displayState: null, paymentState: 'PAID'),
        FinanceTone.success);
    expect(batchTone(displayState: null, paymentState: null),
        FinanceTone.warning);
  });

  group('★★★ 打款进度 timeline', () {
    List<BatchTimelineNode> t({
      String? net = 'PLATFORM_PAYS_MERCHANT',
      String? pay,
      String? paidAt,
      String? voucher,
    }) =>
        batchTimeline(
          netDirection: net,
          paymentState: pay,
          paidAt: paidAt,
          payVoucherNo: voucher,
        );

    test('★★★ 未来节点不给日期、不写「预计」—— 那是假承诺', () {
      final List<BatchTimelineNode> nodes = t(pay: 'PENDING');
      expect(nodes.map((BatchTimelineNode n) => n.at),
          <String?>[null, null, null]);
      for (final BatchTimelineNode n in nodes) {
        expect(n.label.contains('预计'), isFalse,
            reason: '资金域定稿附录 C:「预计打款日期」这条规则代码里不存在');
      }
    });

    test('★★ 判据是业务事实不是时间戳:批次存在 ⇒ 生成节点恒实心', () {
      // 三种付款态,第一个节点都必须是 done。
      for (final String? s in <String?>[null, 'PENDING', 'CONFIRMED', 'PAID']) {
        expect(t(pay: s).first.state, 'done');
      }
    });

    test('★★ 走到第几步只看 paymentState', () {
      expect(t(pay: 'PENDING').map((BatchTimelineNode n) => n.state),
          <String>['done', 'now', 'todo']);
      expect(t(pay: 'CONFIRMED').map((BatchTimelineNode n) => n.state),
          <String>['done', 'done', 'now']);
      expect(t(pay: 'PAID').map((BatchTimelineNode n) => n.state),
          <String>['done', 'done', 'done'],
          reason: '打完款就没有「正在办」了');
    });

    test('★ 打款节点带日期与凭证;没凭证就只给日期', () {
      expect(t(pay: 'PAID', paidAt: '2026-08-18 14:30:00', voucher: 'V998').last.at,
          '2026-08-18 14:30 · 凭证 V998');
      expect(t(pay: 'PAID', paidAt: '2026-08-18 14:30:00').last.at,
          '2026-08-18 14:30');
      expect(t(pay: 'PAID').last.at, isNull,
          reason: '服务端没给时间就不写 —— 这个节点也一样');
    });

    test('★★★ 反方向不显示打款进度 —— 那笔钱是商家欠平台的', () {
      expect(t(net: 'MERCHANT_OWES_PLATFORM', pay: 'PAID'), isEmpty);
      expect(t(net: 'ZERO', pay: 'PAID'), isEmpty);
      expect(t(net: null, pay: 'PAID'), isEmpty);
    });

    test('★★★ 「已打给我了」要方向 + 付款态两个条件', () {
      expect(
        batchIsPaidToMerchant(
            netDirection: 'PLATFORM_PAYS_MERCHANT', paymentState: 'PAID'),
        isTrue,
      );
      expect(
        batchIsPaidToMerchant(
            netDirection: 'MERCHANT_OWES_PLATFORM', paymentState: 'PAID'),
        isFalse,
        reason: '只看 PAID 会把商家欠平台的那笔说成「已打款给你」,正好说反',
      );
    });
  });

  group('★★★ 核销详情(order-detail,与台账**不是同一张表**)', () {
    test('★★ 同一状态在两页说法不同 —— 合并任一条必有一页对不上原文', () {
      // 台账:「待主题结算」/「待结算」;详情页只有一种说法。
      expect(
        financeRedemptionStateText(displayState: 'PENDING_SETTLEMENT'),
        '随主题结算发放至个人账户',
      );
      expect(financeStateText(displayState: 'PENDING_SETTLEMENT'), '待结算');
      // 台账的 LEDGER_ERROR 说「已上报」(安抚);详情的说「请联系客服」(要动作)。
      expect(
        financeRedemptionStateText(displayState: 'LEDGER_ERROR'),
        '结算数据对不上，请联系客服',
      );
    });

    test('★ 已结算按结算路径分「平台已打款」/「已入个人账户」', () {
      expect(
        financeRedemptionStateText(
            displayState: 'SETTLED', settlementRoute: 'CHAPTER_OFFER'),
        '平台已打款',
      );
      expect(
        financeRedemptionStateText(
            displayState: 'SETTLED', settlementRoute: 'COOP_ORDER'),
        '已入个人账户',
      );
    });

    test('★★ 零现金:有原因说原因,没原因说事实', () {
      expect(
        financeRedemptionStateText(
            displayState: 'NO_CASH_SETTLEMENT', noCashReason: '平台补贴场次'),
        '平台补贴场次',
      );
      expect(
        financeRedemptionStateText(displayState: 'NO_CASH_SETTLEMENT'),
        '本次不产生现金结算',
      );
    });

    test('★★★ 脱敏时不查资金表 —— 说履约事实,不说「状态待确认」', () {
      expect(financeFulfillmentStateText('ACTIVE'), '核销有效');
      expect(financeFulfillmentStateText('REVERSED'), '核销已撤销');
      expect(financeFulfillmentStateText(null), '核销状态待确认');
    });
  });

  group('★★★ 核销详情的结算进度时间线', () {
    List<BatchTimelineNode> t({
      String? state,
      String? route = 'CHAPTER_OFFER',
      String? at,
      String? paidAt,
    }) =>
        redemptionTimeline(
          settlementState: state,
          settlementRoute: route,
          occurredAt: at,
          paidAt: paidAt,
        );

    test('★★ 只有章节供给才画这条线', () {
      expect(redemptionTimeline(
              settlementState: 'SETTLED', settlementRoute: 'COOP_ORDER'),
          isEmpty);
      expect(redemptionTimeline(settlementState: 'SETTLED', settlementRoute: null),
          isEmpty);
    });

    test('★★★ 只有服务端真给过时间的节点才有日期 —— 「预计打款日」是假承诺', () {
      final List<BatchTimelineNode> nodes =
          t(state: 'PENDING', at: '2026-09-01 12:30:45');
      expect(nodes.first.at, '2026-09-01 12:30', reason: '秒级串截到分钟');
      // 中间两步是**本页的推论**,不是服务端事件 —— 永远不带日期。
      expect(nodes[1].at, isNull);
      expect(nodes[2].at, isNull);
      expect(nodes.last.at, isNull, reason: '还没打款,这条线不许出现任何日期');
    });

    test('★★★ 进度按**业务事实**看,不看有没有时间戳', () {
      expect(t(state: 'PENDING').map((BatchTimelineNode n) => n.state),
          <String>['done', 'now', 'todo', 'todo']);
      for (final String s in <String>['SETTLED', 'ADJUSTED', 'ADJUSTMENT_PENDING']) {
        expect(t(state: s).map((BatchTimelineNode n) => n.state),
            <String>['done', 'done', 'done', 'done'],
            reason: '流程已到头的状态不许留一个空心环 —— 那会被读成「在办」');
      }
      // NOT_APPLICABLE / ERROR:核销发生过,但后面不会再推进。
      expect(t(state: 'NOT_APPLICABLE').map((BatchTimelineNode n) => n.state),
          <String>['done', 'todo', 'todo', 'todo']);
    });

    test('★★ 徽标语义色:只有明确异常才染红', () {
      expect(
          financeStateVariant(
              canReadFinance: true, displayState: 'ADJUSTMENT_PENDING'),
          'danger');
      expect(
          financeStateVariant(canReadFinance: true, displayState: 'LEDGER_ERROR'),
          'danger');
      expect(
          financeStateVariant(canReadFinance: true, displayState: 'SETTLED'),
          'success');
      // 零现金/已调整/已撤销都是说完就完的中性事实。
      expect(
          financeStateVariant(
              canReadFinance: true, displayState: 'NO_CASH_SETTLEMENT'),
          'neutral');
      // 脱敏时看履约态。
      expect(
          financeStateVariant(
              canReadFinance: false, fulfillmentState: 'ACTIVE'),
          'success');
      expect(
          financeStateVariant(canReadFinance: false, fulfillmentState: 'REVERSED'),
          'neutral');
    });
  });
}
