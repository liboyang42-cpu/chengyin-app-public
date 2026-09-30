// 门禁:创建域(主题编辑器)的每条路由都必须包 `_topicEditorLight(...)`。
//
// 为什么需要:小程序把创建域的页面根节点套 `.theme-topic-editor`(浅色档)——2026-09-17
// 快照实测是 `pages/publish/{fabu,temp,templateadd,template-intro,activity,simple}`;
// App 侧唯一的浅色手段就是「路由外层包一个 Theme」。而「包一层」是**很容易在新增路由时
// 漏掉**的动作:漏了不报错、不抛异常,只是那一页悄悄变回黑底,和相邻创建页对不上
// (决策 D10⑥ + D6③「主题编辑器=浅色」)。这类「少做一步就静默错」的地方必须有门禁。
//
// ⚠️ `pages/merchant/citynode/create` 同样挂 `.theme-topic-editor`,但它已在
//    `_merchantLight` 那条恒浅链上(那条链归 merchant_routes_are_light_test 管),不在这里重复。
//
// 负控:把任意一条创建域路由的 `_topicEditorLight(` 去掉,本测试必须红。
//
// ⚠️ 扫之前先剥注释(test/support/source_text.dart):门禁的注释里**必然**出现被禁
//    写法的名字(注释正是在解释"这里为什么包/为什么不包"),照全文扫会把写了说明
//    当成犯了错 —— 本仓已有两条门禁栽在这上面,所以剥注释是惯例不是洁癖。

import 'dart:io';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

/// 应渲成浅色的创建域路由。判据 = 小程序对应页根节点挂 `.theme-topic-editor`。
const List<String> _kTopicEditorRoutes = <String>[
  '/publish',
  '/publish/pro',
  '/publish/activity',
  '/template/new',
  '/template/edit',
  '/template/intro',
];

void main() {
  test('所有创建域路由都包了 _topicEditorLight', () {
    const String path = 'lib/core/router/app_router.dart';
    expect(File(path).existsSync(), isTrue, reason: '路由表找不到了,门禁形同虚设');
    final List<String> lines = codeOf(path).split('\n');

    final List<String> offenders = <String>[];
    final List<String> missing = <String>[];
    int checked = 0;
    for (final String route in _kTopicEditorRoutes) {
      // 精确匹配整条 path(不能用前缀包含:`/publish` 会撞上 `/publish/pro`、
      // `/publish/poi` —— 那样扫到的是别人的路由,门禁看着绿其实没判)。
      final RegExp pathLine = RegExp("path: '${RegExp.escape(route)}'");
      int index = -1;
      for (int i = 0; i < lines.length; i++) {
        if (pathLine.hasMatch(lines[i])) {
          index = i;
          break;
        }
      }
      if (index < 0) {
        missing.add(route);
        continue;
      }

      // builder / pageBuilder 有单行箭头式与多行式两种,两种都要判 ——
      // 只认单行会让多行那几条**静默漏检**。
      final StringBuffer body = StringBuffer();
      for (int j = index; j < lines.length && j < index + 16; j++) {
        if (j > index && lines[j].contains("path: '")) break; // 进了下一条路由
        body.writeln(lines[j]);
      }
      checked++;
      final String text = body.toString();
      // `pageBuilder:` 里是大写 B,别只认小写的 `builder:` —— 只认一种会让
      // 用 pageBuilder 的那几条**静默漏检**(本门禁第一版就是这么错的)。
      if (!text.contains('builder:') && !text.contains('pageBuilder:')) {
        offenders.add('$route —— 找不到 builder,无法判定');
      } else if (!text.contains('_topicEditorLight(')) {
        offenders.add('$route —— builder 没包 _topicEditorLight()');
      }
      // ★ 用错包装比不包更隐蔽:主题编辑器是恒浅,但用 `_merchantLightIfMerchant`
      //   会让玩家视角的创建页掉回黑底(builder 里"看起来包了")。
      if (text.contains('_merchantLightIfMerchant(')) {
        offenders.add('$route —— 用成了条件浅色,玩家视角会掉回黑底');
      }
    }

    // ★ 没有这两条,整个门禁在路由改名/重构后会变成「零条待检、恒绿」。
    expect(missing, isEmpty, reason: '路由表里找不到这些路径(改名了就把表一起改):$missing');
    expect(
      checked,
      _kTopicEditorRoutes.length,
      reason: '只扫到 $checked 条,应为 ${_kTopicEditorRoutes.length} 条 —— 别让门禁静默少检',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          '这些创建域路由会渲成黑底,与小程序 `.theme-topic-editor` 不一致:\n'
          '${offenders.join('\n')}',
    );
  });

  // ★ 卡片**起层手段** —— 这条是渲染回读,不是源码扫描。
  //
  // 真源把「卡怎么从页底里立起来」写成一条**二选一**规范(tokens.wxss:980-986):
  //   「投影与描边同时出现 = 一张卡两条外沿 … 本域选投影,所以描边必须同步关掉;
  //    白底细线域(theme-topic-editor)则相反 —— 那边零投影、留描边。」
  // 于是:创建域 = 零投影 + 细线;商家域 = 投影 + 无描边。
  //
  // 2026-09-17 之前 `_topicEditorLight` 直接复用 `merchantLight()`,创建域的卡
  // 就带上了商家那档 `rgba(15,23,43,.48)` 投影,而且一条描边都没有 —— 与真源
  // **正好相反**。这类偏差不报错、不抛异常、单测全绿,只有读渲染结果才看得见。
  //
  // 负控:把 `topicEditorLight()` 里的 `cardShadow: const <BoxShadow>[]` 去掉,
  //   第一条 elevation 断言必须红。
  testWidgets('创建域的卡 = 零投影 + 细线(渲染回读)', (WidgetTester tester) async {
    final Material card = await _cardUnder(tester, AppTheme.topicEditorLight());
    expect(card.elevation, 0, reason: '创建域的卡不许有投影(真源 --cy-shadow-card: none)');
    final RoundedRectangleBorder shape = card.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 1, reason: '创建域靠**描边**起层;投影与描边两条外沿都缺席,卡就贴死在页底上');
    expect(
      shape.side.color,
      const Color(0xFFE8E8E8),
      reason:
          '.cy-card 的描边读 --cy-border-card = --cy-color-border-subtle = #E8E8E8',
    );

    // 浅色没被改回暗色:页底/白卡/系统语义色的 brightness 与真源同值。
    final ThemeData topic = AppTheme.topicEditorLight();
    expect(
      topic.scaffoldBackgroundColor,
      const Color(0xFFF3F4F4),
      reason: '创建域页底 #F3F4F4,与白卡差 12 级才看得出卡',
    );
    expect(topic.cardTheme.color, const Color(0xFFFFFFFF));
    expect(
      topic.cupertinoOverrideTheme?.brightness,
      Brightness.light,
      reason: 'iOS 13+ 的系统语义色(分隔线/placeholder)按这个 brightness 解析',
    );
  });

  // ⚠️ 商家这条**必须单独一个 testWidgets**:同一个用例里连着 pump 两个不同的
  //   `MaterialApp(theme:)`,`Card` 会读到**上一个** theme 的 cardTheme
  //   (2026-09-17 实测:merchant 的 elevation 被读成 0,而它真值是 2)——
  //   挤在一条里,断言就会**看着绿其实没判**。一个 theme 一个用例,一次 pump。
  testWidgets('商家域的卡保持投影 + 无描边(别把商家那套改坏)', (WidgetTester tester) async {
    final Material card = await _cardUnder(tester, AppTheme.merchantLight());
    expect(card.elevation, greaterThan(0), reason: '商家域靠投影起层(tokens.wxss:985)');
    final RoundedRectangleBorder shape = card.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 0, reason: '商家域「投影与描边二选一」,描边必须同步关掉,否则一张卡两条外沿');
  });

  // ★★ 只挂 Material `Theme` **换不动 CupertinoTheme** —— 2026-09-18 实测:
  //   只要祖先里已经有一层 `CupertinoTheme`(真机上就是 main.dart 的 `CupertinoApp`),
  //   Material `Theme` 就**继承那一层**(flutter `material/theme.dart`
  //   `_inheritedCupertinoThemeData`:有祖先就不看自己的 `data`),它自己的
  //   `cupertinoOverrideTheme` 形同虚设。
  //   实测现象:嵌套 `Theme(topicEditorLight())` 下 `CyPalette.of().bgPage` 已是浅色
  //   #F3F4F4,但 `CupertinoTheme.brightnessOf()` 仍是 **dark**、
  //   `scaffoldBackgroundColor` 仍是**纯黑** —— 创建域的 `CupertinoPageScaffold` 默认底、
  //   导航栏、`CupertinoTextField` 文字色于是全取暗色值,`/publish/pro` 就是「黑底 + 黑字」。
  //
  //   所以恒浅包装必须自己再挂一层 `CupertinoTheme`;下面两条守住它:
  //   ① 静态:包装里必须有 `CupertinoTheme(`(负控:删掉它,①必须红);
  //   ② 负控:证明「只挂 Material Theme」真的不够(Flutter 哪天改了这个继承顺序,②会红 ——
  //      那时才可以把包装里的 CupertinoTheme 去掉)。
  test('恒浅包装必须自己挂 CupertinoTheme(只挂 Material Theme 换不动它)', () {
    final String source = codeOf('lib/core/router/app_router.dart');
    // main 侧把「Material `Theme` + `CupertinoTheme` 一起挂」抽成了共用助手,
    // 创建域与商家域都委托给它 —— 那层 CupertinoTheme 现在住在 `_lightScope` 里,
    // 判据跟着委托走(只看 `_topicEditorLight` 的就地展开会漏掉真正挂它的那层)。
    final int start = source.indexOf('Widget _lightScope(');
    expect(start, greaterThan(-1), reason: '找不到 _lightScope,门禁形同虚设');
    // 注释被剥掉后文件变短,窗口要夹一下,否则 substring 会 RangeError。
    final String body = source.substring(start, (start + 1500).clamp(0, source.length));
    expect(
      body.contains('CupertinoTheme('),
      isTrue,
      reason: '只挂 Material `Theme` 时,创建域里的 Cupertino 控件仍取暗色值(实测黑底黑字)',
    );
    expect(
      source.contains('_lightScope(AppTheme.topicEditorLight()'),
      isTrue,
      reason: '_topicEditorLight 必须继续走这层 —— 自己另起一份就不受本门禁保护',
    );
  });

  testWidgets('负控:祖先有 CupertinoTheme 时,只挂 Material Theme 仍然读出暗色', (
    WidgetTester tester,
  ) async {
    late Brightness brightness;
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (BuildContext context) => Theme(
            data: AppTheme.topicEditorLight(),
            child: Builder(
              builder: (BuildContext inner) {
                brightness = CupertinoTheme.brightnessOf(inner);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      brightness,
      Brightness.dark,
      reason: '这条是**负控**:它红说明 Flutter 改成「Material Theme 能覆盖祖先 Cupertino 主题」了,'
          '那时才可以把 _topicEditorLight 里那层 CupertinoTheme 去掉',
    );
  });

  // ★ 与 merchant_routes_are_light_test 的同名守卫同源。
  //   2026-09-18 复核实测:`/publish`、`/publish/pro` 两张基准图**就是暗色**(用的
  //   `goldenTheme()`),而这两页在真机上恒浅 —— 基准图肉眼看着"绿",画的却是用户
  //   看不到的画面(假证据)。已改用 `topicEditorGoldenTheme()`,这条守住不再回退。
  test('★★ 创建域的 golden 必须用浅色主题拍 —— 深色版是没人会看到的画面', () {
    final RegExp topicEditorPage = RegExp(
      r'const\s+(PublishPage|PublishProPage|PublishActivityPage)\(',
    );
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e
        in Directory('test/golden').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('_test.dart')) continue;
      // 剥注释:只在注释里提过页名的文件不算「渲染了这页」。
      final String src = codeOf(e.path);
      if (!topicEditorPage.hasMatch(src)) continue;
      if (!src.contains('topicEditorGoldenTheme')) offenders.add(e.path);
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些 golden 渲染了创建域页面却没用 topicEditorGoldenTheme —— '
          '拍出来的黑底是用户看不到的画面,基准图会变成假证据:\n${offenders.join('\n')}',
    );
  });
}

/// 在给定主题下渲一张 `Card`,回读它**实际**的投影与描边。
Future<Material> _cardUnder(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Scaffold(body: Card(child: Text('卡'))),
    ),
  );
  return tester.widget<Material>(
    find
        .descendant(of: find.byType(Card), matching: find.byType(Material))
        .first,
  );
}
