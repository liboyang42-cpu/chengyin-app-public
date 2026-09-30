// 门禁:能变成浅色的页面里,不许出现**静态**颜色常量。
//
// 为什么:`CyTokens.bgSurface` / `AppColors.textPrimary` 是编译期常量,永远是暗色那套。
// 页面底色会跟着 Theme 变浅,这些常量不会 —— 于是出现「白底黑卡」「白底白字」,
// 而且**不报错、不抛异常、单测全绿**,只有真去看那一屏才发现。
//
// 实证(2026-08-19,一天内撞三次):
//   ① 商家台账换浅底后,卡片仍是 #0A0A0B 黑块,标题黑底黑字几乎不可见;
//   ② 状态标签底色用 `bgSubtle`(4% 白),叠在白卡上完全消失,只剩一行灰字;
//   ③ 设置页顶部身份卡用 `bgElevated`,商家视角下白页上戳着一张黑卡。
// 三处都是同一个根因,所以值得一道闸而不是三次修。
//
// 允许的例外:状态色(success/danger/warning/info)两端同值,是语义色不是主题色。
//
// 负控:往任意一个受管文件里塞一处 `CyTokens.bgSurface`,本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 受管文件 = 会被浅色主题包住的页面(恒浅 + 条件浅)+ 它们复用的共享组件。
/// ⚠️ 新增浅色路由时**必须往这里加一行**,否则那一页不受这道闸保护。
// ⚠️ 2026-08-19 补记:词表最初漏了 `actionPrimaryBg` 这一类,于是新写的 CyTabs
//    在浅色页上渲出「白底白丸」—— 选中态和未选中态完全看不出差别,而门禁全绿。
//    **词表漏一个词,门禁就是假的**;加新 token 时要回来同步这里。
const List<String> _kLightCapable = <String>[
  'lib/feature/merchant/',
  // `/merchant/coupons`(我发布的券)路由外层是 _merchantLight,文件却在
  // lib/feature/coupon/ 下 —— 不登记就不受这道闸保护。
  'lib/feature/coupon/my_published_coupons_page.dart',
  'lib/feature/coop/',
  'lib/feature/settings/settings_page.dart',
  // 关于页:子路由 2026-09-18 起包了 `_merchantLightIfMerchant`(真源
  // `pages/shezhi/about/index.wxml` 根节点 `{{isMerchantView ? 'theme-merchant'
  // : 'theme-dark'}}`),商家视角会渲成浅色 —— 于是它也必须进这张表。
  'lib/feature/settings/about_page.dart',
  'lib/feature/official/official_inbox_page.dart',
  'lib/feature/official/official_mine_page.dart',
  // ClubPostTile 定义在 club_feed_page,但俱乐部根页商家视角(_merchantLight
  // 同款 merchantLight 作用域)直接复用这张卡 —— 不登记就不受这道闸保护。
  'lib/feature/club/club_feed_page.dart',
  'lib/feature/club/club_list_page.dart',
  'lib/feature/template/template_list_page.dart',
  'lib/feature/template/template_topic_shelf.dart',
  'lib/feature/template/template_detail_page.dart',
  'lib/feature/activity/activity_detail_page.dart',
  // 确认终价 = 恒浅:小程序 `pages/topic/pricing/index.wxml` 根节点 `theme-merchant`
  // (index.wxss 第 1 行 @import merchant-light.wxss),路由侧包 _merchantLight。
  // 这页原来写的是 CyTokens 暗色常量 —— 白底上会渲出黑卡白字,正是本门禁防的坑。
  'lib/feature/topic/topic_pricing_page.dart',
  // 创建域(主题编辑器)= 恒浅:小程序对应页根节点挂 `.theme-topic-editor`,
  // App 侧由 app_router.dart 的 `_topicEditorLight` 包浅色,门禁见
  // topic_editor_routes_are_light_test.dart。D10⑥ + D6③。
  // ⚠️ 不在内的三处(都不是"一整页恒浅",按恒浅扫会判错):
  //   · `publish/poi_pick_page.dart` —— 选址页还被广场发帖、漫游这些**玩家暗色**
  //     入口 push 到(它自己剩的 2 处静态色,正是"不是恒浅"的证明)。
  //   · `publish/publish_image_cropper.dart` —— club 建圈流也在用(club_image_picker)。
  //   · `publish/publish_chooser_sheet.dart` —— 小程序侧 components/cy/publish-sheet
  //     其实是**无条件浅**(`.ps__panel theme-topic-editor`);但 App 侧这个面板由
  //     showCupertinoSheet 在 rootNavigator 上开,拿不到路由那层浅色 Theme,真浅
  //     要等 sheet 主题机制(共用层)落地 —— 现在收进表里只会门禁看绿、面板仍黑。
  'lib/feature/publish/publish_page.dart',
  'lib/feature/publish/publish_activity_page.dart',
  'lib/feature/publish/publish_pro_page.dart',
  'lib/feature/publish/publish_pro_sheets.dart',
  'lib/feature/publish/publish_pro_story_editor.dart',
  'lib/feature/publish/publish_pro_ticket_tab.dart',
  'lib/feature/publish/publish_pro_utils.dart',
  'lib/feature/publish/collaborator_picker.dart',
  'lib/feature/publish/ai_draft_sheet.dart',
  'lib/feature/template/template_name_page.dart',
  'lib/feature/template/template_edit_page.dart',
  'lib/feature/template/template_intro_page.dart',
  'lib/core/widgets/',
];

/// 主题相关的色 token —— 这些在浅色下必须换值。
/// 状态色不在内:success/danger/warning 两端同值,硬编码它们是对的。
const String _kBannedPattern =
    r'\b(?:CyTokens|AppColors)\.(?:bgPage|bgSurface|bgSurfaceSubtle'
    r'|bgSurfaceStrong|bgElevated|bgSubtle|bgGlass|textPrimary|textSecondary'
    r'|textTertiary|textPlaceholder|textDisabled|textInverse|borderSubtle'
    r'|borderStrong|overlay|divider|actionPrimaryBg|actionPrimaryFg|actionSecondaryBg|actionSecondaryFg|statePressed|brand|brandSoft|inputBgEmpty|inputBgFilled|inputText|inputPlaceholder|primary|onPrimary)\b';

void main() {
  test('可变浅色的页面不许硬编码主题色', () {
    final RegExp banned = RegExp(_kBannedPattern);
    final List<String> offenders = <String>[];
    int scannedFiles = 0;

    for (final String entry in _kLightCapable) {
      final List<File> files = entry.endsWith('/')
          ? Directory(entry)
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart'))
              .toList()
          : <File>[File(entry)];

      for (final File f in files) {
        expect(f.existsSync(), isTrue,
            reason: '${f.path} 不存在 —— 文件改名了就把 _kLightCapable 一起改,'
                '别让这道闸静默少扫一个文件');
        scannedFiles++;
        final List<String> lines = f.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          // 注释里提到 token 名是正常的(解释为什么不能用),只查代码
          final String code = lines[i].split('//').first;
          for (final RegExpMatch m in banned.allMatches(code)) {
            offenders.add('${f.path}:${i + 1}  ${m.group(0)}');
          }
        }
      }
    }

    // ★ 没有这条,目录改名后它会扫 0 个文件然后报绿。
    expect(scannedFiles, greaterThanOrEqualTo(25),
        reason: '只扫到 $scannedFiles 个文件,太少了 —— 目录是不是搬家了?');

    expect(offenders, isEmpty,
        reason: '这些地方在浅色主题下会保持暗色,造成白底黑卡/白底白字。\n'
            '改成 `CyPalette.of(context).xxx`:\n${offenders.join('\n')}');
  });
}
