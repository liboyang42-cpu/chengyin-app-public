import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 搜索框。移植小程序 `components/cy/search`。
///
/// **为什么值得一个组件**:App 这边 6 个页面各写了一套 `TextField`,
/// 只有 1 处有清除钮,6 处都没做空/满态底色区分 ——
/// 而 `CyTokens.inputBgEmpty` / `inputBgFilled` 这两个 token **定义了、全仓零使用**,
/// 设计意图在 token 层写着,却从来没通到界面上。
///
/// 三个容易被漏掉的细节,都在小程序侧有明确出处:
///   ① **空态与有内容态底色不同**(`--cy-comp-search-idle-bg` vs `--filled-bg`)——
///      这是「这里有没有正在生效的筛选」的唯一视觉线索;
///   ② 清除钮的触达区是 **44pt**(小程序 88rpx),不是图标本身那么大 ——
///      按图标大小做热区会点不中;
///   ③ 聚焦是**内描边**(inset box-shadow),不是外发光,也不换底色。
///
/// ★ 与手册 §3.6 分工的关系:搜索框底仍取调色板的 `inputBgEmpty` /
///   `inputBgFilled`(双值,C4),没有换成 `CupertinoColors.*SystemFill` ——
///   系统填充色没有「空态/满态」这一对梯度,换掉就会**删掉**「筛选是否生效」
///   的视觉信号(结构 1:1 优先,§7.1)。两个 token 的取值本就是系统填充语义。
class CySearchField extends StatefulWidget {
  const CySearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.placeholder = '搜索',
    this.enabled = true,
    this.loading = false,
    this.autofocus = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String placeholder;
  final bool enabled;
  final bool loading;
  final bool autofocus;

  @override
  State<CySearchField> createState() => _CySearchFieldState();
}

class _CySearchFieldState extends State<CySearchField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void didUpdateWidget(CySearchField old) {
    super.didUpdateWidget(old);
    // ★ 只在**外部值真的和框里不一样**时才回写 —— 无条件同步会在用户
    //   打字时把光标弹回开头(受控输入框的经典坑)。
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
      _ctrl.selection = TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool filled = widget.value.isNotEmpty;
    final double fieldHeight = math.max(
      44,
      MediaQuery.textScalerOf(context).scale(CyTokens.typeBody) + 16,
    );
    return Container(
      height: fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      decoration: BoxDecoration(
        // 空态 / 有内容态两套底色 —— 见类注释 ①
        color: filled ? p.inputBgFilled : p.inputBgEmpty,
        // ★ iOS 搜索框几何(手册 P3):圆角矩形,不是药丸 —— 系统搜索框
        //   (UISearchBar / SwiftUI .searchable)是 10pt 圆角,这里取梯级里最
        //   接近的 `radiusMd`(12),不再用 499.5 的药丸角。
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        // 聚焦 = 内描边,不换底色也不外发光 —— 见类注释 ③
        border: Border.all(
          color: _focused ? p.borderStrong : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.search, size: 16, color: p.textTertiary),
          const SizedBox(width: CyTokens.space1),
          Expanded(
            child: CupertinoTextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: CyTokens.typeBody,
              ),
              decoration: null,
              padding: EdgeInsets.zero,
              placeholder: widget.placeholder,
              placeholderStyle: TextStyle(
                color: p.textPlaceholder,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
          if (widget.loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CupertinoActivityIndicator(
                radius: 7,
                color: p.textTertiary,
              ),
            )
          else if (filled && widget.enabled)
            // 清除钮:图标 16pt,触达区 44pt —— 见类注释 ②。
            // ★ OverflowBox 保证动态字号下的按钮仍保持 44pt 命中区,
            //   不受输入行内容高度约束。
            //   小程序那边同样是让 ::after 绝对定位溢出,不是把框撑高。
            SizedBox(
              width: 44,
              child: OverflowBox(
                maxHeight: 44,
                minHeight: 44,
                child: Semantics(
                  label: '清除',
                  button: true,
                  child: ExcludeSemantics(
                    child: CupertinoButton(
                      minimumSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                      pressedOpacity: MediaQuery.disableAnimationsOf(context)
                          ? 1
                          : 0.4,
                      onPressed: () {
                        _ctrl.clear();
                        widget.onChanged('');
                      },
                      child: Icon(
                        CupertinoIcons.clear,
                        size: 16,
                        color: p.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
