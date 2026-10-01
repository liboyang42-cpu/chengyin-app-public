import '../../l10n/app_localizations.dart';
// 唤起外部地图做导航 —— 对应小程序的 `wx.openLocation`。
//
// ★ 小程序有微信内置地图,一句 `wx.openLocation({lat,lng,name,address})` 就完事。
//   App 没有这个东西:要按平台拼 URI、还要目标 App 装了才打得开。
//
// ⚠️⚠️ 这里最容易出的事故是**静默失败**:
//   iOS 上 `canLaunchUrl` 需要在 Info.plist 声明 LSApplicationQueriesSchemes,
//   漏声明就恒返回 false ——「导航」按钮点下去什么都不发生,
//   而且不报错。那正是这个项目最高频的那类问题(声称存在、实际不生效)。
//
//   所以这里设计成**必有兜底的链**,而不是「能不能打开」的判断:
//     ① 系统地图(iOS 苹果地图 / Android geo:)
//     ② 打不开 → **把地址复制到剪贴板**并如实告诉用户
//   ⇒ 任何一步走通都算成功;全不行时用户手里仍有地址,
//     而不是对着一个没反应的按钮。
//
// ★ 2026-09-15(Task 1.4 / 决策 D7)删掉了原来排在第一档的高德 `amapuri://`:
//   App 的地图已整体换成 Apple Maps,再把「在地图中打开」甩给高德就是两套坐标
//   语义、两个产品观感。iOS 这一档直接落到苹果地图,与 D7「一键在地图中打开
//   交给 Apple 地图」一致;Android 的 `geo:` 不变(D1 只降级 App 内地图组件,
//   唤起外部地图仍然可用)。

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 一次导航请求的结果。★ 分三档而不是 bool ——
/// 「打开了地图」和「只复制了地址」对用户是两件事,提示语也不同。
enum MapLaunchResult {
  /// 打开了某个地图 App。
  opened,

  /// 没打开地图,但地址已复制到剪贴板。
  copied,

  /// 连坐标都没有 —— 这不是失败,是**数据没给**。
  noCoordinates,
}

/// 系统地图。iOS 走 `maps:`,Android 走 `geo:` —— 两边都是系统级 scheme,
/// 不需要声明查询白名单。
Uri systemMapUri({
  required double lat,
  required double lng,
  required String name,
  required bool isIOS,
}) =>
    isIOS
        ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lng'
            '&q=${Uri.encodeComponent(name)}')
        : Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})');

/// 坐标有没有。★ 0/0 视为**没有** —— 后端拿不到坐标时常下发 0,
/// 直接导航过去会把人送到几内亚湾。
/// ★ NaN/Infinity 也视为没有 —— `double.tryParse('NaN')` 解析得出来,
///   放进下游距离计算会「Infinity or NaN toInt」当场炸。
bool hasCoordinates(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat != 0 &&
    lng != 0;

/// 走一遍兜底链。返回**做成了哪一档**,由调用方决定怎么提示。
///
/// [address] 用于最后一档复制;拿不到就复制「名字 + 坐标」。
Future<MapLaunchResult> launchNavigation({
  required double? lat,
  required double? lng,
  required String name,
  String? address,
  required bool isIOS,
  // ★ 注入这两个是为了能测:真跑 url_launcher 在测试环境里没有平台通道。
  Future<bool> Function(Uri)? launcher,
  Future<void> Function(String)? copy,
}) async {
  if (!hasCoordinates(lat, lng)) return MapLaunchResult.noCoordinates;
  final Future<bool> Function(Uri) open =
      launcher ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);

  final Uri target = systemMapUri(
    lat: lat!,
    lng: lng!,
    name: name,
    isIOS: isIOS,
  );
  try {
    if (await open(target)) return MapLaunchResult.opened;
  } catch (_) {
    // 系统地图被禁用 / scheme 没声明 —— 落到复制那一档,不打断。
  }

  final String text = (address ?? '').trim().isNotEmpty
      ? '$name ${address!.trim()}'
      : '$name $lat,$lng';
  await (copy ?? (String t) => Clipboard.setData(ClipboardData(text: t)))(text);
  return MapLaunchResult.copied;
}

/// 每一档对应的提示语。★ 「已复制」必须说清**为什么只能复制**,
/// 否则用户以为按钮坏了。
String mapLaunchMessage(MapLaunchResult r, {AppLocalizations? strings}) {
  switch (r) {
    case MapLaunchResult.opened:
      return '';
    case MapLaunchResult.copied:
      return strings?.mapNavigationCopied ?? '没找到可用的地图应用,地址已复制到剪贴板';
    case MapLaunchResult.noCoordinates:
      // 这是数据没给,不是操作失败 —— 别说「导航失败,请重试」,重试也没用。
      return strings?.mapNavigationNoCoordinates ?? '这个地点还没有坐标,暂时导航不了';
  }
}
