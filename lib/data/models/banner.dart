/// 首页轮播图。对齐后端 SysBanner / `/api/common/banner`。
/// linkType:0无事件 1单页详情 2跳转H5 3活动详情 4主题详情;dataId 为对应 ID/链接。
class HomeBanner {
  HomeBanner({
    required this.id,
    this.picUrl,
    this.linkType = 0,
    this.dataId,
    this.contents,
  });

  final int id;
  final String? picUrl;
  final int linkType;

  /// H5链接 / 活动ID / 主题ID(按 linkType 解释)。
  final String? dataId;

  /// linkType==1 时的单页详情内容。
  final String? contents;

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
    id: (json['id'] as num?)?.toInt() ?? 0,
    picUrl: json['picUrl'] as String?,
    linkType: (json['linkType'] as num?)?.toInt() ?? 0,
    dataId: json['dataId'] as String?,
    contents: json['contents'] as String?,
  );
}
