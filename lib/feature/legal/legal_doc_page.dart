import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import 'legal_docs.dart';

/// 法律文档展示页。排版对齐小程序 `pages/agreement`(index.wxml + index.wxss):
/// 页内大标题 → intro → 若干「小节标题 + 正文」→ 页脚生效日期,左右 page-x。
///
/// 路由:`/legal/:type`,type 取 [LegalDocType] 里的 key;未知 type 由
/// [legalDoc] 兜底到《用户服务协议》,不会出现空白页。
class LegalDocPage extends StatelessWidget {
  const LegalDocPage({super.key, required this.type});

  final String type;

  static String routeOf(String type) => '/legal/$type';

  @override
  Widget build(BuildContext context) {
    final LegalDoc doc = legalDoc(type);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      // 整页滚动(含大标题)—— 与小程序一致:那边 cy-page-title 也在页面滚动流里,
      // 长文页把标题钉死会让正文从标题下缘"钻出来",看着像穿模。
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: CyTokens.space7),
            children: <Widget>[
              CyPageTitle(doc.title),
              Padding(
                // .agr-page:padding 0 page-x。标题→首段的 space-5 由 CyPageTitle 承担。
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: doc.pending
                      ? const <Widget>[_PendingBody()]
                      : <Widget>[
                          // .agr-intro
                          Text(doc.intro ?? '', style: _bodyStyle),
                          for (final LegalSection s in doc.sections)
                            Padding(
                              // .agr-section:margin-top space-5
                              padding: const EdgeInsets.only(
                                top: CyTokens.space5,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  // .agr-h:真源 --cy-font-subtitle(16)/w600 →
                                  // 梯级最近档 Headline 17 Semibold(T1/T2)
                                  Text(s.h, style: _sectionStyle),
                                  // .agr-p:margin-top space-2
                                  const SizedBox(height: CyTokens.space2),
                                  _Paragraph(text: s.p),
                                ],
                              ),
                            ),
                          if (doc.updatedAt != null)
                            Padding(
                              // .agr-meta--footer:margin-top space-6
                              padding: const EdgeInsets.only(
                                top: CyTokens.space6,
                              ),
                              child: Text(
                                '生效日期：${doc.updatedAt}',
                                style: _metaStyle,
                              ),
                            ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// .agr-intro / .agr-p 共用:iOS Body 17(T1/T2)+ loose 行高 + text-body(=secondary)。
///
/// 字号从真源的 `--cy-font-body`(28rpx = 14)换到 iOS 正文档 17 —— 仓内 rpx÷2
/// 字阶不在 HIG 梯级上(梯上没有 14),T2 要求落在梯级,属「iOS 27 原生化」。
/// 颜色仍取 `CyTokens`:真源 `pages/agreement/index.wxml` 根节点是**无条件**
/// `theme-dark`(商家点进来也是暗色),这页是手册 §6 允许的「确定恒暗的玩家页」。
final TextStyle _bodyStyle = CyType.body.copyWith(
  height: CyTokens.leadingLoose,
  color: CyTokens.textSecondary,
);

/// .agr-h 小节标题:iOS Headline 17 Semibold(真源 --cy-font-subtitle 16 / w600)。
final TextStyle _sectionStyle = CyType.headline.copyWith(
  height: CyTokens.leadingNormal,
  color: CyTokens.textPrimary,
);

/// .agr-meta--footer 生效日期:iOS Caption1 12(与真源 --cy-font-label 同值)。
final TextStyle _metaStyle = CyType.caption1.copyWith(
  height: CyTokens.leadingNormal,
  color: CyTokens.textSecondary,
);

/// 「待提供」占位:让人一眼看出是**这份文本还没有**,不是页面坏了。
/// 目前只有《隐私政策》会走到这里,原因见 legal_docs.dart 里那段注释。
class _PendingBody extends StatelessWidget {
  const _PendingBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('该文档待提供', style: _sectionStyle),
          const SizedBox(height: CyTokens.space2),
          Text(
            '这份文档的正文还在定稿中,暂时无法在此展示。页面本身是正常的 —— '
            '定稿后会直接出现在这里。',
            style: _bodyStyle,
          ),
          const SizedBox(height: CyTokens.space5),
          Text(
            '如需了解我们如何处理你的个人信息,可先查阅《用户服务协议》第七条'
            '「个人信息与位置权限」。',
            style: _bodyStyle.copyWith(color: CyTokens.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 「登录即同意《用户服务协议》与《隐私政策》」——两个书名号**各自可点**,
/// 点了进 [LegalDocPage]。App Store 审核要求注册/登录流程内能访问到这两份文档,
/// 纯 Text 点不动 = 上架阻断项,所以这行必须走 RichText + 手势识别器。
///
/// 识别器要显式 dispose,故为 StatefulWidget。
class LegalConsentLine extends StatefulWidget {
  const LegalConsentLine({super.key});

  @override
  State<LegalConsentLine> createState() => _LegalConsentLineState();
}

class _LegalConsentLineState extends State<LegalConsentLine> {
  final TapGestureRecognizer _agreement = TapGestureRecognizer();
  final TapGestureRecognizer _privacy = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _agreement.onTap = () => _open(LegalDocType.userAgreement);
    _privacy.onTap = () => _open(LegalDocType.privacyPolicy);
  }

  void _open(String type) => context.push(LegalDocPage.routeOf(type));

  @override
  void dispose() {
    _agreement.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: '登录即同意'),
          // 文档名统一按真源:小程序里这份文档处处叫《用户服务协议》
          // (title 字段 / shezhi 入口 / about 入口 / agreement 页标题)。
          TextSpan(text: '《用户服务协议》', style: _linkStyle, recognizer: _agreement),
          const TextSpan(text: '与'),
          TextSpan(text: '《隐私政策》', style: _linkStyle, recognizer: _privacy),
        ],
      ),
      textAlign: TextAlign.center,
      // ★ height 不是排版偏好,是**热区**:行内链接的命中盒就是它所在行的文字盒,
      //   caption 11pt 默认行盒只有 16pt,拇指点不中(HIG 最小可点尺寸 44pt)。
      //   11 × 4.0 = 44。文字在行盒内垂直居中,所以视觉上只是上下多了透明留白,
      //   字号与颜色都没变。
      //   ⚠️ 别为了「看着紧凑」把它调小 —— test/feature/legal/consent_tap_target_test.dart
      //   会红。注意 `tapOnText` 那类测试**永远抓不到这个**,它按文字中心精确命中。
      style: CyType.caption2.copyWith(
        color: CyTokens.textDisabled,
        height: 4.0,
      ),
    );
  }
}

/// 行内链接:与小程序 `.deregister-link` 同款 —— text-title + 下划线。
/// 底色是 textDisabled 的灰,链接必须显著更亮才看得出「这里能点」。
const TextStyle _linkStyle = TextStyle(
  color: CyTokens.textPrimary,
  decoration: TextDecoration.underline,
  decorationColor: CyTokens.textPrimary,
);

/// 正文段落。含 `\n` 的段落按行渲染,并给「1. / 2. / ·」这类列表行做**悬挂缩进**。
///
/// ★ 为什么要专门处理:定稿文本里的列表是写在同一个字符串里、用 `\n` 分行的
///   (如《账号注销须知》第一节的五种不可注销情形)。整段丢给一个 Text,
///   换行后会**顶格**到最左 —— 第 4 条那种较长的会断成「…处理相关业\n务;」,
///   「务;」孤零零顶在行首,看着像新的一条。
///   这是用户要阅读并同意的法律文本,读不清不是排版洁癖,是实质问题。
class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  /// 行首的列表记号:`1.` `12.` `一、` `·` `-`。取到记号本身,没有则返回 null。
  static String? _marker(String line) {
    final RegExpMatch? m = RegExp(
      r'^(\d{1,2}[.、]|[·•\-]|[一二三四五六七八九十]+、)\s*',
    ).firstMatch(line);
    return m?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> lines = text.split('\n');
    if (lines.length == 1) return Text(text, style: _bodyStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String line in lines)
          Builder(
            builder: (BuildContext context) {
              final String? mark = _marker(line);
              if (mark == null) return Text(line, style: _bodyStyle);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(mark, style: _bodyStyle),
                  Expanded(
                    child: Text(line.substring(mark.length), style: _bodyStyle),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
