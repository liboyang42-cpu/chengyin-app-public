import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/invitation.dart';
import '../profile/profile_edit_page.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_sheet.dart';

/// 填写邀请人。对齐小程序首页的 setInviter 能力(App 侧此前完全没有)。
///
/// ★ 邀请人**只能绑一次**(后端 bindInviterIfAbsent),所以:
///   - 提交前把能判的先判(空/非法/绑自己)
///   - 失败时不编一个确定的原因,并明说不用重试
Future<void> showInviterSheet(BuildContext context) {
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  return showCyNativeSheet<void>(
    context,
    detents: CyNativeSheetDetents.medium,
    builder: (BuildContext context) => const _InviterSheet(),
  );
}

class _InviterSheet extends ConsumerStatefulWidget {
  const _InviterSheet();

  @override
  ConsumerState<_InviterSheet> createState() => _InviterSheetState();
}

class _InviterSheetState extends ConsumerState<_InviterSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit(int? myId) async {
    final local = InviterBinding.localReject(
      inviterId: _ctrl.text,
      myMemberId: myId,
    );
    if (local != null) {
      setState(() => _error = local);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(registrationApiProvider).setInviter(_ctrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      CyNativeNotice.show(context, '已绑定邀请人');
    } catch (e) {
      if (!mounted) return;
      // ★ 直接展示后端失败的完整说明(含"可能已绑过 · 重试不会有变化"),
      //   而不是压成一句「绑定失败」。
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final myId = ref.watch(myProfileProvider).asData?.value.id;

    // ★ 表单类 sheet **保留不透明背景**(同上:可读性优先)。
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('填写邀请人')),
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
            const SizedBox(height: CyTokens.space1),
            Text(
              '邀请人只能绑定一次,填写后无法更改。',
              style: textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              key: const Key('inviter-code'),
              controller: _ctrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              placeholder: '输入邀请码',
              placeholderStyle: textTheme.bodyMedium?.copyWith(
                color: palette.textPlaceholder,
              ),
              style: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: palette.inputBgEmpty,
                border: Border.all(color: palette.borderSubtle),
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (!_busy) _submit(myId);
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: textTheme.bodySmall?.copyWith(
                      color: CyTokens.statusWarning,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('inviter-submit'),
              minimumSize: const Size.fromHeight(44),
              color: palette.actionPrimaryBg,
              disabledColor: palette.bgSubtle,
              foregroundColor: _busy
                  ? palette.textPlaceholder
                  : palette.actionPrimaryFg,
              onPressed: _busy ? null : () => _submit(myId),
              child: _busy
                  ? const CupertinoActivityIndicator()
                  : const Text('绑定'),
            ),
          ],
        ),
      ),
    );
  }
}
