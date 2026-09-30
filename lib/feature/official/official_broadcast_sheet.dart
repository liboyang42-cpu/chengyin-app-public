// 发官方通知 —— 对应小程序 pages/activity/list 里那段 `_pubPostJson('/api/official/broadcast')`。
//
// 与「发布官方活动」共用同一道白名单闸(officialCanPublishProvider),
// 所以挂在同一页上,不另开一个会被权限挡住的入口。
//
// ★★ 后端返回的话是「通知已提交」不是「已送达」——
//   渲染成「已发送给 N 人」就是替投递系统作保。文案照它的口径说。
//
// ★ 分角色文案(copyMode=2)是小程序那边的能力:同一条通知给
//   玩家/俱乐部/商家各写一句。这里**先做统一文案(copyMode=1)**,
//   并把这个取舍写明 —— 分角色文案要三套输入框,现在没有它的落点;
//   等有人真的要用再补,而不是先摆三组空框。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_sheet.dart';
import 'official_controller.dart';

/// 受众。★ 与后端 audience 字段的取值逐字对齐,别自己造词。
const List<({String wire, String label})> kBroadcastAudiences =
    <({String wire, String label})>[
      (wire: 'player', label: '玩家'),
      (wire: 'club', label: '俱乐部'),
      (wire: 'merchant', label: '商家'),
    ];

/// 组装请求体。抽成纯函数是为了能对着它写断言 ——
/// 这条通知一旦发出去就收不回来,参数拼错的代价比一般表单高。
Map<String, dynamic> buildBroadcastBody({
  required String title,
  required String sub,
  required Set<String> audience,
  int? eventId,
  String? city,
}) => <String, dynamic>{
  'eventId': eventId,
  'title': title.trim(),
  // ★ 逗号分隔,顺序按 kBroadcastAudiences 固定 —— 不用 Set 的遍历序,
  //   那个不稳定,会让同样的选择拼出不同的字符串。
  'audience': <String>[
    for (final a in kBroadcastAudiences)
      if (audience.contains(a.wire)) a.wire,
  ].join(','),
  'copyMode': 1,
  'contentJson':
      '{"title":"${_esc(title.trim())}","sub":"${_esc(sub.trim())}"}',
  // 小程序默认 'inapp',原样跟随。
  'channels': 'inapp',
  'city': city,
};

String _esc(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

Future<void> showBroadcastSheet(BuildContext context) =>
    // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
    showCyNativeSheet<void>(
      context,
      builder: (BuildContext context) => const _Sheet(),
    );

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet();

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _sub = TextEditingController();
  final Set<String> _aud = <String>{'player'};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _sub.dispose();
    super.dispose();
  }

  String? get _blocker {
    if (_title.text.trim().isEmpty) return '先写通知标题';
    if (_aud.isEmpty) return '至少选一类收件人';
    return null;
  }

  Future<void> _send() async {
    if (_busy || _blocker != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(officialApiProvider)
          .broadcast(
            buildBroadcastBody(
              title: _title.text,
              sub: _sub.text,
              audience: _aud,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      // ★ 「已提交」不是「已送达」。
      CyNativeNotice.show(context, '通知已提交');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // 401 是登录态问题不是故障 —— 分流成登录引导(dio 层已清 token、
      //   全局跳回 /login,这句只解释「为什么被弹走」;口径同 ofc-06 收口)。
      // 其余走域内归一管线:后端中文原话(内容安全原因就是这句)直用,
      //   告诉他改哪儿;只有 dio 英文栈才换人话。
      CyNativeNotice.show(
        context,
        isUnauthorizedError(e) ? '登录状态已失效，请重新登录' : officialErrorSub(e),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final BoxDecoration inputDecoration = BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
    final TextStyle? inputStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPrimary,
    );
    final TextStyle? placeholderStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPlaceholder,
    );

    return CupertinoPageScaffold(
      // 原生承载时透明,透出系统 sheet 背景(S3:不给 sheet 加自定义背景)。
      backgroundColor: isCyNativeSheet(context)
          ? Colors.transparent
          : palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('发官方通知')),
      child: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              '标题',
              style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              controller: _title,
              key: const Key('broadcast-title'),
              onChanged: (_) => setState(() {}),
              placeholder: '请输入通知标题',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              clearButtonMode: OverlayVisibilityMode.editing,
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              '副文案',
              style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              controller: _sub,
              key: const Key('broadcast-sub'),
              minLines: 2,
              maxLines: 2,
              placeholder: '请输入副文案',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              '收件人',
              style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            // 受众是多选，保持小程序的三项固定入口与顺序。
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (final a in kBroadcastAudiences)
                  _AudToggle(
                    wire: a.wire,
                    label: a.label,
                    on: _aud.contains(a.wire),
                    onTap: () => setState(
                      () => _aud.contains(a.wire)
                          ? _aud.remove(a.wire)
                          : _aud.add(a.wire),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CyTokens.space4),
            CupertinoButton(
              key: const Key('broadcast-send'),
              minimumSize: const Size.fromHeight(44),
              color: palette.actionPrimaryBg,
              disabledColor: palette.bgSubtle,
              foregroundColor: (_busy || _blocker != null)
                  ? palette.textPlaceholder
                  : palette.actionPrimaryFg,
              onPressed: (_busy || _blocker != null) ? null : _send,
              child: _busy
                  ? const CupertinoActivityIndicator()
                  : Text(_blocker ?? '提交'),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              '提交后由平台投递,「已提交」不等于已送达。',
              style: textTheme.labelSmall?.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudToggle extends StatelessWidget {
  const _AudToggle({
    required this.wire,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String wire;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      key: Key('broadcast-aud-$wire'),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
      color: on ? palette.actionPrimaryBg : palette.actionSecondaryBg,
      foregroundColor: on ? palette.actionPrimaryFg : palette.textSecondary,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: CyTokens.typeBody,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
