import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/template.dart';
import '../models/template_draft.dart';
import '../models/topic_template.dart';

/// 玩法模板。对齐后端 `ApiTemplateController`(/api/template)。
class TemplateApi {
  TemplateApi(this._client);
  final DioClient _client;

  /// 模板列表:`POST /api/template/list`。
  /// 公共模板库列表。
  ///
  /// ★ [packType] 不传 = 看全部形态。后端对认不出的值也按不过滤处理,
  ///   两端同口径 —— 别在客户端偷偷兜成 0,那会让用户以为筛选生效了。
  Future<List<PlayTemplate>> list({
    String? keyword,
    int? categoryId,
    int? packType,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/list',
      data: FormData.fromMap(<String, dynamic>{
        'keyword': ?keyword,
        // ⚠️ 后端形参名是 category_id(蛇形),这里发的是驼峰 —— Spring 按名绑定,
        //   **这条筛选一直没生效**,列表始终返回全部。零报错零告警。
        //   本批刻意不在这里顺手改:那是行为变化(原本"显示全部"的列表会开始真筛选),
        //   两端都受影响,该有自己的改动与验证。已单独记为待办。
        'categoryId': ?categoryId?.toString(),
        // ★ 新增的形态筛选用蛇形,与后端形参名逐字一致 —— 别重蹈上面那条的覆辙。
        'pack_type': ?packType?.toString(),
      }),
    );
    return _rows(resp.data ?? <String, dynamic>{});
  }

  /// 主题模板货架:`POST /api/template/topic-template/list`。
  ///
  /// 对齐小程序 `pages/template/index.js:609`(「主题」tab 的数据源):
  /// 方法 POST、**空 body**(原文 `data: {}`),回包 `data` 直接是数组
  /// (那边判的条件是 `isRecordList(res.data)`)。
  ///
  /// ★ 与 [list] 是两个实体:这里是「一条路线」的整包主题(cms_topic,
  ///   is_template=1),`list` 是「一个地点上的一次互动」的玩法。
  ///   复制成自己的草稿走 `/api/template/topic-template/use`。
  ///
  /// ⚠️ body 用空 JSON 对象(与同页的 `/api/template/homeData` 一致 ——
  ///   那条在 `PublishApi.templateHomeSections`)—— 这条接口没有任何入参,
  ///   两个 tab 拉的都是全量,分页/排序不存在。
  Future<List<TopicTemplate>> topicTemplateList() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/topic-template/list',
      data: <String, dynamic>{},
    );
    return _list(
      resp.data ?? <String, dynamic>{},
      TopicTemplate.fromJson,
      fallbackMessage: '主题模板加载失败',
    );
  }

  /// 我的模板:`POST /api/template/my-list`。
  Future<List<PlayTemplate>> myList() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/my-list',
      data: FormData.fromMap(<String, dynamic>{
        'is_quote': '',
        'keyword': '',
        'category_id': '',
        'pageNum': '1',
        'pageSize': '100',
      }),
    );
    return _rows(resp.data ?? <String, dynamic>{});
  }

  Future<void> setLibraryStatus(PlayTemplate template) async {
    await _post('/api/template/updateLibraryStatus', <String, dynamic>{
      'template_id': template.id.toString(),
      'publish_status': template.publishStatus == 1 ? '0' : '1',
    });
  }

  Future<void> remove(PlayTemplate template) async {
    await _post('/api/template/delete', <String, dynamic>{
      'template_id': template.id.toString(),
    });
  }

  /// 模板详情:`POST /api/template/info`(表单 id)。
  ///
  /// ⚠️ 后端有**四种**拒绝理由(不存在 / 已删除 / 审核中 / 已下架),
  ///   它们对用户意味着完全不同的事 —— 抛 [TemplateUnavailableException]
  ///   带上原因,让页面分流,而不是统统渲染成「加载失败 + 重试」。
  Future<PlayTemplate> info(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      final msg = (body['msg'] as String?) ?? '模版打不开';
      throw TemplateUnavailableException(msg, templateUnavailableFrom(msg));
    }
    return PlayTemplate.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 存草稿:`POST /api/template/draft`(JSON body)。
  ///
  /// ★ 门槛低 —— 后端只判标题非空,**不查重名**。
  Future<void> saveDraft(TemplateDraft draft) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/draft',
      data: draft.toJson(),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw TemplatePublishException((body['msg'] as String?) ?? '保存失败');
    }
  }

  /// 发布:`POST /api/template/publish`。
  ///
  /// ⚠️ 与 draft 的关键差别:**会查重名**,重名返回「模板名称 X 已存在」。
  ///   那是唯一一个"改个名字就能过"的失败 —— 界面要明说换名字,
  ///   而不是笼统「发布失败,请重试」(重试一万次名字还是重的)。
  Future<void> publish(TemplateDraft draft) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/publish',
      data: draft.toJson(),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw TemplatePublishException((body['msg'] as String?) ?? '发布失败');
    }
  }

  Future<void> _post(String path, Map<String, dynamic> data) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(data),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }

  List<PlayTemplate> _rows(Map<String, dynamic> body) =>
      _list(body, PlayTemplate.fromJson, fallbackMessage: '加载失败');

  /// 列表类回包的公共判据:`code == 200`;`data` 直接是数组,或 `{rows: []}`
  /// 这一族包法(两个实体的接口都用这一套)。
  List<T> _list<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson, {
    required String fallbackMessage,
  }) {
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? fallbackMessage);
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : (data is Map<String, dynamic>
              ? (data['rows'] as List<dynamic>? ?? const <dynamic>[])
              : const <dynamic>[]);
    return rows.whereType<Map<String, dynamic>>().map(fromJson).toList();
  }
}

/// 模板不可用。带上**原因**,页面据此决定给不给重试。
class TemplateUnavailableException implements Exception {
  TemplateUnavailableException(this.message, this.reason);

  final String message;
  final TemplateUnavailable reason;

  @override
  String toString() => message;
}
