import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 发布能力快照(`/api/publish/home`)。
///
/// ★★ 小程序把它喂给发布弹窗,判据写在组件注释里:
///   「卡3 活动锁判据 = role === club;**role 缺省按 player(fail-closed 锁)**」。
///   ⇒ 拿不到身份时**按最小权限处理**,而不是放行。
///
/// ★★ 锁态的呈现也有讲究:小程序**换一整张卡**说清
///   「仅俱乐部主理人可发布 / 成为主理人后解锁」——
///   不是把按钮灰掉了事。灰按钮不告诉人怎么才能用。
class PublishCapability {
  const PublishCapability({
    this.role = 'player',
    this.isMerchant = false,
    this.maxThemes,
    this.themesOnline = 0,
    this.themesRemaining,
    this.canSimplePublish = true,
    this.canProPublish = true,
  });

  /// player / club / merchant。★ 缺省 player = 最小权限。
  final String role;
  final bool isMerchant;

  /// 主题上限。★ **null = 不限**,不是 0。
  ///   兜 0 会让「不限」显示成「一个都不能发」。
  final int? maxThemes;

  final int themesOnline;

  /// 还能发几个。★ 同样 **null = 不限**。
  final int? themesRemaining;

  /// 主题两种创建能力。小程序只在后端明确下发 false 时拦截；
  /// permission 缺失仍保留普通玩家的发布主题入口。
  final bool canSimplePublish;
  final bool canProPublish;

  bool get isClubLeader => role == 'club';

  /// 配额是不是满了。★ 只有**明确拿到 0** 才算满 ——
  ///   拿不到(null)是「不限或未知」,不能当成满而把入口锁掉。
  bool get quotaExhausted => themesRemaining != null && themesRemaining! <= 0;

  /// 配额那行怎么说。拿不到就不说,别编一个数。
  String? get quotaText {
    if (themesRemaining == null) return null;
    if (themesRemaining! <= 0) {
      return '已达上限($themesOnline/${maxThemes ?? '-'}),下架一个才能再发';
    }
    return '还能发 $themesRemaining 个';
  }

  factory PublishCapability.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> q =
        (json['quota'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> permission =
        (json['permission'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String role = switch ((json['role'] ?? '').toString()) {
      'club' => 'club',
      'merchant' => 'merchant',
      _ => 'player',
    };
    int? n(Object? v) => v is num ? v.toInt() : null;
    return PublishCapability(
      // ★ fail-closed:认不出的身份一律按 player。
      role: role,
      // 小程序优惠券卡的主判据是 role === merchant；复合身份快照的
      // isMerchant=true 也保留，避免俱乐部主理人兼商家时被错锁。
      isMerchant: role == 'merchant' || json['isMerchant'] == true,
      maxThemes: n(q['maxThemes']),
      themesOnline: n(q['themesOnline']) ?? 0,
      themesRemaining: n(q['themesRemaining']),
      canSimplePublish: permission['canSimplePublish'] != false,
      canProPublish: permission['canProPublish'] != false,
    );
  }
}

/// ★ 拿不到能力快照时落**最小权限**的默认值,而不是抛错让整页变错误页 ——
///   发布能力是个附加信息,拉不到不该挡住浏览。
final publishCapabilityProvider = FutureProvider.autoDispose<PublishCapability>(
  (Ref ref) async {
    try {
      final data = await ref.watch(myProjectApiProvider).publishHome();
      return PublishCapability.fromJson(data);
    } catch (_) {
      return const PublishCapability();
    }
  },
);
