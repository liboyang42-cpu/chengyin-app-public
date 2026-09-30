import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../playkit_fullscreen.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-stickerbook` · 城市贴纸图鉴。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-stickerbook/`。
///
/// 「已收集 + 未解锁空槽」拼成一个网格:空槽不是占位符,是稿里明确要的
/// 「还差几张」。所以 [lockedCount] 由调用方给(它知道本城总共几张),**组件不猜**。
///
/// ## 这一件在小程序里是「半屏 sheet」
/// `usingComponents` 是 `cy-sheet`(带 grabber 的半屏),不是 `cy-play-stage`。
/// 所以它**没有**登记进 `kFullscreenPlayKinds` —— 那个集合的语义是「必须占满屏」。
/// 宿主用原生 sheet 呈现时把 [showGrabber] 关掉。
///
/// ## 触感只落在**已收集**的贴纸上
/// 未解锁的格子没有 id,点了不震 —— 给没解锁的东西手感等于骗一下用户。
/// 切分类不震(那是浏览)。减动效下不震:真源 `motion.haptic` 在 reducedMotion 时
/// 直接 `return false`(触感也是动效)。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * 网格改用 iOS 原生网格口径(3 列、gap 8)承载旋转卡纸;角度逐值照搬 `TILTS`。
/// * 字号走 iOS 梯级(T2),字重 900 → w700(T3)。
class PlayKitStickerBookView extends StatelessWidget {
  const PlayKitStickerBookView({
    super.key,
    required this.data,
    this.eyebrow = '我的城市贴纸',
    this.total = 0,
    this.categories = const <PlayKitStickerCategory>[],
    this.activeCategory = '',
    this.stickers = const <PlayKitSticker>[],
    this.lockedCount = 0,
    this.hint = '',
    this.showGrabber = true,
    this.onCategoryChanged,
    this.onStickerTap,
  });

  final PlayKitFullscreenContext data;
  final String eyebrow;
  final int total;
  final List<PlayKitStickerCategory> categories;
  final String activeCategory;
  final List<PlayKitSticker> stickers;
  final int lockedCount;
  final String hint;
  final bool showGrabber;
  final ValueChanged<String>? onCategoryChanged;
  final ValueChanged<int>? onStickerTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final List<PlayKitStickerCell> cells = buildStickerCells(
      stickers,
      lockedCount,
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CyTokens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space5,
        CyTokens.space2,
        CyTokens.space5,
        CyTokens.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showGrabber)
            Center(
              child: Semantics(
                label: '下滑关闭',
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: CyTokens.space1),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          PlayKitEyebrow(
            eyebrow,
            color: palette.textSecondary,
            letterSpacing: 1.6,
          ),
          const SizedBox(height: CyTokens.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              PlayKitBigFigure(
                text: '$total',
                size: 34,
                color: palette.textPrimary,
              ),
              const SizedBox(width: CyTokens.space2),
              Flexible(
                child: Text(
                  '张 · 每张都是你亲手拍下的城市',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: CyTokens.typeCaption,
                  ),
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            // 胶囊行高必须 ≥ 触控下限:36 会把 CupertinoButton 的 44 命中区裁掉(L9)。
            SizedBox(
              height: kPlayKitMinTapTarget,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: CyTokens.space2),
                itemBuilder: (BuildContext context, int index) {
                  final PlayKitStickerCategory category = categories[index];
                  return _CategoryPill(
                    label: category.label,
                    selected: category.key == activeCategory,
                    onPressed: category.key == activeCategory
                        ? null
                        : () => onCategoryChanged?.call(category.key),
                  );
                },
              ),
            ),
          ],
          if (cells.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            _StickerGrid(cells: cells, onStickerTap: onStickerTap),
          ],
          if (hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textTertiary,
                fontSize: CyTokens.typeLabel,
                height: CyTokens.leadingNormal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 分类:「全部」+ 各城市/类别。`key` 与 `activeCategory` 对得上才算选中。
@immutable
class PlayKitStickerCategory {
  const PlayKitStickerCategory({required this.key, required this.label});

  final String key;
  final String label;
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '筛选 $label',
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        minimumSize: const Size.square(kPlayKitMinTapTarget),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        color: selected ? palette.actionPrimaryBg : palette.bgSurfaceSubtle,
        pressedOpacity: 0.8,
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.actionPrimaryFg : palette.textSecondary,
            fontSize: CyTokens.typeLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({required this.cells, required this.onStickerTap});

  final List<PlayKitStickerCell> cells;
  final ValueChanged<int>? onStickerTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: CyTokens.space2,
        crossAxisSpacing: CyTokens.space2,
        childAspectRatio: 0.82,
      ),
      itemCount: cells.length,
      itemBuilder: (BuildContext context, int index) {
        final PlayKitStickerCell cell = cells[index];
        return Transform.rotate(
          angle: cell.tilt * math.pi / 180,
          child: cell.locked
              ? const _LockedSlot()
              : _StickerCard(cell: cell, onStickerTap: onStickerTap),
        );
      },
    );
  }
}

/// 空槽:一个问号 + 一句可读的语义标签。**没有可点的手感**。
class _LockedSlot extends StatelessWidget {
  const _LockedSlot();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      image: true,
      label: '尚未解锁的贴纸位',
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: palette.borderSubtle),
        ),
        alignment: Alignment.center,
        child: Text(
          '?',
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 白相纸:贴纸的辨识度全在这圈白边 + 落影。
class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.cell, required this.onStickerTap});

  final PlayKitStickerCell cell;
  final ValueChanged<int>? onStickerTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String label = cell.label;
    return Semantics(
      button: true,
      label: '查看贴纸 $label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final int? id = cell.id;
          if (id == null) return;
          if (!MediaQuery.disableAnimationsOf(context)) {
            unawaited(HapticFeedback.lightImpact());
          }
          onStickerTap?.call(id);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(CyTokens.space1),
              decoration: BoxDecoration(
                color: palette.bgSurface,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                border: Border.all(color: palette.borderSubtle),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.overlay,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      child: CyNetImage(
                        cell.imgUrl,
                        width: double.infinity,
                        fallback: ColoredBox(
                          color: _fallbackColor(palette, cell.color),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: CyTokens.typeCaption,
                    ),
                  ),
                ],
              ),
            ),
            if (cell.isNew)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space1,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.statusDanger,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                  child: Text(
                    '新!',
                    style: TextStyle(
                      color: palette.textInverse,
                      fontSize: CyTokens.typeCaption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 贴纸自带色(`color`)优先 —— 它是服务端给的这一张的底色,
  /// 认不出/为空时才落回主题的软底。
  Color _fallbackColor(CyPalette palette, String? raw) {
    final String text = raw?.trim() ?? '';
    if (text.startsWith('#') && (text.length == 7 || text.length == 9)) {
      final int? value = int.tryParse(text.substring(1), radix: 16);
      if (value != null) {
        return Color(text.length == 7 ? 0xFF000000 | value : value);
      }
    }
    return palette.bgSurfaceSubtle;
  }
}
