import 'package:flutter/cupertino.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';

/// 全屏图片查看器:左右翻页 + 双指缩放 + 第几张/共几张。
///
/// ★ 比小程序丰富在哪:小程序帖文里点图走 `wx.previewImage`
///   (系统层看不了第几张、也不能缩放说明);App 自己有一层,
///   序号、缩放、关闭按钮和「第 n 张」的朗读标签都在我们手里。
Future<void> showSquareImageViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) async {
  final List<String> shown = urls
      .where((String url) => url.trim().isNotEmpty)
      .toList(growable: false);
  if (shown.isEmpty) return;
  final int start = initialIndex.clamp(0, shown.length - 1);
  await Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) =>
          SquareImageViewer(urls: shown, initialIndex: start),
    ),
  );
}

class SquareImageViewer extends StatefulWidget {
  const SquareImageViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<SquareImageViewer> createState() => _SquareImageViewerState();
}

class _SquareImageViewerState extends State<SquareImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex.clamp(0, widget.urls.length - 1),
  );
  late int _index = widget.initialIndex.clamp(0, widget.urls.length - 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      key: const Key('square-image-viewer'),
      // 看图就是看图:恒黑底,不跟浅色主题走。
      backgroundColor: CupertinoColors.black,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (int value) => setState(() => _index = value),
              itemBuilder: (BuildContext context, int index) => Semantics(
                key: Key('square-image-viewer-page-$index'),
                image: true,
                label: '第 ${index + 1} 张，共 ${widget.urls.length} 张',
                child: ExcludeSemantics(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: CyNetImage(
                        widget.urls[index],
                        fit: BoxFit.contain,
                        fallback: const Center(
                          child: Icon(
                            CupertinoIcons.photo,
                            color: CupertinoColors.systemGrey,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                  vertical: CyTokens.space1,
                ),
                child: Row(
                  children: <Widget>[
                    Semantics(
                      button: true,
                      label: '关闭图片查看器',
                      child: CupertinoButton(
                        key: const Key('square-image-viewer-close'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const ExcludeSemantics(
                          child: Icon(
                            CupertinoIcons.xmark,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.urls.length > 1)
                      Container(
                        key: const Key('square-image-viewer-count'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space2,
                          vertical: CyTokens.space1,
                        ),
                        decoration: BoxDecoration(
                          color: palette.overlay,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusPill,
                          ),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.urls.length}',
                          style: const TextStyle(
                            color: CupertinoColors.white,
                            fontSize: CyTokens.typeCaption,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
