import 'dart:ui' show Tristate;

import 'package:chengyin_app/core/widgets/cy_cupertino_range_slider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('双端值保持顺序且拖动不改变 44pt 几何', (WidgetTester tester) async {
    RangeValues values = const RangeValues(20, 80);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Center(
                child: SizedBox(
                  width: 300,
                  child: CyCupertinoRangeSlider(
                    values: values,
                    min: 0,
                    max: 100,
                    divisions: 10,
                    startSemanticLabel: '最低价格',
                    endSemanticLabel: '最高价格',
                    onChanged: (RangeValues next) =>
                        setState(() => values = next),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final Finder slider = find.byType(CyCupertinoRangeSlider);
    expect(tester.getSize(slider).height, 44);
    await tester.dragFrom(tester.getCenter(slider), const Offset(70, 0));
    await tester.pump();
    expect(values.start, lessThanOrEqualTo(values.end));
    expect(values.start % 10, 0);
    expect(values.end % 10, 0);
  });

  testWidgets('VoiceOver 分别调整两个滑块且禁用态不可操作', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    RangeValues values = const RangeValues(20, 80);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: CyCupertinoRangeSlider(
            values: values,
            min: 0,
            max: 100,
            divisions: 10,
            startSemanticLabel: '最低价格',
            endSemanticLabel: '最高价格',
            semanticFormatter: (double value) => '¥${value.toStringAsFixed(0)}',
            onChanged: (RangeValues next) => values = next,
          ),
        ),
      ),
    );

    final SemanticsNode start = tester.getSemantics(
      find.bySemanticsLabel('最低价格'),
    );
    final SemanticsNode end = tester.getSemantics(
      find.bySemanticsLabel('最高价格'),
    );
    expect(start.flagsCollection.isSlider, isTrue);
    expect(start.value, '¥20');
    expect(
      start.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(end.flagsCollection.isSlider, isTrue);
    expect(end.value, '¥80');

    tester.semantics.increase(find.semantics.byLabel('最低价格'));
    await tester.pump();
    expect(values.start, 30);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: CyCupertinoRangeSlider(
            values: const RangeValues(20, 80),
            min: 0,
            max: 100,
            startSemanticLabel: '最低价格',
            endSemanticLabel: '最高价格',
          ),
        ),
      ),
    );
    final SemanticsNode disabled = tester.getSemantics(
      find.bySemanticsLabel('最低价格'),
    );
    expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
    expect(
      disabled.getSemanticsData().hasAction(SemanticsAction.increase),
      isFalse,
    );
    handle.dispose();
  });
}
