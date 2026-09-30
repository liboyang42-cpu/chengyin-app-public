import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';

/// 项目玩家名单:谁要来 / 谁还没来。
///
/// ★ 后端注释:「商家开店前想知道的是『谁要来、谁还没来』,不是『已售 24 份』
///   —— 所以这里给名单不给统计口径的分析」。
///   所以这页的主体是**名单**,summary 只做一行小字,不做大数字仪表盘。
///
/// ★★ 联系方式给不给判在 service(主办方自办 **且** 玩家给过当前版本的数据共享同意)。
///   拿到就显示、没拿到就不显示 —— **前端不做脱敏**:
///   后端原话「前端过滤等于把号码先发出去再假装没发」。
///
/// ★★ 看不到号码时必须显示后端给的 `contactHint`。
///   后端原话:「不能只给一个 false 就完事:商家会以为是 bug。说清为什么、以及该找谁」。
final projectPlayersProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int?>((ref, topicId) {
      return ref.read(myProjectApiProvider).projectPlayers(topicId: topicId);
    });

class ProjectPlayersPage extends ConsumerWidget {
  const ProjectPlayersPage({super.key, this.topicId});
  final int? topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectPlayersProvider(topicId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('玩家名单')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const CySkeleton(),
            error: (Object e, StackTrace st) => StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: '名单没读出来',
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () => ref.invalidate(projectPlayersProvider(topicId)),
            ),
            data: (Map<String, dynamic> d) => _body(context, d),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> d) {
    final List<Map<String, dynamic>> rows =
        ((d['rows'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
    final Map<String, dynamic> summary =
        (d['summary'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String? hint = d['contactHint']?.toString();
    final TextTheme t = Theme.of(context).textTheme;
    final CyPalette p = CyPalette.of(context);

    int n(Object? v) => v is num ? v.toInt() : 0;

    if (rows.isEmpty) {
      return const StatusView(
        icon: CupertinoIcons.person,
        message: '还没有人报名',
        sub: '有人买票后,这里会显示谁要来、谁已经到店',
        large: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        // summary 只做一行小字 —— 这页的主体是名单不是统计。
        Text(
          '已付 ${n(summary['paidCount'])} 人 · '
          '已到 ${n(summary['arrivedCount'])} · '
          '未到 ${n(summary['pendingCount'])}'
          '${n(summary['refundedCount']) > 0 ? ' · 已退 ${n(summary['refundedCount'])}' : ''}',
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        ),
        if (hint != null && hint.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: p.bgSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            ),
            // ★ 这句话是后端给的,原样显示。自己写「暂无权限」的话,
            //   商家不知道该去找谁。
            child: Text(hint, style: t.bodySmall),
          ),
        ],
        const SizedBox(height: CyTokens.space3),
        ...rows.map((Map<String, dynamic> r) => _row(context, r)),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final TextTheme t = Theme.of(context).textTheme;
    final CyPalette p = CyPalette.of(context);
    final String state = (r['state'] ?? 'pending').toString();
    // ★ 号码拿到就显示、没拿到就整行不显示 —— 不做脱敏、不放占位。
    final String? phone = r['phone']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text((r['name'] ?? '玩家').toString(), style: t.titleSmall),
                if ((r['ticketName'] ?? '').toString().isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    r['ticketName'].toString(),
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
                if (phone != null && phone.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(phone, style: t.bodySmall),
                ],
              ],
            ),
          ),
          Text(
            _stateText(state),
            style: t.labelSmall?.copyWith(color: _stateColor(state, p)),
          ),
        ],
      ),
    );
  }

  /// 三态照后端的 state 走。**「已退款」必须单独一态** ——
  /// 混进「未到」的话,商家会一直等一个不会来的人。
  static String _stateText(String s) {
    switch (s) {
      case 'arrived':
        return '已到店';
      case 'refunded':
        return '已退款';
      default:
        return '未到店';
    }
  }

  static Color _stateColor(String s, CyPalette p) {
    switch (s) {
      case 'arrived':
        return p.statusSuccess;
      case 'refunded':
        return p.textTertiary;
      default:
        return p.textSecondary;
    }
  }
}
