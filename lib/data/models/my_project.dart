/// 我发布的一条内容(主题/活动/模板)。
/// 对齐后端 `ApiProjectController.my`(/api/project/my)。
class MyProject {
  const MyProject({
    required this.id,
    required this.bizType,
    required this.title,
    this.cover,
    this.projectType,
    this.projectTypeText,
    this.state,
    this.stateText,
    this.publishStatus,
    this.signupCount = 0,
    this.viewCount = 0,
    this.ownerType,
    this.clubId,
    this.acceptStatus,
    this.acceptStatusText,
    this.startTime,
    this.endTime,
  });

  final int id;

  /// topic / activity / template —— 决定删除与上下架调哪个端点。
  final String bizType;

  final String title;
  final String? cover;
  final String? projectType;

  /// 后端算好的类型文案,前端**不自己映射** ——
  /// 映射一份就要跟着后端改一份,还必然滞后。
  final String? projectTypeText;

  final String? state;
  final String? stateText;

  /// online / offline。
  final String? publishStatus;

  final int signupCount;
  final int viewCount;

  /// member / club。
  final String? ownerType;
  final int? clubId;
  final String? acceptStatus;
  final String? acceptStatusText;
  final String? startTime;
  final String? endTime;

  bool get isOnline =>
      publishStatus == 'online' || state == 'running' || state == 'notStarted';

  bool get isPending =>
      state == 'rejected' || state == 'draft' || state == 'pending';

  int get pendingRank => switch (state) {
    'rejected' => 0,
    'draft' => 1,
    'pending' => 2,
    _ => 9,
  };

  String get actionLabel => switch (state) {
    'draft' => '继续编辑',
    'offline' => '重新上架',
    'rejected' => '编辑重发',
    'running' || 'notStarted' => '查看数据',
    'completed' => '复盘',
    _ => '查看',
  };

  bool get canToggle =>
      state == 'running' || state == 'notStarted' || state == 'offline';

  /// 主办方「取消并退款」入口(对齐小程序 myproject decorate 的 canCancel)。
  ///
  /// · 主题:个人/商家主办可取消;俱乐部主题有岗位权限,走俱乐部「结束主题」。
  /// · 活动:商家承接生成的 activity 保持只读;且必须**已有人买票**
  ///   (没人买票直接下架/删除即可,不存在退款)。
  bool get canCancel {
    final bool onlineish =
        state == 'running' || state == 'notStarted' || state == 'offline';
    if (bizType == 'topic') return ownerType != 'club' && onlineish;
    if (bizType != 'activity') return false;
    final bool merchantActivity = ownerType == 'merchant';
    return !merchantActivity && signupCount > 0 && onlineish;
  }

  String? get scheduleLabel {
    final start = _shortDate(startTime);
    final end = _shortDate(endTime);
    if (start.isEmpty || end.isEmpty) return null;
    return '$start - $end';
  }

  bool get canDeleteByState =>
      state == 'draft' ||
      state == 'offline' ||
      state == 'rejected' ||
      state == 'completed';

  bool get canViewCandidates {
    return bizType == 'topic' &&
        const <String>{
          'clubOpen',
          'merchantOpen',
          'clubAccepted',
          'merchantAccepted',
        }.contains(acceptStatus);
  }

  /// 数据行文案。★ 报名数与浏览数都为 0 时**整行不显示** ——
  ///   「0 报名 · 0 浏览」对刚发布的内容是噪音,还显得很惨。
  String? get statsText {
    if (signupCount <= 0 && viewCount <= 0) return null;
    return <String>[
      if (signupCount > 0) '$signupCount 报名',
      if (viewCount > 0) '$viewCount 浏览',
    ].join(' · ');
  }

  /// 能不能删。★ 已有人报名的**不给删** —— 后端也会拦,
  ///   但前端提前禁用能说清原因,而不是让人点了才被拒。
  bool get deletable => signupCount <= 0;

  String? get deleteBlockedReason =>
      deletable ? null : '已有 $signupCount 人报名,不能删除';

  /// 三种已知业务各自进入对应详情；未知类型返回 null，不猜 topic。
  String? get detailRoute => switch (bizType) {
    'topic' => '/topic/$id',
    'activity' => '/activity/$id',
    'template' => '/template/$id',
    _ => null,
  };

  factory MyProject.fromJson(Map<String, dynamic> json) {
    return MyProject(
      id: (json['id'] as num?)?.toInt() ?? 0,
      bizType: (json['bizType'] as String?) ?? '',
      title: ((json['title'] as String?) ?? '').trim().isEmpty
          ? '未命名'
          : (json['title'] as String).trim(),
      cover: json['cover'] as String?,
      projectType: json['projectType']?.toString(),
      projectTypeText: json['projectTypeText'] as String?,
      state: json['state']?.toString(),
      stateText: json['stateText'] as String?,
      publishStatus: json['publishStatus'] as String?,
      signupCount: (json['signupCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      ownerType: json['ownerType'] as String?,
      clubId: (json['clubId'] as num?)?.toInt(),
      acceptStatus: json['acceptStatus'] as String?,
      acceptStatusText: json['acceptStatusText'] as String?,
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
    );
  }
}

String _shortDate(String? value) {
  final text = (value ?? '').trim();
  if (text.length < 10) return '';
  return text.substring(0, 10).replaceAll('-', '.');
}

/// 按 bizType 决定调哪组端点。
///
/// ★ 三种业务各有各的删除与上下架端点,**不能只按 topic 一套走** ——
///   拿 topic 的端点删 activity,后端会说"不存在"而不是删错东西,
///   但用户看到的是一个删不掉的条目。
class ProjectEndpoints {
  const ProjectEndpoints({required this.delete, required this.toggleStatus});

  final String delete;

  /// 上下架端点。template 用的是 updateLibraryStatus(语义是"入库/出库")。
  final String toggleStatus;

  static ProjectEndpoints? forBizType(String bizType) {
    switch (bizType) {
      case 'topic':
        return const ProjectEndpoints(
          delete: '/api/topic/delete',
          toggleStatus: '/api/topic/update_user_status',
        );
      case 'activity':
        return const ProjectEndpoints(
          delete: '/api/activity/delete',
          toggleStatus: '/api/activity/update_publish_status',
        );
      case 'template':
        return const ProjectEndpoints(
          delete: '/api/template/delete',
          toggleStatus: '/api/template/updateLibraryStatus',
        );
      default:
        // ★ 未知类型返回 null,调用方据此**不给操作按钮** ——
        //   猜一个端点去调,是在拿用户的数据赌。
        return null;
    }
  }
}
