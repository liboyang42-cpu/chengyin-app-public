import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_filter_sheet.dart';
import 'package:chengyin_app/core/widgets/cy_cupertino_range_slider.dart';
import 'package:chengyin_app/core/widgets/cy_tabs.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SearchFilterHost extends ConsumerStatefulWidget {
  const _SearchFilterHost({this.withMerchantFields = true});

  final bool withMerchantFields;

  @override
  ConsumerState<_SearchFilterHost> createState() => _SearchFilterHostState();
}

class _SearchFilterHostState extends ConsumerState<_SearchFilterHost> {
  int searches = 0;
  String merchantTag = '';
  String merchantCityRole = '';

  @override
  Widget build(BuildContext context) {
    final SearchFilter filter = ref.watch(searchFilterProvider);
    return Scaffold(
      body: Column(
        children: <Widget>[
          CupertinoButton(
            onPressed: () => showSearchFilterSheet(
              context,
              ref,
              initialMerchantTag: merchantTag,
              initialMerchantCityRole: merchantCityRole,
              onMerchantFieldsChanged: widget.withMerchantFields
                  ? (String tag, String cityRole) {
                      setState(() {
                        merchantTag = tag;
                        merchantCityRole = cityRole;
                      });
                    }
                  : null,
              onSearch: () => setState(() => searches += 1),
            ),
            child: const Text('打开筛选'),
          ),
          Text('sort:${filter.sortType};searches:$searches'),
          Text('date:${filter.dateRange != null}'),
          Text('merchant:$merchantTag;$merchantCityRole'),
        ],
      ),
    );
  }
}

void main() {
  test('默认“最近”不误报为额外筛选，只有“最热”才标记改变排序', () {
    expect(const SearchFilter().hasAdvanced, isFalse);
    expect(const SearchFilter(sortType: 2).hasAdvanced, isTrue);
  });

  Future<void> open(
    WidgetTester tester, {
    bool withMerchantFields = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _SearchFilterHost(withMerchantFields: withMerchantFields),
        ),
      ),
    );
    await tester.tap(find.text('打开筛选'));
    await tester.pumpAndSettle();
  }

  testWidgets('高级筛选用可滚动 Cupertino sheet 且字段顺序不变', (WidgetTester tester) async {
    await open(tester);

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    // 排序分段走共用件(手册 §6 P3):iOS 26+ 系统分段,旧系统回退 Cupertino。
    expect(find.byType(CyTabs), findsOneWidget);
    expect(find.byType(CyCupertinoRangeSlider), findsOneWidget);
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('高级筛选'), findsOneWidget);

    final double merchantY = tester.getTopLeft(find.text('商家发现')).dy;
    final double dateY = tester.getTopLeft(find.text('日期区间')).dy;
    final double priceY = tester.getTopLeft(find.text('价格区间')).dy;
    final double sortY = tester.getTopLeft(find.text('排序')).dy;
    expect(merchantY, lessThan(dateY));
    expect(dateY, lessThan(priceY));
    expect(priceY, lessThan(sortY));
  });

  testWidgets('普通搜索入口不传商家回调时保持原有筛选结构', (WidgetTester tester) async {
    await open(tester, withMerchantFields: false);

    expect(find.text('商家发现'), findsNothing);
    expect(find.byKey(const Key('search-filter-merchant-tag')), findsNothing);
    expect(
      find.byKey(const Key('search-filter-merchant-city-role')),
      findsNothing,
    );
    expect(find.text('日期区间'), findsOneWidget);
    expect(find.text('价格区间'), findsOneWidget);
    expect(find.text('排序'), findsOneWidget);
  });

  testWidgets('地图筛选用 Cupertino 文本框接入探索标签和城市角色', (WidgetTester tester) async {
    await open(tester);

    final Finder tag = find.byKey(const Key('search-filter-merchant-tag'));
    final Finder cityRole = find.byKey(
      const Key('search-filter-merchant-city-role'),
    );
    expect(tag, findsOneWidget);
    expect(cityRole, findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));

    await tester.enterText(tag, '  宠物友好  ');
    await tester.enterText(cityRole, '  街区客厅  ');
    await tester.ensureVisible(find.byKey(const Key('search-filter-apply')));
    await tester.tap(find.byKey(const Key('search-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('merchant:宠物友好;街区客厅'), findsOneWidget);
    expect(find.text('sort:1;searches:1'), findsOneWidget);
  });

  testWidgets('地图商家字段输入即保留，关闭再打开不丢失', (WidgetTester tester) async {
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('search-filter-merchant-tag')),
      '宠物友好',
    );
    await tester.enterText(
      find.byKey(const Key('search-filter-merchant-city-role')),
      '街区客厅',
    );
    await tester.tap(find.byKey(const Key('search-filter-close')));
    await tester.pumpAndSettle();

    expect(find.text('merchant:宠物友好;街区客厅'), findsOneWidget);
    expect(find.text('sort:1;searches:0'), findsOneWidget);
    await tester.tap(find.text('打开筛选'));
    await tester.pumpAndSettle();
    final CupertinoTextField tag = tester.widget(
      find.byKey(const Key('search-filter-merchant-tag')),
    );
    final CupertinoTextField cityRole = tester.widget(
      find.byKey(const Key('search-filter-merchant-city-role')),
    );
    expect(tag.controller?.text, '宠物友好');
    expect(cityRole.controller?.text, '街区客厅');
  });

  testWidgets('双端价格保留 44pt 命中区并支持 200% 字号', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: MaterialApp(home: _SearchFilterHost()),
        ),
      ),
    );
    await tester.tap(find.text('打开筛选'));
    await tester.pumpAndSettle();

    final Finder slider = find.byType(CyCupertinoRangeSlider);
    expect(tester.getSize(slider).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('排序逐字对齐小程序最近与最热，并保持 44pt 主动作', (WidgetTester tester) async {
    await open(tester);

    expect(find.text('最近'), findsOneWidget);
    expect(find.text('最热'), findsOneWidget);
    expect(find.text('距离(需定位)'), findsNothing);
    expect(find.text('距离排序暂不可用(未接入定位)'), findsNothing);
    // 顺序锁死「最近 → 最热」(小程序原文),点「最热」才改排序类型。
    expect(
      tester
          .widget<CyTabs>(find.byType(CyTabs))
          .tabs
          .map((CyTab tab) => tab.label),
      orderedEquals(<String>['最近', '最热']),
    );
    await tester.tap(find.text('最热'));
    await tester.pump();

    final Finder apply = find.byKey(const Key('search-filter-apply'));
    expect(tester.getSize(apply).height, greaterThanOrEqualTo(44));
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('sort:2;searches:1'), findsOneWidget);
  });

  testWidgets('日期入口使用 Cupertino 日期选择，关闭不应用', (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('search-filter-date')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPopupSurface), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('开始日期'), findsOneWidget);
    final CupertinoDatePicker picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    final DateTime now = DateTime.now();
    expect(picker.minimumDate, DateTime(now.year - 1));
    expect(picker.maximumDate, DateTime(now.year + 2, 12, 31));
    await tester.tap(find.byKey(const Key('cy-native-picker-cancel')));
    await tester.pumpAndSettle();

    final Finder close = find.byKey(const Key('search-filter-close'));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('sort:1;searches:0'), findsOneWidget);
  });

  testWidgets('日期完成后仍要等主动作应用，不偷改 provider', (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('search-filter-date')));
    await tester.pumpAndSettle();
    expect(find.text('开始日期'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cy-native-picker-done')));
    await tester.pumpAndSettle();
    expect(find.text('结束日期'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cy-native-picker-done')));
    await tester.pumpAndSettle();
    expect(find.text('date:false'), findsOneWidget);

    final Finder apply = find.byKey(const Key('search-filter-apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('date:true'), findsOneWidget);
    expect(find.text('sort:1;searches:1'), findsOneWidget);
  });
}
