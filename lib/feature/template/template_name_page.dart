import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import 'template_creation_navigation.dart';

/// 模板创建第 1 页。
///
/// 对齐小程序 `pages/publish/templateadd`：先独立命名，再用
/// replace 进入编辑器，避免编辑器返回时重复经过命名页。
class TemplateNamePage extends StatefulWidget {
  const TemplateNamePage({super.key});

  @override
  State<TemplateNamePage> createState() => _TemplateNamePageState();
}

class _TemplateNamePageState extends State<TemplateNamePage> {
  final TextEditingController _controller = TextEditingController();

  bool get _canContinue => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_canContinue) return;
    final String name = _controller.text;
    replaceTemplateCreationStep(
      context,
      Uri(
        path: '/template/edit',
        queryParameters: <String, String>{'templateName': name},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('创建节点玩法')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space4,
              CyTokens.pageX,
              CyTokens.space4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '创建节点玩法',
                  // 真源 --cy-font-page-title(58rpx = 29)→ 梯级最近档 Title1 28(T2);
                  // T3:强调用 bold(700),w800 属堆重。
                  style: CyType.title1.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '完善以下内容，为路线打造可落地的现场互动方案',
                  // 真源 `cy-page-title` 的副标 = body(28rpx = 14)→ Subhead 15(T2);
                  // 原来不写字号 = 吃 Material 默认 14,不在 iOS 阶梯上。
                  style: CyType.subhead.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: CyTokens.space4),
                CupertinoTextField(
                  key: const Key('template-name-field'),
                  controller: _controller,
                  autofocus: true,
                  placeholder: '给节点玩法起个名字',
                  clearButtonMode: OverlayVisibilityMode.editing,
                  textInputAction: TextInputAction.done,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                    vertical: 14,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _continue(),
                ),
                const Spacer(),
                CyNativeButton(
                  key: const Key('template-name-confirm'),
                  label: '确认',
                  onPressed: _canContinue ? _continue : null,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
