import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../core/map/map_launcher.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_api.dart';
import '../../data/api/roam_api.dart';
import '../../data/models/club.dart';
import '../../data/models/pricing.dart';
import '../../data/models/roam_merchant_info.dart';
import '../auth/login_gate.dart';

/// partner 页的失败分档(与 `topic_pricing_page._failureMessage` 同一口径):
/// 后端业务拒绝的中文短句照原话放行,承载层异常([DioException])只给兜底文案
/// —— 原始 DioException 的 toString 是英文堆栈 + MDN 链接,不能画到屏幕上。
String partnerFailureMessage(Object error, String fallback) {
  if (error is DioException) return fallback;
  final String text = error.toString().replaceFirst('Exception: ', '').trim();
  final bool looksLikeCopy =
      text.isNotEmpty &&
      text.length <= 60 &&
      !text.contains('\n') &&
      !text.contains('http');
  return looksLikeCopy ? text : fallback;
}

class TopicPricingPartnerLookup {
  const TopicPricingPartnerLookup({
    required this.toType,
    required this.toId,
    this.topicId,
  });

  final String toType;
  final int? toId;
  final int? topicId;

  /// 与小程序 `onLoad` 的参数校验同口径:toType 二选一,toId/topicId 都是正整数。
  bool get isValid =>
      (toType == 'club' || toType == 'merchant') &&
      _isPositive(toId) &&
      _isPositive(topicId);

  static bool _isPositive(int? value) => value != null && value > 0;

  @override
  bool operator ==(Object other) =>
      other is TopicPricingPartnerLookup &&
      other.toType == toType &&
      other.toId == toId &&
      other.topicId == topicId;

  @override
  int get hashCode => Object.hash(toType, toId, topicId);
}

class PricingPartnerDetailRow {
  const PricingPartnerDetailRow({
    required this.label,
    required this.value,
    this.opensLocation = false,
  });

  final String label;
  final String value;
  final bool opensLocation;
}

class PricingPartnerProfile {
  const PricingPartnerProfile({
    required this.name,
    this.description,
    this.details = const <PricingPartnerDetailRow>[],
    this.memberId,
    this.latitude,
    this.longitude,
    this.address,
  });

  final String name;
  final String? description;
  final List<PricingPartnerDetailRow> details;
  final int? memberId;
  final double? latitude;
  final double? longitude;
  final String? address;
}

/// 一次加载的两段产物:本主题生效阵容里的条款 + 合作方公开档案。
class TopicPricingPartnerData {
  const TopicPricingPartnerData({required this.terms, required this.profile});

  final PricingLineupTerms terms;
  final PricingPartnerProfile profile;
}

typedef TopicPricingPartnerMapLauncher =
    Future<MapLaunchResult> Function({
      required double? lat,
      required double? lng,
      required String name,
      String? address,
      required bool isIOS,
    });

final topicPricingPartnerMapLauncherProvider =
    Provider<TopicPricingPartnerMapLauncher>((_) => launchNavigation);

/// 两步链,和小程序 `loadProfile → loadPublicProfile` 一致:
/// ① `POST /api/topic/pricing/preview`(subType=self)取本主题阵容,找到这一行,
///   条款非法就停;② 再按 toType 拉公开档案。条款**不来自路由 query** ——
///   链接参数会被用户随手改,结算是资金口径,只认服务器。
final topicPricingPartnerProvider = FutureProvider.autoDispose
    .family<TopicPricingPartnerData, TopicPricingPartnerLookup>((
      ref,
      lookup,
    ) async {
      final PricingPreview preview;
      try {
        preview = await ref
            .read(topicApiProvider)
            .pricingPreview(
              topicId: lookup.topicId!,
              subType: PricingSubType.self,
            );
      } catch (error) {
        // ★ 401 是后端**有意**拒绝(游客必撞),原样抛给页面换登录引导,
        //   不能被兜底成「加载失败,请重试」的死路。
        if (isUnauthorizedError(error)) rethrow;
        throw Exception(partnerFailureMessage(error, '合作条款加载失败，请稍后重试。'));
      }

      PricingLineupRow? row;
      for (final PricingLineupRow candidate in preview.lineup) {
        if (candidate.toType == lookup.toType &&
            candidate.toId == lookup.toId) {
          row = candidate;
          break;
        }
      }
      if (row == null) {
        throw Exception('该合作方不在当前主题的生效阵容中，条款无法展示。');
      }
      final PricingLineupTerms? terms = row.terms;
      if (terms == null) {
        throw Exception('合作条款信息不完整，请稍后重试。');
      }

      final PricingPartnerProfile profile = await _loadPartnerProfile(
        ref,
        lookup,
      );
      return TopicPricingPartnerData(terms: terms, profile: profile);
    });

Future<PricingPartnerProfile> _loadPartnerProfile(
  Ref ref,
  TopicPricingPartnerLookup lookup,
) async {
  final int id = lookup.toId!;
  if (lookup.toType == 'club') {
    try {
      final Club club = await ref.read(clubApiProvider).detail(id);
      if (club.name.trim().isEmpty) {
        throw Exception('合作俱乐部资料缺少名称，请稍后重试。');
      }
      return PricingPartnerProfile(
        name: club.name.trim(),
        description: _nonEmpty(club.description),
        details: <PricingPartnerDetailRow>[
          if (_nonEmpty(club.leaderName) case final String leader)
            PricingPartnerDetailRow(label: '主理人', value: leader),
          if (_nonEmpty(club.city ?? club.address) case final String city)
            PricingPartnerDetailRow(label: '所在城市', value: city),
          if (_nonEmpty(club.clubType) case final String type)
            PricingPartnerDetailRow(label: '俱乐部类型', value: type),
          PricingPartnerDetailRow(label: '成员数', value: '${club.memberCount} 人'),
          if (club.level > 0)
            PricingPartnerDetailRow(label: '等级', value: 'L${club.level}'),
        ],
      );
    } catch (error) {
      if (isUnauthorizedError(error) ||
          error is ClubApiException ||
          error.toString().contains('资料缺少名称')) {
        rethrow;
      }
      throw Exception(partnerFailureMessage(error, '未能读取合作俱乐部资料，请稍后重试。'));
    }
  }

  if (lookup.toType == 'merchant') {
    try {
      final (RoamMerchantInfo merchant, _) = await ref
          .read(roamApiProvider)
          .publicMerchantDetail(id);
      final String name = merchant.name?.trim() ?? '';
      if (name.isEmpty) {
        throw Exception('承接商家资料缺少名称，请稍后重试。');
      }
      return PricingPartnerProfile(
        name: name,
        memberId: merchant.memberId,
        description: _nonEmpty(merchant.description),
        latitude: merchant.latitude,
        longitude: merchant.longitude,
        address: _nonEmpty(merchant.address),
        details: <PricingPartnerDetailRow>[
          if (merchant.catNames.isNotEmpty)
            PricingPartnerDetailRow(label: '品类', value: merchant.catNames),
          if (merchant.capacity != null)
            PricingPartnerDetailRow(
              label: '可容纳',
              value: '${merchant.capacity} 人',
            ),
          if (_nonEmpty(merchant.suitActivityTypes)
              case final String activityTypes)
            PricingPartnerDetailRow(label: '适合路线', value: activityTypes),
          if (_nonEmpty(merchant.availableTime) case final String time)
            PricingPartnerDetailRow(label: '可承接时段', value: time),
          if (merchant.chargeType != null)
            PricingPartnerDetailRow(label: '收费方式', value: merchant.chargeText),
          if (_nonEmpty(merchant.demand) case final String demand)
            PricingPartnerDetailRow(label: '合作诉求', value: demand),
          if (_nonEmpty(merchant.businessTime) case final String businessTime)
            PricingPartnerDetailRow(label: '营业时间', value: businessTime),
          if (_nonEmpty(merchant.address) case final String address)
            PricingPartnerDetailRow(
              label: '门店地址',
              value: address,
              opensLocation: hasCoordinates(
                merchant.latitude,
                merchant.longitude,
              ),
            ),
        ],
      );
    } catch (error) {
      if (isUnauthorizedError(error) ||
          error is RoamApiException ||
          error.toString().contains('资料缺少名称')) {
        rethrow;
      }
      throw Exception(partnerFailureMessage(error, '未能读取承接商家资料，请稍后重试。'));
    }
  }

  throw Exception('合作方类型无效，无法读取档案。');
}

String? _nonEmpty(String? value) {
  final String text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

class TopicPricingPartnerPage extends ConsumerWidget {
  const TopicPricingPartnerPage({
    super.key,
    this.toType = '',
    this.toId,
    this.topicId,
  });

  final String toType;
  final int? toId;
  final int? topicId;

  TopicPricingPartnerLookup get lookup =>
      TopicPricingPartnerLookup(toType: toType, toId: toId, topicId: topicId);

  String get _pageTitle => switch (toType) {
    'club' => '合作俱乐部',
    'merchant' => '承接商家',
    _ => '合作方',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    return CupertinoPageScaffold(
      backgroundColor: background,
      navigationBar: CupertinoNavigationBar(middle: Text(_pageTitle)),
      child: SafeArea(
        bottom: false,
        child: !lookup.isValid
            ? _InvalidLink(onBack: () => Navigator.maybePop(context))
            : ref
                  .watch(topicPricingPartnerProvider(lookup))
                  .when(
                    loading: () => const Center(
                      child: CupertinoActivityIndicator(radius: 14),
                    ),
                    error: (Object error, StackTrace _) =>
                        isUnauthorizedError(error)
                        // 401 = 后端要登录,不是故障(生产实测:游客 /api/club/detail → 401)。
                        ? StatusView(
                            message: '登录后查看合作方档案',
                            sub: '这一步需要登录,登录完会自动回到这一页。',
                            icon: Icons.lock_outline,
                            retryLabel: '去登录',
                            onRetry: () async {
                              if (!await requireLogin(context, ref)) return;
                              ref.invalidate(
                                topicPricingPartnerProvider(lookup),
                              );
                            },
                          )
                        : StatusView(
                            message: '合作信息加载失败',
                            sub: error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                            icon: CupertinoIcons.exclamationmark_triangle,
                            onRetry: () => ref.invalidate(
                              topicPricingPartnerProvider(lookup),
                            ),
                          ),
                    data: (TopicPricingPartnerData data) => _PartnerContent(
                      profile: data.profile,
                      terms: data.terms,
                      lookup: lookup,
                    ),
                  ),
      ),
    );
  }
}

class _PartnerContent extends ConsumerWidget {
  const _PartnerContent({
    required this.profile,
    required this.terms,
    required this.lookup,
  });

  final PricingPartnerProfile profile;
  final PricingLineupTerms terms;
  final TopicPricingPartnerLookup lookup;

  void _openProfile(BuildContext context) {
    if (lookup.toType == 'club') {
      context.push('/club/${lookup.toId}');
      return;
    }
    final int? memberId = profile.memberId;
    if (memberId == null || memberId <= 0) {
      CyNativeNotice.show(context, '商家资料还没加载好');
      return;
    }
    context.push('/user/$memberId');
  }

  Future<void> _openLocation(BuildContext context, WidgetRef ref) async {
    final MapLaunchResult result =
        await ref.read(topicPricingPartnerMapLauncherProvider)(
          lat: profile.latitude,
          lng: profile.longitude,
          name: profile.name,
          address: profile.address,
          isIOS: defaultTargetPlatform == TargetPlatform.iOS,
        );
    if (!context.mounted) return;
    final String message = mapLaunchMessage(result);
    if (message.isNotEmpty) CyNativeNotice.show(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PricingPartnerDetailRow> details = profile.details;
    return CupertinoScrollbar(
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              '阵容已锁定，以下为该合作方在本主题中的结算条款。',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ),
          CupertinoListSection.insetGrouped(
            children: <Widget>[
              CupertinoListTile(
                title: Text(
                  profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                  onPressed: () => _openProfile(context),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('查看'),
                      SizedBox(width: 3),
                      Icon(CupertinoIcons.chevron_forward, size: 16),
                    ],
                  ),
                ),
              ),
              if (_nonEmpty(profile.description) case final String description)
                CupertinoListTile(title: Text(description)),
              if (details.isEmpty && _nonEmpty(profile.description) == null)
                const CupertinoListTile(
                  title: Text(
                    '暂无公开档案信息',
                    style: TextStyle(color: CupertinoColors.secondaryLabel),
                  ),
                ),
              ...details.map(
                (PricingPartnerDetailRow row) => _KeyValueTile(
                  key: row.opensLocation
                      ? const Key('partner-open-location')
                      : null,
                  label: row.label,
                  value: row.value,
                  onTap: row.opensLocation
                      ? () => _openLocation(context, ref)
                      : null,
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('合作条款'),
            footer: Text(terms.footnote),
            children: <Widget>[
              _KeyValueTile(label: '结算方式', value: terms.settlementName),
              if (terms.shareMode == 1)
                _KeyValueTile(label: '分成比例', value: terms.shareRateDisplay),
              if (terms.shareMode == 2)
                _KeyValueTile(label: '固定合作费', value: terms.fixedFeeDisplay),
              _KeyValueTile(label: '冻结时间', value: '开售即冻结'),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyValueTile extends StatelessWidget {
  const _KeyValueTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      onTap: onTap,
      trailing: onTap == null
          ? null
          : const Icon(CupertinoIcons.location, size: 18),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: CupertinoColors.secondaryLabel),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _InvalidLink extends StatelessWidget {
  const _InvalidLink({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => StatusView(
    icon: CupertinoIcons.question_circle,
    message: '合作链接已失效',
    sub: '合作链接无效或已失效，请从主题定价页重新进入。',
    retryLabel: '返回上一页',
    onRetry: onBack,
  );
}
