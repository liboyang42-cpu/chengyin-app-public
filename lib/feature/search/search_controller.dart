import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/map/map_scene.dart';
import '../../core/network/login_required.dart';
import '../../core/providers.dart';
import '../../data/models/activity.dart';
import '../../data/models/category.dart';
import '../../data/models/city_node_poi.dart';
import '../../data/models/club.dart';
import '../../data/models/merchant.dart';
import '../../data/models/topic.dart';
import '../map/map_controller.dart';

/// 搜索筛选条件。结构清晰:关键词 / 分类 / 日期区间 / 价格区间 / 排序。
@immutable
class SearchFilter {
  const SearchFilter({
    this.keyword = '',
    this.categoryId,
    this.dateRange,
    this.minPrice,
    this.maxPrice,
    this.sortType = 1,
  });

  final String keyword;

  /// 选中的分类 id(对应 /api/category/list 的 id)。
  final int? categoryId;

  /// 日期区间(客户端兜底过滤;后端 list 接口无日期参数)。
  final DateTimeRange? dateRange;

  /// 价格区间(客户端兜底过滤活动 minAmount;后端 list 接口无价格参数)。
  final double? minPrice;
  final double? maxPrice;

  /// 排序:1最近 / 2最热。逐字对齐小程序 search2 筛选。
  final int? sortType;

  /// 是否有任意高级筛选生效(用于 UI 标记)。
  bool get hasAdvanced =>
      categoryId != null ||
      dateRange != null ||
      minPrice != null ||
      maxPrice != null ||
      (sortType != null && sortType != 1);

  SearchFilter copyWith({
    String? keyword,
    int? categoryId,
    bool clearCategory = false,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    double? minPrice,
    double? maxPrice,
    bool clearPrice = false,
    int? sortType,
    bool clearSort = false,
  }) {
    return SearchFilter(
      keyword: keyword ?? this.keyword,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      minPrice: clearPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPrice ? null : (maxPrice ?? this.maxPrice),
      sortType: clearSort ? null : (sortType ?? this.sortType),
    );
  }
}

/// 当前搜索筛选条件(单一真源)。
final searchFilterProvider = StateProvider.autoDispose<SearchFilter>(
  (ref) => const SearchFilter(),
);

/// 分类 chips:主题分类(type=1)。加载失败走 error 态(由 .when 处理)。
final searchCategoriesProvider = FutureProvider.autoDispose<List<Category>>((
  ref,
) async {
  return ref.watch(categoryApiProvider).list(type: '1');
});

/// 搜索历史(本地最近 10 条)。2026-08-04 产品拍板:只走本地 storage,不上后端、不建表。
/// App 无 shared_preferences,沿用既有 flutter_secure_storage(与 token/地图隐私同源)。
class SearchHistoryStore {
  SearchHistoryStore(this._storage);
  final FlutterSecureStorage _storage;

  static const String _key = 'search2_history';
  static const int _max = 10;

  Future<List<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return <String>[];
    try {
      return (jsonDecode(raw) as List<dynamic>).whereType<String>().toList();
    } on FormatException {
      return <String>[];
    }
  }

  /// 新词提到最前、去重,截断到 10 条,并写回 storage。返回最新列表。
  Future<List<String>> push(String keyword) async {
    final kw = keyword.trim();
    final next = <String>[kw, ...(await read()).where((String k) => k != kw)];
    final list = next.take(_max).toList();
    await _storage.write(key: _key, value: jsonEncode(list));
    return list;
  }

  Future<void> clear() => _storage.delete(key: _key);
}

final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return SearchHistoryStore(ref.watch(secureStorageProvider));
});

/// 搜索结果四种类型(对齐小程序 discover-search 的 TYPE_META)。
enum SearchResultType { topic, activity, club, merchant }

/// 结果页查询条件:keyword + categoryId + 客户端兜底筛选(日期/价格)。
/// 小程序 search2/index.js 把 startDate/endDate/minPrice/maxPrice 拼进跳转 URL,
/// 结果页 onLoad 再交给 discover-search 客户端过滤,这里 1:1 复刻(后端不消费这几项)。
@immutable
class SearchQuery {
  const SearchQuery({
    this.keyword = '',
    this.categoryId,
    this.startDate,
    this.endDate,
    this.minPrice,
    this.maxPrice,
  });

  final String keyword;
  final int? categoryId;

  /// 日期边界(yyyy-MM-dd),客户端过滤;null 表示不限。
  final String? startDate;
  final String? endDate;

  /// 价格边界,客户端过滤;min>0 或 max<1000 才生效(对齐小程序量程 0-1000)。
  final double? minPrice;
  final double? maxPrice;

  bool get hasFilter =>
      (startDate != null && startDate!.isNotEmpty) ||
      (endDate != null && endDate!.isNotEmpty) ||
      (minPrice != null && minPrice! > 0) ||
      (maxPrice != null && maxPrice! < 1000);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQuery &&
          other.keyword == keyword &&
          other.categoryId == categoryId &&
          other.startDate == startDate &&
          other.endDate == endDate &&
          other.minPrice == minPrice &&
          other.maxPrice == maxPrice;

  @override
  int get hashCode =>
      Object.hash(keyword, categoryId, startDate, endDate, minPrice, maxPrice);
}

/// 客户端兜底过滤:日期落区间 + 价格落区间。1:1 对齐小程序
/// utils/discover-search.js 的 matchesFilters —— 只对主题/活动生效,
/// 俱乐部/商家原样放行(它们后端也不收这几项、列表无票价)。
/// [rowDate] 是行的开始日期字符串(取 yyyy-MM-dd 前缀比较);
/// [rowPrice] 为行最低价(活动 minAmout),null 表示无价 → 跳过价格判定。
bool matchesDatePriceFilter({
  required bool appliesToType,
  required String? rowDate,
  required double? rowPrice,
  String? startBound,
  String? endBound,
  double? minPrice,
  double? maxPrice,
}) {
  if (!appliesToType) return true;
  final String? start = _ymd(startBound);
  final String? end = _ymd(endBound);
  final String? day = _ymd(rowDate);
  if ((start != null || end != null) && day != null) {
    if (start != null && day.compareTo(start) < 0) return false;
    if (end != null && day.compareTo(end) > 0) return false;
  }
  final double? minP = minPrice;
  final double? maxP = maxPrice;
  final bool applyPrice =
      (minP != null && minP > 0) || (maxP != null && maxP < 1000);
  if (applyPrice && rowPrice != null) {
    if (minP != null && minP > 0 && rowPrice < minP) return false;
    if (maxP != null && maxP < 1000 && rowPrice > maxP) return false;
  }
  return true;
}

/// 取字符串开头的 yyyy-MM-dd(与小程序 ymdOf 同口径),取不到返回 null。
final RegExp _ymdPattern = RegExp(r'^(\d{4}-\d{2}-\d{2})');
String? _ymd(String? value) => _ymdPattern.firstMatch(value ?? '')?.group(1);

/// 搜索结果一行(类型 + 展示字段),供结果页直接渲染。
@immutable
class SearchResultRow {
  const SearchResultRow({
    required this.type,
    required this.id,
    required this.title,
    required this.detail,
    this.memberId,
    this.cover,
    this.tags = const <String>[],
  });

  final SearchResultType type;
  final int id;
  final int? memberId;
  final String title;
  final String detail;
  final String? cover;
  final List<String> tags;

  String get typeLabel => switch (type) {
    SearchResultType.topic => '主题',
    SearchResultType.activity => '活动',
    SearchResultType.club => '俱乐部',
    SearchResultType.merchant => '商家',
  };
}

/// 一次搜索的全部结果(按 主题/活动/俱乐部/商家 顺序扁平化)。
@immutable
class SearchResultBundle {
  const SearchResultBundle({
    required this.rows,
    required this.counts,
    this.failedTypes = const <SearchResultType>[],
    this.loginGated = false,
  });

  final List<SearchResultRow> rows;
  final Map<SearchResultType, int> counts;

  /// 这一路请求失败的类型。对齐小程序 result/index.js 的逐请求 failed 计数:
  /// 部分失败**不吞掉**其余三路的成功结果,只有全失败才算整页错误。
  final List<SearchResultType> failedTypes;

  /// 有结果源因为「需要登录」被跳过(游客态)。页面据此提示,
  /// 不静默少给结果 —— 少给和没有是两回事。
  final bool loginGated;

  bool get isEmpty => rows.isEmpty;
  bool get hasFailure => failedTypes.isNotEmpty;
  bool get allFailed => failedTypes.length == SearchResultType.values.length;
}

/// 单路请求失败不炸整包:成功返回 (rows, null),失败返回 ([], 异常)。
/// Future.wait 是 Promise.all 语义,任一路 401 会把其余三路已拿到的
/// 结果整包丢掉(游客态实测俱乐部 401 = 结果页恒错误态,P0-1)。
Future<(List<T>, Object?)> _attempt<T>(Future<List<T>> request) async {
  try {
    return (await request, null);
  } catch (error) {
    return (<T>[], error);
  }
}

/// 结果页数据源:并发打 4 个公开接口,聚合成一行行卡片。
/// 关键词为空且无类别时不打接口(返回空),由调用方先拦。
final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResultBundle, SearchQuery>((ref, query) async {
      final kw = query.keyword.trim();
      if (kw.isEmpty && query.categoryId == null) {
        return const SearchResultBundle(rows: <SearchResultRow>[], counts: {});
      }
      final categoryId = query.categoryId?.toString();

      final topicApi = ref.watch(topicApiProvider);
      final activityApi = ref.watch(activityApiProvider);
      final clubApi = ref.watch(clubApiProvider);
      final merchantApi = ref.watch(merchantApiProvider);

      final (
        (List<Topic> topics, Object? topicsFailure),
        (List<Activity> activities, Object? activitiesFailure),
        (List<Club> clubs, Object? clubsFailure),
        (List<Merchant> merchants, Object? merchantsFailure),
      ) = await (
        _attempt(
          topicApi.list(
            keyword: kw.isEmpty ? null : kw,
            categoryId: categoryId,
            pageNum: 1,
            pageSize: 12,
          ),
        ),
        _attempt(
          activityApi.list(
            keyword: kw.isEmpty ? null : kw,
            categoryId: categoryId,
            pageNum: 1,
            pageSize: 12,
          ),
        ),
        _attempt(clubApi.searchByName(kw)),
        _attempt(merchantApi.searchByName(kw)),
      ).wait;

      // 登录门槛(2026-09-18 实测:游客打 /api/club/list 是 401,其余三源 200)
      // 不算失败:整页不该因一路要登录而哑掉,记下 loginGated 让页面给引导,
      // 其余照常渲染。真故障仍按逐路失败计(不吞掉其余三路)。
      bool loginGated = false;
      final failedTypes = <SearchResultType>[];
      for (final (SearchResultType type, Object? failure)
          in <(SearchResultType, Object?)>[
            (SearchResultType.topic, topicsFailure),
            (SearchResultType.activity, activitiesFailure),
            (SearchResultType.club, clubsFailure),
            (SearchResultType.merchant, merchantsFailure),
          ]) {
        if (failure == null) continue;
        if (isLoginRequiredError(failure)) {
          loginGated = true;
        } else {
          failedTypes.add(type);
        }
      }

      // 日期/价格是客户端兜底筛选(后端不收),口径同小程序 discover-search.matchesFilters。
      final visibleTopics = topics
          .where((Topic t) {
            return matchesDatePriceFilter(
              appliesToType: true,
              rowDate: t.startDate,
              rowPrice: null,
              startBound: query.startDate,
              endBound: query.endDate,
              minPrice: query.minPrice,
              maxPrice: query.maxPrice,
            );
          })
          .toList(growable: false);
      final visibleActivities = activities
          .where((Activity a) {
            return matchesDatePriceFilter(
              appliesToType: true,
              rowDate: a.startDate,
              rowPrice: a.minAmount,
              startBound: query.startDate,
              endBound: query.endDate,
              minPrice: query.minPrice,
              maxPrice: query.maxPrice,
            );
          })
          .toList(growable: false);

      final rows = <SearchResultRow>[
        for (final t in visibleTopics)
          SearchResultRow(
            type: SearchResultType.topic,
            id: t.id,
            title: t.name.isEmpty ? '主题' : t.name,
            detail: (t.introduction != null && t.introduction!.isNotEmpty)
                ? t.introduction!
                : '城市主题',
            cover: t.picUrl,
          ),
        for (final a in visibleActivities)
          SearchResultRow(
            type: SearchResultType.activity,
            id: a.id,
            title: a.name.isEmpty ? '活动' : a.name,
            detail: (a.addressName != null && a.addressName!.isNotEmpty)
                ? a.addressName!
                : ((a.address != null && a.address!.isNotEmpty)
                      ? a.address!
                      : '活动地点待公布'),
            cover: a.imgUrl,
          ),
        for (final c in clubs)
          SearchResultRow(
            type: SearchResultType.club,
            id: c.id,
            title: c.name.isEmpty ? '俱乐部' : c.name,
            detail: (c.description != null && c.description!.isNotEmpty)
                ? c.description!
                : '城市俱乐部',
            cover: (c.cover != null && c.cover!.isNotEmpty) ? c.cover : c.logo,
          ),
        for (final m in merchants)
          SearchResultRow(
            type: SearchResultType.merchant,
            id: m.id,
            memberId: m.memberId,
            title: (m.name == null || m.name!.isEmpty) ? '商家' : m.name!,
            detail: (m.cityRole != null && m.cityRole!.isNotEmpty)
                ? m.cityRole!
                : ((m.address != null && m.address!.isNotEmpty)
                      ? m.address!
                      : ((m.slogan != null && m.slogan!.isNotEmpty)
                            ? m.slogan!
                            : ((m.description != null &&
                                      m.description!.isNotEmpty)
                                  ? m.description!
                                  : '合作商家'))),
            cover: (m.coverImage != null && m.coverImage!.isNotEmpty)
                ? m.coverImage
                : m.logo,
            tags: _merchantTags(m.tags),
          ),
      ];

      final counts = <SearchResultType, int>{};
      for (final r in rows) {
        counts[r.type] = (counts[r.type] ?? 0) + 1;
      }
      return SearchResultBundle(
        rows: rows,
        counts: counts,
        failedTypes: failedTypes,
        loginGated: loginGated,
      );
    });

/// 商家 tags 字段:逗号/分号分隔的串或 JSON 数组,取前 2 个当卡片标签。
List<String> _merchantTags(String? raw) {
  if (raw == null || raw.isEmpty) return <String>[];
  final trimmed = raw.trim();
  if (trimmed.startsWith('[')) {
    try {
      final parsed = jsonDecode(trimmed);
      return (parsed as List<dynamic>).whereType<String>().take(2).toList();
    } on FormatException {
      return <String>[];
    }
  }
  return trimmed
      .split(RegExp(r'[,;]'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .take(2)
      .toList();
}

@immutable
class CityNodeSearchQuery {
  const CityNodeSearchQuery({
    this.keyword = '',
    this.categoryId,
    this.tag,
    this.cityRole,
    this.center,
    this.sortType = 1,
    this.minPrice,
    this.maxPrice,
    this.dateRange,
  });

  final String keyword;
  final int? categoryId;
  final String? tag;
  final String? cityRole;
  final MapCoordinate? center;
  final int sortType;
  final double? minPrice;
  final double? maxPrice;
  final DateTimeRange? dateRange;

  @override
  bool operator ==(Object other) =>
      other is CityNodeSearchQuery &&
      other.keyword == keyword &&
      other.categoryId == categoryId &&
      other.tag == tag &&
      other.cityRole == cityRole &&
      other.center == center &&
      other.sortType == sortType &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.dateRange == dateRange;

  @override
  int get hashCode => Object.hash(
    keyword,
    categoryId,
    tag,
    cityRole,
    center,
    sortType,
    minPrice,
    maxPrice,
    dateRange,
  );
}

@immutable
class CityNodeSearchResult {
  const CityNodeSearchResult({
    required this.center,
    required this.activities,
    required this.nodes,
    this.activitiesFailure,
    this.merchantNodesFailure,
  });

  final MapCoordinate center;
  final List<Activity> activities;
  final List<CityNodePoi> nodes;

  /// 活动/商家节点两路各自是否失败(小程序 searchmap:listState 看活动、
  /// merchantNodeError 看节点,一路 401 不拖垮另一路,地图常驻不消失)。
  final Object? activitiesFailure;
  final Object? merchantNodesFailure;

  int get totalCount => activities.length + nodes.length;
  int get noCoordinateActivityCount =>
      activities.where((activity) => !activity.hasCoordinates).length;

  MapScene get scene => MapScene.build(
    userLocation: center,
    points: <MapPoint>[
      for (final Activity activity in activities)
        if (activity.hasCoordinates)
          MapPoint(
            id: 'activity-${activity.id}',
            latitude: activity.latitude!,
            longitude: activity.longitude!,
            title: activity.name,
            subtitle: activity.addressName ?? activity.address,
            topicId: activity.topicId,
          ),
      for (final CityNodePoi node in nodes)
        if (node.hasCoords)
          MapPoint(
            id: 'city-node-${node.poiId}',
            latitude: node.lat!,
            longitude: node.lng!,
            title: node.name,
            subtitle: node.merchantName,
            nodeId: node.poiId,
            fenceRadiusMeters: node.radiusM?.toDouble(),
          ),
    ],
  );
}

/// 用户明确点“使用当前位置”后才读取本 provider，避免搜索页静默申请定位。
final cityNodeSearchProvider = FutureProvider.autoDispose
    .family<CityNodeSearchResult, CityNodeSearchQuery>((ref, query) async {
      final MapCoordinate center;
      if (query.center case final movedCenter?) {
        center = movedCenter;
      } else {
        center = await ref.watch(currentMapLocationProvider.future);
      }
      final String? startBound = query.dateRange == null
          ? null
          : _wireDate(query.dateRange!.start);
      final String? endBound = query.dateRange == null
          ? null
          : _wireDate(query.dateRange!.end);
      final (
        (List<Activity> activities, Object? activitiesFailure),
        (List<CityNodePoi> nodes, Object? merchantNodesFailure),
      ) = await (
        _attempt(
          // A-02:日期/价格**不发后端**(真源 utils/discover-search.js:116
          // 「filters 仅客户端消费:/api/activity/list 没有 minPrice/startDate」),
          // 取回后用 matchesDatePriceFilter 兜底过滤。
          ref
              .watch(activityApiProvider)
              .list(
                keyword: query.keyword.trim().isEmpty
                    ? null
                    : query.keyword.trim(),
                categoryId: query.categoryId?.toString(),
                sortType: query.sortType.toString(),
                longitude: center.longitude.toString(),
                latitude: center.latitude.toString(),
                pageNum: 1,
                pageSize: 50,
              ),
        ),
        _attempt(
          ref
              .watch(cityNodeApiProvider)
              .nearby(
                lat: center.latitude,
                lng: center.longitude,
                radius: 20000,
                keyword: query.keyword,
                categoryId: query.categoryId,
                tag: query.tag,
                cityRole: query.cityRole,
              ),
        ),
      ).wait;
      // A-02(同小程序 searchmap):日期/价格后端不消费,取回后用 matchesFilters
      // 同口径客户端过滤,不各写一套。
      final visibleActivities = activities
          .where(
            (Activity a) => matchesDatePriceFilter(
              appliesToType: true,
              rowDate: a.startDate,
              rowPrice: a.minAmount,
              startBound: startBound,
              endBound: endBound,
              minPrice: query.minPrice,
              maxPrice: query.maxPrice,
            ),
          )
          .toList(growable: false);
      return CityNodeSearchResult(
        center: center,
        activities: visibleActivities,
        nodes: _sortNodesByKnownDistance(nodes),
        activitiesFailure: activitiesFailure,
        merchantNodesFailure: merchantNodesFailure,
      );
    });

String _wireDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 地图搜索必须只依赖后端基于当次中心点返回的 distance。
/// 没有距离的节点放在末尾，且保留服务端原顺序；不用缺失坐标伪算 0m。
List<CityNodePoi> _sortNodesByKnownDistance(List<CityNodePoi> nodes) {
  final indexed = nodes.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final double? leftDistance = _knownDistance(left.$2.distance);
    final double? rightDistance = _knownDistance(right.$2.distance);
    if (leftDistance == null && rightDistance == null) {
      return left.$1.compareTo(right.$1);
    }
    if (leftDistance == null) return 1;
    if (rightDistance == null) return -1;
    final int byDistance = leftDistance.compareTo(rightDistance);
    return byDistance != 0 ? byDistance : left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

double? _knownDistance(double? distance) =>
    distance != null && distance.isFinite && distance >= 0 ? distance : null;
