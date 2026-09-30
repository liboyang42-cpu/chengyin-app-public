import 'package:chengyin_app/core/moderation/report_sheet.dart';
import 'package:chengyin_app/data/models/community_report_reason.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReportHost extends StatefulWidget {
  const _ReportHost();

  @override
  State<_ReportHost> createState() => _ReportHostState();
}

class _ReportHostState extends State<_ReportHost> {
  String? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          CupertinoButton(
            onPressed: () async {
              final String? value = await showReportSheet(
                context,
                targetLabel: '这条动态',
              );
              if (mounted) setState(() => result = value);
            },
            child: const Text('打开举报'),
          ),
          Text(result ?? '未提交'),
        ],
      ),
    );
  }
}

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: _ReportHost()));
    await tester.tap(find.text('打开举报'));
    await tester.pumpAndSettle();
  }

  testWidgets('举报用 Cupertino sheet，原因顺序与文案不变', (WidgetTester tester) async {
    await open(tester);

    const List<String> sourceReasons = <String>[
      '含有违法违规内容',
      '色情低俗',
      '人身攻击或骚扰',
      '虚假信息或欺诈',
      '侵犯他人权益',
      '其他',
    ];

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(
      find.byType(CupertinoRadio<CommunityReportReason>),
      findsNWidgets(6),
    );
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.text('举报这条动态'), findsOneWidget);
    expect(find.textContaining('审核期间该内容仍可能可见'), findsOneWidget);
    expect(kReportReasons, sourceReasons);

    final List<double> rows = sourceReasons
        .map(
          (String reason) =>
              tester.getTopLeft(find.byKey(Key('report-reason-$reason'))).dy,
        )
        .toList();
    expect(rows, orderedEquals(rows.toList()..sort()));
  });

  testWidgets('未选不可提交，选中后返回原始理由', (WidgetTester tester) async {
    await open(tester);

    final Finder submit = find.byKey(const Key('report-submit'));
    expect(tester.widget<CupertinoButton>(submit).onPressed, isNull);

    const String reason = '虚假信息或欺诈';
    await tester.tap(find.byKey(const Key('report-reason-$reason')));
    await tester.pump();
    expect(tester.widget<CupertinoButton>(submit).onPressed, isNotNull);
    expect(tester.getSize(submit).height, greaterThanOrEqualTo(44));

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('显式关闭返回 null，不伪造举报结果', (WidgetTester tester) async {
    await open(tester);
    final Finder close = find.byKey(const Key('report-close'));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('未提交'), findsOneWidget);
  });
}
