import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/completed_play.dart';
import '../auth/login_gate.dart';

final myCompletedPlaysProvider =
    FutureProvider.autoDispose<List<CompletedPlay>>((ref) {
      return ref.watch(playApiProvider).myCompleted();
    });

/// 后端是否以「未登录」拒绝了这次请求。只认 401 —— 把断网也算成要登录,
/// 会把断网的人反复推去登录页,登完还是失败。
/// (判据同 activity_detail_page;共享层的那份在 PR #183,landed 后换用。)
bool _isUnauthorized(Object e) =>
    e is DioException && e.response?.statusCode == 401;

/// 非 401 的读失败副文案:后端给了中文原话就用原话,只有 dio 自己的英文栈
/// (`DioException [bad response] ... developer.mozilla.org`)才换成人话。
String _errorSub(Object e) {
  if (e is! DioException) return e.toString().replaceFirst('Exception: ', '');
  final Object? data = e.response?.data;
  final String msg = data is Map ? (data['msg']?.toString().trim() ?? '') : '';
  return msg.isEmpty ? '网络开了点小差' : msg;
}

/// 我走过的局。对齐小程序 `pages/play` 的 my-completed。
class MyPlaysPage extends ConsumerWidget {
  const MyPlaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCompletedPlaysProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('我走过的')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => Semantics(
              liveRegion: true,
              label: '正在加载我走过的路线',
              child: const ExcludeSemantics(
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
            error: (Object e, _) => _isUnauthorized(e)
                // ★ 游客从设置点进来必然走到这里:路由对游客开放,而后端
                //   `/api/play/my-completed` 对无 token 的请求返回 401(生产实测
                //   2026-09-18:`HTTP 401 {"msg":"登录状态已失效，请重新登录"}`)。
                //   原样抛 dio 异常 = 整屏英文堆栈 + MDN 链接,而「重试」按多少次
                //   都还是 401,是条死路。改成可恢复的登录引导(写法同活动详情页)。
                ? StatusView(
                    message: '登录后查看走过的路线',
                    sub: '这一步需要登录,登录完会自动回到这一页。',
                    icon: CupertinoIcons.lock,
                    large: true,
                    retryLabel: '去登录',
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      ref.invalidate(myCompletedPlaysProvider);
                    },
                  )
                : StatusView(
                    message: '我的参与没能加载出来',
                    sub: _errorSub(e),
                    large: true,
                    onRetry: () => ref.invalidate(myCompletedPlaysProvider),
                  ),
            data: (List<CompletedPlay> rows) {
              if (rows.isEmpty) {
                return const StatusView(
                  message: '还没走过',
                  sub: '完成一局之后,这里会记下你走过的路线',
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(myCompletedPlaysProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  itemBuilder: (_, int i) {
                    final c = rows[i];
                    final route = c.route;
                    return CyCell(
                      title: c.name,
                      // total 为 0 时不显示「0/0」。
                      subtitle: c.progressText,
                      // ★ 拿不到可用 id 就**不给点** —— 跳到 /activity/0
                      //   会进一个永远加载失败的页面。
                      onTap: route == null ? null : () => context.push(route),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
