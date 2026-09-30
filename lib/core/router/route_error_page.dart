import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../widgets/status_view.dart';

/// 未匹配深链 / 路由处理抛异常时的人话错误页。
///
/// go_router 17 默认把 `GoException` 原文铺满整屏(如
/// `no routes for location: /xxx`),用户读不懂(B1 模拟器报告 P2)。
/// 这里给错误态三件套:主标说「没有什么」、副标说「下一步做什么」、
/// 退不出去时 [StatusView] 自带「回首页」。**不给「重试」**——
/// 根本不存在的路由重试永远是死路(同 nearby 401 假报错的教训)。
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.error});

  final GoException? error;

  @override
  Widget build(BuildContext context) {
    // 无匹配路由的判定:go_router 17 在 configuration.dart 里造
    // `GoException('no routes for location: $uri')`;其余都是中途异常。
    final bool notFound =
        error == null || error!.message.startsWith('no routes for location');
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('页面打不开')),
      child: SafeArea(
        child: StatusView(
          large: true,
          icon: CupertinoIcons.question_circle,
          message: notFound ? '这个页面找不到了' : '这个页面打不开',
          sub: notFound ? '链接可能过期或打错了,从首页继续逛' : '这个页面遇到了问题,从首页继续逛',
        ),
      ),
    );
  }
}
