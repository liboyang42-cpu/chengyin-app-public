import '../../l10n/strings.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/door_entry.dart';
import '../../core/router/route_paths.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/api/play_api.dart';
import '../auth/auth_controller.dart';

/// 门口码冷启动落地页(对齐小程序 pages/index onLoad 的前两段:
/// consumeDoorScene + 邀请人归因)。它不渲染内容,只负责把
/// `?scene=<32hex>` 换成真实去处、把 `?inviter`/`?id` 补发给后端,
/// 然后 go 走 —— 小程序里等价动作是 redirectTo/reLaunch。
class DoorEntryPage extends ConsumerStatefulWidget {
  const DoorEntryPage({super.key, this.scene, this.inviterId = ''});

  final String? scene;
  final String inviterId;

  @override
  ConsumerState<DoorEntryPage> createState() => _DoorEntryPageState();
}

class _DoorEntryPageState extends ConsumerState<DoorEntryPage> {
  bool _started = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant DoorEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene ||
        oldWidget.inviterId != widget.inviterId) {
      _generation++;
      _started = false;
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    unawaited(_consumeInviter());
    final String? code = parseDoorScene(widget.scene);
    if (code == null) {
      // 链接没带可解析的码 → 等同小程序首页普通启动。
      context.go(kHomeRoute);
      return;
    }
    unawaited(_consumeDoorScene(code));
  }

  Future<void> _consumeInviter() async {
    if (widget.inviterId.isEmpty) return;
    await ref.read(pendingInviterProvider).capture(widget.inviterId);
  }

  Future<void> _consumeDoorScene(String code) async {
    final int generation = ++_generation;
    String? route;
    final fallback = stringsOf(context).doorUnavailable;
    String failure = '';
    try {
      final result = await ref.read(playApiProvider).scanEntry(code);
      route = doorEntryRouteFor(result);
    } on PlayException catch (e) {
      // 真源 `cyToast(res.msg || fallback)`:后端给了原因就说原因。
      failure = e.message.trim().isEmpty ? fallback : e.message;
    } catch (_) {
      failure = fallback;
    }
    if (!mounted || generation != _generation) return;
    if (route != null) {
      context.go(route);
      return;
    }
    if (failure.isEmpty) failure = fallback;
    CyNativeNotice.show(context, failure);
    context.go(kHomeRoute);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider.select((auth) => (auth.user?.id, auth.loading)), (previous, next) {
      if (previous != next) {
        _generation++;
        _started = false;
      }
    });
    // 登录恢复未完成 → 等它,和 splash 同屏口径(真源 waitForAppReady)。
    final auth = ref.watch(authControllerProvider);
    if (auth.initialized && !auth.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
    return const CupertinoPageScaffold(child: SizedBox.expand());
  }
}
