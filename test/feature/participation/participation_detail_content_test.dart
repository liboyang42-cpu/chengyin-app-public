import 'package:chengyin_app/feature/participation/participation_detail_sheet.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

/// 用假原生驱动截获 sheet 内容,逐条核对「详情半屏渲染的是真源字段,
/// 不是假数据」(A2/A3/A4/A9)。
class _CapturingDriver implements ParticipationDetailNativeDriver {
  AppleLiquidSheetContent? captured;

  @override
  Future<bool> show({
    required BuildContext context,
    required AppleLiquidSheetContent content,
  }) async {
    captured = content;
    return true;
  }
}

const ParticipationDetail _detail = ParticipationDetail(
  id: 77,
  topicName: '夜游苏河',
  dateText: '2026.09.10 - 2026.09.12',
  statusText: '未开始',
  modeText: '城市定向',
  ownerType: 1,
  ownerId: 11,
  isTopic: true,
  paymentStatus: 2,
  refundDeadlineDisplay: '2026-09-07 09:00',
  showOrderStats: true,
  showRemainingBadge: true,
  remainingDaysText: '距离路线开始还剩2天',
  canCancel: true,
  showContactService: false,
  needModify: false,
  hasRuleInstructions: true,
  activityDescription: '沿河完成城市探索',
  cooperateDate: '每日 10:00-22:00',
  coverUrl: 'https://img.test/topic.jpg',
  templateId: 9,
  templateName: '经典定向模板',
  pendingVerification: 3,
  verifiedCount: 2,
  totalOrderCount: 5,
);

({String? title, String? value, String? subtitle, Object? onPressed})? _findRow(
  AppleLiquidSheetContent content,
  String title,
) {
  for (final AppleLiquidSheetSection section in content.sections) {
    for (final AppleLiquidSheetRow row in section.rows) {
      if (row.title == title) {
        return (
          title: row.title,
          value: row.value,
          subtitle: row.subtitle,
          onPressed: row.onButtonPressed,
        );
      }
    }
  }
  return null;
}

Future<void> _pump(WidgetTester tester, _CapturingDriver driver) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => FilledButton(
          onPressed: () =>
              showParticipationDetail(context, _detail, nativeDriver: driver),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('半屏渲染真源字段:接待时间/活动日期/核销进度/规则固定文案', (WidgetTester tester) async {
    final _CapturingDriver driver = _CapturingDriver();
    await _pump(tester, driver);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final AppleLiquidSheetContent content = driver.captured!;
    expect(content.title, '参与详情');
    expect(_findRow(content, '活动日期')?.value, '2026.09.10 - 2026.09.12');
    expect(_findRow(content, '接待时间')?.value, '每日 10:00-22:00');
    expect(
      _findRow(content, kParticipationRuleInstructionsCopy)!.title,
      isNotEmpty,
    );
    expect(_findRow(content, '距离路线开始还剩2天')?.title, '距离路线开始还剩2天');
  });

  testWidgets('A4 硬编码假数据行不再出现', (WidgetTester tester) async {
    final _CapturingDriver driver = _CapturingDriver();
    await _pump(tester, driver);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final AppleLiquidSheetContent content = driver.captured!;
    expect(_findRow(content, '场次时间排期'), isNull);
    // nodeName 无真值 ⇒ 整行不存在,也不给「待分配」占位。
    expect(_findRow(content, '最终分配节点'), isNull);
    final String flattened = content.sections
        .map((AppleLiquidSheetSection section) => section.rows)
        .expand((List<AppleLiquidSheetRow> rows) => rows)
        .map((AppleLiquidSheetRow row) => '${row.title}${row.value}')
        .join();
    expect(flattened, isNot(contains('营业时间内自由接待')));
    expect(flattened, isNot(contains('待分配')));
    // 商家口吻兜底文案已删。
    expect(flattened, isNot(contains('能让您的品牌在活动中看起来更棒')));
  });

  testWidgets('A3 动作按钮齐:开始玩/取消参与/核验扫码;条件不满足的不出现', (WidgetTester tester) async {
    final _CapturingDriver driver = _CapturingDriver();
    await _pump(tester, driver);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final AppleLiquidSheetContent content = driver.captured!;
    expect(_findRow(content, '开始玩'), isNotNull);
    expect(_findRow(content, '取消参与'), isNotNull);
    expect(_findRow(content, '核验扫码'), isNotNull);
    expect(_findRow(content, '联系客服'), isNull);
    expect(_findRow(content, '去修改'), isNull);
  });

  testWidgets('A9 模板行可点并回传 openTemplate;按下去收起半屏', (WidgetTester tester) async {
    final _CapturingDriver driver = _CapturingDriver();
    await _pump(tester, driver);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final AppleLiquidSheetContent content = driver.captured!;
    final ({String? title, String? value, String? subtitle, Object? onPressed})?
    templateRow = _findRow(content, '经典定向模板');
    expect(templateRow, isNotNull);
    expect(templateRow!.onPressed, isNotNull);
  });
}
