import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/template_draft.dart';
import 'package:chengyin_app/feature/template/template_edit_page.dart';

class _CategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async => const <Category>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 一直失败:验证失败态本身(不给重试入口就等于没有出路)。
class _FailingCategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async =>
      throw Exception('网络开了点小差');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 失败直到测试放行:验证「重试真的能回来」。
class _RecoverableCategoryApi implements CategoryApi {
  bool failing = true;
  int calls = 0;

  @override
  Future<List<Category>> list({String? type}) async {
    calls += 1;
    if (failing) throw Exception('网络开了点小差');
    return <Category>[Category(id: 7, name: '夜跑')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {CategoryApi? api}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  await tester.pumpWidget(
    ProviderScope(
      // ★ 必须跟 main.dart 同一条重试策略:Riverpod 3 默认会把任何 Exception
      //   重试 10 次,重试期间 AsyncValue 停在 AsyncLoading —— 不覆盖的话
      //   这一屏的失败态要三十多秒才出得来,测试里就是永远转圈。
      retry: chengyinRetry,
      overrides: <dynamic>[
        categoryApiProvider.overrideWithValue(api ?? _CategoryApi()),
      ].cast(),
      child: const MaterialApp(home: TemplateEditPage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _scrollToCategories(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('玩法类别 *'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _pumpSeed(WidgetTester tester, TemplateDraft seed) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        categoryApiProvider.overrideWithValue(_CategoryApi()),
      ].cast(),
      child: MaterialApp(home: TemplateEditPage(seed: seed)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('编辑器 D4 保留小程序页面身份与基本信息顺序', (tester) async {
    await _pump(tester);
    expect(find.text('创建节点玩法'), findsWidgets);
    expect(find.text('完善以下内容，为路线打造可落地的现场互动方案'), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.byKey(const Key('template-field-players')), findsOneWidget);
    expect(find.byKey(const Key('template-field-rules')), findsOneWidget);
  });

  testWidgets('temp 模块顺序与选项 2 到 4 的入口数不缩水', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('template-validation-method')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('完成方式'), findsWidgets);
    expect(find.text('完成奖励'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('剧情故事'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('剧情故事'), findsOneWidget);
    expect(find.text('语音讲解'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('template-validation-method')),
      -400,
      scrollable: find.byType(Scrollable).first,
    );

    // 页面里现在有两处「选项问答」:旧 validationMethod 选择器 + 新玩法配置器目录。
    // 这条用例测的是旧选择器,故把 tap 限定到它的容器 key 内。
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('template-validation-method')),
        matching: find.text('选项问答'),
      ),
    );
    await tester.pump();
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);
    expect(find.text('选项 C'), findsNothing);
    expect(find.byKey(const Key('template-add-choice')), findsOneWidget);

    await tester.tap(find.byKey(const Key('template-add-choice')));
    await tester.pump();
    expect(find.text('选项 C'), findsOneWidget);
  });

  testWidgets('E19 标签:剧情节点给配图提示与计数,题干音频配好后叫「已配音频」', (tester) async {
    await _pumpSeed(
      tester,
      const TemplateDraft(
        title: '夜色寻宝',
        validationMethod: 1,
        questionAudio: 'x.mp3',
        storyEnabled: true,
      ),
    );

    await tester.scrollUntilVisible(
      find.text('配图(选填,最多6张)'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('配图(选填,最多6张)'), findsOneWidget);
    expect(find.text('0/6'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('已配音频'),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('已配音频'), findsOneWidget);
  });

  testWidgets('★★ 类别为空/没拉出来:给「暂无可选分类」与重试(照真源 cy-category-sheet)', (
    tester,
  ) async {
    await _pump(tester);
    await _scrollToCategories(tester);

    // 真源 components/cy/category-sheet/index.wxml:
    //   cy-empty title="暂无可选分类" sub="分类没有加载出来，或当前类型下还没有配置分类。" cta="重试"
    expect(find.text('暂无可选分类'), findsOneWidget);
    expect(find.text('分类没有加载出来，或当前类型下还没有配置分类。'), findsOneWidget);
    expect(find.byKey(const Key('template-categories-retry')), findsOneWidget);
  });

  testWidgets('★ 类别接口拉不到:同一处给出重试', (tester) async {
    await _pump(tester, api: _FailingCategoryApi());
    await _scrollToCategories(tester);

    expect(find.text('暂无可选分类'), findsOneWidget);
    expect(find.byKey(const Key('template-categories-retry')), findsOneWidget);
  });

  testWidgets('★ 点重试:能真的把类别拉回来', (tester) async {
    final api = _RecoverableCategoryApi();
    await _pump(tester, api: api);
    await _scrollToCategories(tester);
    expect(find.text('暂无可选分类'), findsOneWidget);

    api.failing = false;
    await tester.tap(find.byKey(const Key('template-categories-retry')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.calls, greaterThanOrEqualTo(2));
    expect(find.text('暂无可选分类'), findsNothing);
    expect(find.text('夜跑'), findsOneWidget);
  });
}
