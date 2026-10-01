import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/status_view.dart';
import 'club_controller.dart';
import 'club_login_gate.dart';

/// 旧 workbench 只服务外部直达/历史深链;站内管理体已合并到俱乐部详情页。
/// 对齐小程序 `pages/club/workbench`(redirect 到详情页管理视图):
/// - 带 clubId → 直达该俱乐部详情(owner 时详情页内展示管理入口);
/// - 不带 → 取我拥有的第一个俱乐部;一个都没有就回俱乐部目录。
class ClubWorkbenchPage extends ConsumerStatefulWidget {
  const ClubWorkbenchPage({super.key, this.clubId});
  final int? clubId;

  @override
  ConsumerState<ClubWorkbenchPage> createState() => _ClubWorkbenchPageState();
}

class _ClubWorkbenchPageState extends ConsumerState<ClubWorkbenchPage> {
  String? _error;
  bool _loginRequired = false;

  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    final clubId = widget.clubId;
    if (clubId != null && clubId > 0) {
      // ★ 不能在 build 期同步 go():initState 还在 build 阶段,go() 会让
      //   go_router 的 Router 在 build 中被标记重建 ——
      //   「setState() or markNeedsBuild() called during build」未捕获异常,
      //   页面永远停在转圈(2026-09-17 模拟器实测:带 id 的入口必现)。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/club/$clubId');
      });
      return;
    }
    try {
      final owned = await ref.read(clubMyProvider.future);
      if (!mounted) return;
      if (owned.isNotEmpty) {
        context.go('/club/${owned.first.id}');
      } else {
        context.go('/clubs');
      }
    } catch (error) {
      if (!mounted) return;
      // 游客(从没登录过)撞 401 说成「加载失败,检查网络后重试」是死路 ——
      // 重试多少次都还是 401,与 club 域其余页面同口径走登录引导。
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _error = _loginRequired ? null : stringsOf(context).clubWorkbenchLoadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _loginRequired
              ? ClubLoginGate(message: stringsOf(context).clubWorkbenchLogin, onSignedIn: _redirect)
              : _error == null
              ? const Center(child: CupertinoActivityIndicator())
              : StatusView(
                  // 与小程序 `pages/club/workbench` 同一套错误文案:
                  // 主标说清是哪件事失败,副标说清接下来能做什么。
                  message: stringsOf(context).clubWorkbenchUnavailable,
                  sub: _error!,
                  icon: CupertinoIcons.exclamationmark_triangle,
                  retryLabel: stringsOf(context).clubWorkbenchRetry,
                  onRetry: () {
                    setState(() => _error = null);
                    _redirect();
                  },
                ),
        ),
      ),
    );
  }
}
