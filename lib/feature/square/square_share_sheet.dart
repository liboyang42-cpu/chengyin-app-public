import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/tracker.dart';
import '../../core/providers.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/models/square_post.dart';
import 'community_post_analytics.dart';

/// 帖文直达链接(与列表页原分享文案同源)。
String squareShareUrl(int postId) =>
    'https://api.example.invalid/square/$postId';

enum SquareShareAction { copyLink, systemShare }

/// 分享面板。
///
/// ★ 比小程序丰富在哪:小程序帖文只能把内容交给微信 `open-type="share"`;
///   App 是独立客户端,分享出口不能只有一条。这里给「复制链接」和
///   「系统分享」两条:复制走的链接与小程序分享落地页同源
///   (`/square/<id>`),系统分享仍是 SharePlus 的系统面板。
Future<void> showSquareShareSheet(
  BuildContext context,
  WidgetRef ref, {
  required SquarePost post,
  Rect? sharePositionOrigin,
  String pagePath = '/square',
}) async {
  final SquareShareAction? action =
      await showCupertinoModalPopup<SquareShareAction>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: const Text('分享这条动态'),
          actions: <Widget>[
            CupertinoActionSheetAction(
              key: const Key('square-share-copy'),
              onPressed: () =>
                  Navigator.of(sheetContext).pop(SquareShareAction.copyLink),
              child: const Text('复制链接'),
            ),
            CupertinoActionSheetAction(
              key: const Key('square-share-system'),
              onPressed: () =>
                  Navigator.of(sheetContext).pop(SquareShareAction.systemShare),
              child: const Text('系统分享'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
  if (action == null || !context.mounted) return;
  switch (action) {
    case SquareShareAction.copyLink:
      await Clipboard.setData(ClipboardData(text: squareShareUrl(post.id)));
      if (context.mounted) {
        CyNativeNotice.show(context, '链接已复制');
      }
    case SquareShareAction.systemShare:
      await shareSquarePostToSystem(
        ref,
        post: post,
        sharePositionOrigin: sharePositionOrigin,
        pagePath: pagePath,
      );
  }
}

/// 系统分享。只有**真的分享出去**才记一次 share——
/// 在自家剪贴板里放一条链接不算一次对外分发。
Future<void> shareSquarePostToSystem(
  WidgetRef ref, {
  required SquarePost post,
  Rect? sharePositionOrigin,
  String pagePath = '/square',
}) async {
  final String author = (post.memberNickname ?? '').trim().isEmpty
      ? '城瘾用户'
      : post.memberNickname!.trim();
  final String body = (post.contents ?? '').trim();
  final ShareResult result = await SharePlus.instance.share(
    ShareParams(
      subject: '$author 在城瘾发布的动态',
      text:
          '${body.isEmpty ? '来看看这条城瘾动态' : body}\n'
          '${squareShareUrl(post.id)}',
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
  if (!CommunityPostAnalytics.shouldCountShare(result.status)) return;
  try {
    await ref.read(squareApiProvider).recordShare(post.id);
    CommunityPostAnalytics.shared(
      ref.read(trackerProvider),
      post.id,
      pagePath: pagePath,
    );
  } catch (_) {
    // 系统分享已完成;统计失败不能反过来欺骗用户说分享失败。
  }
}
