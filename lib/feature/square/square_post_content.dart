import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

/// 正文片段类型。
enum SquareContentTokenKind { text, mention, topic }

@immutable
class SquareContentToken {
  const SquareContentToken(this.kind, this.text);

  final SquareContentTokenKind kind;
  final String text;
}

/// @提及 / #话题 后面最多跟多少字符。超过就不再当成一个整体
/// (避免把一句长中文全吞进去)。
const int squareContentTagMaxLength = 24;

final RegExp _tagChar = RegExp(r'[0-9A-Za-z_\u00B7\u4E00-\u9FFF\u3400-\u4DBF]');

/// @/# 的启动边界:行首、空白或标点。`a@b.com` 里的 @ 不该高亮。
bool _isTagBoundary(String ch) {
  if (ch.trim().isEmpty) return true;
  return '，,。.；;：:!！?？、（）()【】[]「」『』“”"\''.contains(ch);
}

/// 把一行文本切成 普通文本 / @提及 / #话题 三种片段。
///
/// ★ 为什么是「行内扫描」而不是正则替换:小程序那边正文就是
///   `{{contents}}` 原样渲染,连换行都不保留;App 这边要做段落与高亮,
///   就得先知道哪些字符是 token —— 边界(标点/空白)也要一起判,
///   否则「下午3点@阿兰」和「a@b.com」会被切成不同的结果。
List<SquareContentToken> squareContentTokens(String line) {
  final List<SquareContentToken> tokens = <SquareContentToken>[];
  final StringBuffer plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    tokens.add(
      SquareContentToken(SquareContentTokenKind.text, plain.toString()),
    );
    plain.clear();
  }

  int index = 0;
  while (index < line.length) {
    final String ch = line[index];
    if (ch == '@' || ch == '#') {
      final bool boundary = index == 0 || _isTagBoundary(line[index - 1]);
      int end = index + 1;
      while (end < line.length && _tagChar.hasMatch(line[end])) {
        end++;
      }
      final int length = end - index - 1;
      if (boundary && length >= 1 && length <= squareContentTagMaxLength) {
        flush();
        tokens.add(
          SquareContentToken(
            ch == '@'
                ? SquareContentTokenKind.mention
                : SquareContentTokenKind.topic,
            line.substring(index, end),
          ),
        );
        index = end;
        continue;
      }
    }
    plain.write(ch);
    index++;
  }
  flush();
  return tokens;
}

/// 按换行切成段落(空行保留,作为段间距)。`\r\n` 一并归一。
List<List<SquareContentToken>> squareContentParagraphs(String source) {
  return source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map(squareContentTokens)
      .toList(growable: false);
}

/// 段落 → TextSpan。@提及 / #话题 用加粗 + 下划线标出来
/// (城瘾是黑白系,不引入彩色;下划线在深浅两套外观里都成立)。
List<TextSpan> squareContentSpans(
  List<SquareContentToken> tokens, {
  required TextStyle base,
  required TextStyle tag,
}) {
  return tokens
      .map(
        (SquareContentToken token) => TextSpan(
          text: token.text,
          style: token.kind == SquareContentTokenKind.text ? base : tag,
        ),
      )
      .toList(growable: false);
}

/// 帖文 / 评论正文。
///
/// ★ 比小程序丰富在哪(对照 `components/cy/post-card/index.wxml`):
///   小程序正文是 `{{post.contents}}` 一整块纯文本,按稿夹 2 行后挂一个
///   **假的**「展开」提示(注释自陈「没有展开态(那要改 js)」);
///   App 这边保留换行与段落、标出 @/#,并把「展开」做成真的:
///   展开前按行数夹断,展开后按段落铺开,再点收起。
class SquarePostContent extends StatefulWidget {
  const SquarePostContent({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 6,
    this.expandable = true,
    this.paragraphSpacing = CyTokens.space2,
    this.semanticLabel,
  });

  final String text;
  final TextStyle? style;

  /// 折叠态最多几行。
  final int maxLines;

  /// 详情页这类整页阅读场景传 false:正文全部铺开,不做二次展开。
  final bool expandable;
  final double paragraphSpacing;

  /// 无障碍朗读用的整段文本。
  final String? semanticLabel;

  @override
  State<SquarePostContent> createState() => _SquarePostContentState();
}

class _SquarePostContentState extends State<SquarePostContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextStyle base =
        widget.style ??
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: palette.textPrimary,
          height: 1.35,
        );
    final TextStyle tag = base.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: palette.textTertiary,
      decorationThickness: 1,
    );
    final List<List<SquareContentToken>> paragraphs = squareContentParagraphs(
      widget.text,
    );
    final List<TextSpan> joined = <TextSpan>[
      for (int i = 0; i < paragraphs.length; i++) ...<TextSpan>[
        if (i > 0) const TextSpan(text: '\n'),
        ...squareContentSpans(paragraphs[i], base: base, tag: tag),
      ],
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final TextPainter painter = TextPainter(
          text: TextSpan(style: base, children: joined),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: maxWidth);
        final bool clipped = painter.didExceedMaxLines;
        painter.dispose();
        final bool collapsed = widget.expandable && clipped && !_expanded;

        final Widget body = collapsed
            ? Text.rich(
                TextSpan(style: base, children: joined),
                key: const Key('square-content-collapsed'),
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
              )
            : Column(
                key: const Key('square-content-expanded'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < paragraphs.length; i++) ...<Widget>[
                    if (i > 0) SizedBox(height: widget.paragraphSpacing),
                    if (paragraphs[i].isNotEmpty)
                      Text.rich(
                        TextSpan(
                          style: base,
                          children: squareContentSpans(
                            paragraphs[i],
                            base: base,
                            tag: tag,
                          ),
                        ),
                      ),
                  ],
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              container: true,
              label: widget.semanticLabel ?? widget.text,
              child: ExcludeSemantics(child: body),
            ),
            if (widget.expandable && clipped)
              Semantics(
                button: true,
                label: collapsed ? '展开全文' : '收起全文',
                child: CupertinoButton(
                  key: const Key('square-content-toggle'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  alignment: Alignment.centerLeft,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: ExcludeSemantics(
                    child: Text(
                      collapsed ? '展开全文' : '收起',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
