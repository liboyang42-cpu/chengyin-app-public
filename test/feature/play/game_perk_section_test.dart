import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/game_section.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/perk_section.dart';

void main() {
  testWidgets('★真实态:hasGame=true 但还没到店(gameTitle 被后端摘走)⇒ 整段不渲染', (t) async {
    // 这就是 /api/play/nodes 在「有玩法 + 未扫码」时的真实形状:
    // !arrived 摘 gameTitle/ruleInstructions,却不摘 hasGame,也不摘 duration/players。
    // 按 hasGame 判会渲出一个没标题、没「怎么玩」的孤儿段。
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'arrived': false,
      'duration': 15,
      'players': '1–2 人',
      'difficulty': '轻松',
      'requiredMaterials': '一张纸巾',
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(
      find.textContaining('本站游戏'),
      findsNothing,
      reason: '判据是 gameTitle 非空,不是 hasGame',
    );
    expect(find.textContaining('15 分钟'), findsNothing);
    expect(find.text('需要准备'), findsNothing);
  });

  testWidgets('★没有 gameTitle 就整段不渲染', (t) async {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': false,
      'arrived': true,
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(find.textContaining('本站游戏'), findsNothing);
  });

  // ★ 到店态改成叙事优先:先故事钩子、再一条行动指令;规则折叠进帮助入口,
  //   时长/人数/权益/材料退到次级规格行,不抢主视觉。
  PlayNode narrativeNode() => PlayNode.fromJson(<String, dynamic>{
    'nodeId': 1, 'name': 'x', 'address': '', 'sortId': 1, 'hasGame': true,
    // ★ 叙事是到店态:常态必须 arrived=true、done=false。
    'arrived': true,
    // ★ duration 是后端真实形状:数字(CmsMemberTemplate.duration 是 Long),不带单位。
    'gameTitle': '找一本 1998', 'duration': 15, 'players': '1–2 人',
    'storyText': '店主收唱片二十年,最爱聊六七十年代的爵士。',
    'ruleInstructions': '进店说出一个年份\n找封面是唱片的书\n翻到扉页回答问题',
    'requiredMaterials': '一张纸巾',
  });

  testWidgets('★叙事优先:故事钩子 + 一条行动指令,其余规则默认折叠', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: narrativeNode())),
      ),
    );
    expect(find.text('找一本 1998'), findsOneWidget);
    expect(
      find.text('店主收唱片二十年,最爱聊六七十年代的爵士。'),
      findsOneWidget,
      reason: 'storyText 是叙事钩子,优先展示',
    );
    expect(find.text('进店说出一个年份'), findsOneWidget, reason: '第一条规则就是那一条行动指令');
    expect(find.text('找封面是唱片的书'), findsNothing, reason: '玩法规则折叠到帮助入口');
    expect(find.text('翻到扉页回答问题'), findsNothing);
  });

  testWidgets('★规格信息退到次级行,但仍可读:时长 / 人数 / 材料', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: narrativeNode())),
      ),
    );
    expect(
      find.text('15 分钟'),
      findsOneWidget,
      reason: '后端发的是分钟数,单位由展示层拼 —— 光渲个「15」读不出是什么',
    );
    expect(find.text('1–2 人'), findsOneWidget);
    expect(find.textContaining('一张纸巾'), findsOneWidget);
  });

  testWidgets('★规格行排在故事钩子之下(不抢主视觉的次序证据)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: narrativeNode())),
      ),
    );
    final double hookY = t.getTopLeft(find.text('店主收唱片二十年,最爱聊六七十年代的爵士。')).dy;
    final double specY = t.getTopLeft(find.text('15 分钟')).dy;
    expect(hookY, lessThan(specY), reason: '叙事在前,规格在后');
  });

  testWidgets('★帮助入口展开后露出其余规则', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: narrativeNode())),
      ),
    );
    expect(find.text('怎么玩'), findsOneWidget, reason: '有折叠规则才给帮助入口');
    await t.tap(find.text('怎么玩'));
    await t.pumpAndSettle();
    expect(find.text('找封面是唱片的书'), findsOneWidget);
    expect(find.text('翻到扉页回答问题'), findsOneWidget);
  });

  testWidgets('★折叠入口是标准可访问按钮:44 高、暴露 expanded、不重复子语义', (t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: narrativeNode())),
      ),
    );
    final Finder entry = find.bySemanticsLabel('展开玩法规则');
    expect(entry, findsOneWidget, reason: '入口要有可读的语义 label,不是裸手势');
    expect(
      t
          .getSize(
            find.ancestor(
              of: find.text('怎么玩'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .height,
      greaterThanOrEqualTo(44),
      reason: '44pt 是 iOS HIG / Material 的最小触达尺寸',
    );
    expect(
      t.getSemantics(entry),
      matchesSemantics(
        label: '展开玩法规则',
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
      reason: '收起态要同时暴露「可展开」和「当前未展开」',
    );
    // 子语义被排除:读屏只听到一个节点,不会把「怎么玩」再念一遍。
    expect(
      find.bySemanticsLabel('怎么玩'),
      findsNothing,
      reason: 'ExcludeSemantics 后子级文案不再单独成节点',
    );

    await t.tap(entry);
    await t.pumpAndSettle();
    expect(
      t.getSemantics(find.bySemanticsLabel('收起玩法规则')),
      matchesSemantics(
        label: '收起玩法规则',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('★photoRequireDesc 优先作为行动指令,规则整组折叠', (t) async {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'gameTitle': '城市颜色采样',
      'arrived': true,
      'validationMethod': 2,
      'photoRequireDesc': '拍一张能代表此刻心情的城市细节',
      'ruleInstructions': '打开相机\n对准一处细节',
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(
      find.text('拍一张能代表此刻心情的城市细节'),
      findsOneWidget,
      reason: '拍照任务的行动指令是拍摄要求,不是通用规则',
    );
    expect(find.text('打开相机'), findsNothing, reason: '规则整组折叠');
    await t.tap(find.text('怎么玩'));
    await t.pumpAndSettle();
    expect(find.text('打开相机'), findsOneWidget);
  });

  testWidgets('★storyText 单独存在也渲染(叙事优先)', (t) async {
    final PlayNode storyOnly = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'arrived': true,
      'storyText': '支弄里的墙面会保存很多短暂出现过的生活痕迹。',
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: storyOnly)),
      ),
    );
    expect(find.text('支弄里的墙面会保存很多短暂出现过的生活痕迹。'), findsOneWidget);
  });

  testWidgets('★异常投影反例:arrived=false 即便后端误发 gameTitle/storyText 也整段不渲染', (
    t,
  ) async {
    // 硬闸 node.arrived 先于叙事/gameTitle 判据:后端投影异常时
    // 也绝不把「未到店」的节点渲染成叙事段。
    final PlayNode leaked = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'arrived': false,
      'gameTitle': '猜年代小游戏',
      'storyText': '阿旧收唱片二十年,每一张黑胶背后都藏着一段城市记忆。',
      'ruleInstructions': '店主放一段唱片',
      'duration': 15,
      'players': '1–2 人',
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: leaked)),
      ),
    );
    expect(
      GameSection.visibleFor(leaked),
      isFalse,
      reason: 'arrived 是硬闸,排在 gameTitle/storyText 之前',
    );
    expect(find.textContaining('本站游戏'), findsNothing);
    expect(find.text('猜年代小游戏'), findsNothing);
    expect(find.textContaining('阿旧收唱片'), findsNothing);
    expect(find.textContaining('15 分钟'), findsNothing);
  });

  testWidgets('★duration=0 不渲染时长 —— 「0 分钟」是编出来的信息', (t) async {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': 'x', 'address': '', 'sortId': 1, 'hasGame': true,
      'arrived': true,
      // 后台表单没填时 Long 列常落 0,不是 null。样机两处都是 falsy 判
      // (`n.duration ? … : ''` index.js:2718、`if (node.duration)` index.js:1532),
      // 0 根本不进 meta。
      'gameTitle': '找一本 1998', 'duration': 0, 'players': '1–2 人',
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(find.text('找一本 1998'), findsOneWidget, reason: '段本身要在,否则测的不是这件事');
    expect(find.textContaining('分钟'), findsNothing);
    expect(find.text('1–2 人'), findsOneWidget, reason: '只摘时长,别把整行 meta 一起吞了');
  });

  group('★gameTitle 缺失时按 validationMethod 回落(小程序 normNode,index.js:2717)', () {
    Future<void> pump(WidgetTester t, Map<String, dynamic> extra) async {
      final n = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 1,
        'name': 'x',
        'address': '',
        'sortId': 1,
        'hasGame': true,
        'arrived': true,
        ...extra,
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameSection(node: n)),
        ),
      );
    }

    testWidgets('vm=2 → 拍照任务', (t) async {
      await pump(t, <String, dynamic>{'validationMethod': 2});
      expect(find.text('拍照任务'), findsWidgets);
    });

    testWidgets('vm=4 → 现场打卡 / vm=6 → 生活偏好校准 / 其余非零 → 点位任务', (t) async {
      await pump(t, <String, dynamic>{'validationMethod': 4});
      expect(find.text('现场打卡'), findsWidgets);
      await pump(t, <String, dynamic>{'validationMethod': 6});
      expect(find.text('生活偏好校准'), findsOneWidget);
      await pump(t, <String, dynamic>{'validationMethod': 3});
      expect(find.text('点位任务'), findsOneWidget);
    });

    testWidgets('★vm=2/4 合成标题与类型同名 ⇒ 眉标不再重复类型名', (t) async {
      await pump(t, <String, dynamic>{'validationMethod': 2});
      expect(
        find.text('本站游戏 · 拍照任务'),
        findsNothing,
        reason: '合成标题已经叫「拍照任务」,眉标再缀一遍就是同一句出现两次',
      );
      expect(find.text('本站游戏'), findsOneWidget);
      expect(find.text('拍照任务'), findsOneWidget);

      await pump(t, <String, dynamic>{'validationMethod': 4});
      expect(find.text('本站游戏 · 现场打卡'), findsNothing);
      expect(find.text('本站游戏'), findsOneWidget);
      expect(find.text('现场打卡'), findsOneWidget);
    });

    testWidgets('★后端下发了 gameTitle 就用它,回落不许顶掉真名', (t) async {
      await pump(t, <String, dynamic>{
        'validationMethod': 2,
        'gameTitle': '找一本 1998',
      });
      expect(find.text('找一本 1998'), findsOneWidget);
      expect(
        find.text('拍照任务'),
        findsNothing,
        reason: '眉标那句是「本站游戏 · 拍照任务」,标题位不该再冒出一个裸的类型名',
      );
    });

    testWidgets('★★gameTitle 缺失 + validationMethod 也缺失 ⇒ 整段不渲染', (t) async {
      // 未到店时后端把两个字段一起摘掉(ApiPlayProgressController:703-705),
      // 这时回落成「点位任务」会让未到店凭空长出一个段 —— 正是 P0-1 那个坑。
      await pump(t, <String, dynamic>{'duration': 15, 'players': '1–2 人'});
      expect(find.textContaining('本站游戏'), findsNothing);
      expect(find.text('点位任务'), findsNothing);
    });

    testWidgets('★vm=0(到达即完成)同样不回落 —— 小程序那里 0 是 falsy', (t) async {
      await pump(t, <String, dynamic>{'validationMethod': 0});
      expect(find.textContaining('本站游戏'), findsNothing);
    });
  });

  testWidgets('★眉标带玩法类型,meta 第三件是权益名(不是难度)', (t) async {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'gameTitle': 'g',
      'validationMethod': 2,
      'arrived': true,
      'difficulty': '轻松',
      'perk': <String, dynamic>{'name': '到店赠明信片'},
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(find.text('本站游戏 · 拍照任务'), findsOneWidget);
    expect(find.text('到店赠明信片'), findsOneWidget);
    expect(
      find.textContaining('轻松'),
      findsNothing,
      reason: '样机 meta 是 时长/人数/权益名',
    );
  });

  testWidgets('★怎么玩为空时不留空标题', (t) async {
    final n = PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1,
      'name': 'x',
      'address': '',
      'sortId': 1,
      'hasGame': true,
      'gameTitle': 'g',
      'arrived': true,
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameSection(node: n)),
      ),
    );
    expect(find.text('怎么玩'), findsNothing);
    expect(find.text('需要准备'), findsNothing);
  });

  testWidgets('权益段:名称 + 两条 meta', (t) async {
    // 后端 CoopPerk.validEnd 是 @JsonFormat(pattern="yyyy-MM-dd") 的 Date ⇒ 只发日期。
    const PlayPerk p = PlayPerk(
      name: '到店赠明信片',
      redeemRule: '到店出示核销',
      validEnd: '2026-09-15',
    );
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PerkSection(perk: p)),
      ),
    );
    expect(find.text('到店赠明信片'), findsOneWidget);
    expect(find.text('到店出示核销'), findsOneWidget);
    expect(
      find.textContaining('9/15'),
      findsOneWidget,
      reason: '有效期按中国时区格式化到「月/日」',
    );
  });

  testWidgets('★redeemRule 为空回落「到店出示核销」', (t) async {
    const PlayPerk p = PlayPerk(name: '到店赠明信片');
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PerkSection(perk: p)),
      ),
    );
    expect(
      find.text('到店出示核销'),
      findsOneWidget,
      reason: '样机 index.js:1564 有这条回落 —— 整行不渲染会让权益看着没有兑换方式',
    );
  });

  test('★★ 有效期取中国日历字段,不随设备时区漂', () {
    // 这台开发机是 PDT。用 toLocal() 的话下面第一条会算成 12/30,
    // 基线 png 一度就把 12/30 烤了进去。
    expect(chinaCalendar('2026-12-31T00:00:00Z')!.day, 31);
    expect(chinaCalendar('2026-12-31T00:00:00Z')!.month, 12);
    // 裸串语义就是中国时间(CoopPerk.validEnd 是 @JsonFormat("yyyy-MM-dd")),
    // 字面即日历字段。
    expect(chinaCalendar('2026-09-15')!.day, 15);
    expect(chinaCalendar('2026-09-15 23:59:59')!.day, 15);
    // 中国 12/31 08:00 = UTC 12/31 00:00;美西那一刻还是 12/30,但显示必须是 12/31。
    expect(chinaCalendar('2026-12-30T16:00:00Z')!.day, 31);
    expect(chinaCalendar(null), isNull);
    expect(chinaCalendar('  '), isNull);
    expect(chinaCalendar('不是日期'), isNull);
  });
}
