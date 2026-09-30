import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';
import '../../data/models/square_draft.dart';

final squareLocalDraftStoreProvider = Provider<SquareLocalDraftStore>((ref) {
  return SquareLocalDraftStore(ref.watch(secureStorageProvider));
});

/// 一条本机草稿：`postId == null` 是未发布新帖的草稿，否则是已发布/已存服务器帖文的本机修改稿。
class SquareLocalDraftEntry {
  const SquareLocalDraftEntry({required this.postId, required this.draft});

  final int? postId;
  final SquareDraft draft;
}

class SquareLocalDraftStore {
  const SquareLocalDraftStore(this._storage);

  static const String _keyPrefix = 'community_post_local_draft_v4';
  final FlutterSecureStorage _storage;

  String _key(int memberId, int? postId) =>
      '$_keyPrefix:$memberId:${postId == null ? 'new' : 'post:$postId'}';

  Future<bool> save(int memberId, SquareDraft draft) async {
    if (memberId <= 0) return false;
    draft = draft.withStableMediaRequests();
    try {
      await _storage.write(
        key: _key(memberId, draft.id),
        value: jsonEncode(<String, dynamic>{
          'memberId': memberId,
          'workflowId': draft.workflowId,
          'id': draft.id,
          'expectedVersion': draft.expectedVersion,
          'sourceLifecycle': draft.sourceLifecycle,
          'contents': draft.contents,
          'pics': draft.pics,
          'picByteSizes': draft.picByteSizes,
          'picMimeTypes': draft.picMimeTypes,
          'picUploadReceipts': draft.picUploadReceipts,
          'picUploadRequestIds': draft.picUploadRequestIds,
          'existingMediaIds': draft.existingMediaIds,
          'existingPicCount': draft.existingPicCount,
          'address': draft.address,
          'cityCode': draft.cityCode,
          'longitude': draft.longitude,
          'latitude': draft.latitude,
          'dataId': draft.dataId,
          'dataType': draft.dataType,
          'referenceType': draft.referenceType,
          'referenceId': draft.referenceId,
          'communityId': draft.communityId,
          'audience': draft.audience,
          'commentPolicy': draft.commentPolicy,
          'replyApprovalEnabled': draft.replyApprovalEnabled,
          'slowModeSeconds': draft.slowModeSeconds,
          'disclosureType': draft.disclosureType,
          'mentionedMemberIds': draft.mentionedMemberIds,
          'safetyLabels': draft.safetyLabels,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SquareDraft?> read(int memberId, {int? postId}) async {
    if (memberId <= 0) return null;
    try {
      final raw = await _storage.read(key: _key(memberId, postId));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if ((map['memberId'] as num?)?.toInt() != memberId) return null;
      List<T> list<T>(String key) => (map[key] as List<dynamic>? ?? const [])
          .whereType<T>()
          .toList(growable: false);
      return SquareDraft(
        workflowId: '${map['workflowId'] ?? ''}',
        id: (map['id'] as num?)?.toInt(),
        expectedVersion: (map['expectedVersion'] as num?)?.toInt() ?? 0,
        sourceLifecycle: '${map['sourceLifecycle'] ?? 'DRAFT'}',
        contents: '${map['contents'] ?? ''}',
        pics: list<String>('pics'),
        picByteSizes: list<num>(
          'picByteSizes',
        ).map((value) => value.toInt()).toList(growable: false),
        picMimeTypes: list<String>('picMimeTypes'),
        picUploadReceipts: list<String>('picUploadReceipts'),
        picUploadRequestIds: list<String>('picUploadRequestIds'),
        existingMediaIds: list<num>(
          'existingMediaIds',
        ).map((value) => value.toInt()).toList(growable: false),
        existingPicCount: (map['existingPicCount'] as num?)?.toInt() ?? 0,
        address: map['address'] as String?,
        cityCode: map['cityCode'] as String?,
        longitude: map['longitude'] as String?,
        latitude: map['latitude'] as String?,
        dataId: (map['dataId'] as num?)?.toInt(),
        dataType: (map['dataType'] as num?)?.toInt() ?? 0,
        referenceType: map['referenceType'] as String?,
        referenceId: (map['referenceId'] as num?)?.toInt(),
        communityId: (map['communityId'] as num?)?.toInt(),
        audience: '${map['audience'] ?? 'PUBLIC'}',
        commentPolicy: '${map['commentPolicy'] ?? 'EVERYONE'}',
        replyApprovalEnabled: map['replyApprovalEnabled'] == true,
        slowModeSeconds: (map['slowModeSeconds'] as num?)?.toInt() ?? 0,
        disclosureType: '${map['disclosureType'] ?? 'NONE'}',
        mentionedMemberIds: list<num>(
          'mentionedMemberIds',
        ).map((value) => value.toInt()).toList(growable: false),
        safetyLabels: list<String>('safetyLabels'),
      ).withStableMediaRequests();
    } catch (_) {
      return null;
    }
  }

  Future<bool> clear(int memberId, {int? postId}) async {
    if (memberId <= 0) return false;
    try {
      await _storage.delete(key: _key(memberId, postId));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 枚举该账号在本机存下的全部草稿（新帖草稿 + 各帖修改稿）。
  /// 单个槽位解析失败或账号不匹配则跳过；存储整体读取失败会抛出，
  /// 由界面呈现「读取失败 + 重试」，不能静默伪装成“没有草稿”。
  Future<List<SquareLocalDraftEntry>> listFor(int memberId) async {
    if (memberId <= 0) return const <SquareLocalDraftEntry>[];
    final all = await _storage.readAll();
    final prefix = '$_keyPrefix:$memberId:';
    final entries = <SquareLocalDraftEntry>[];
    for (final key in all.keys) {
      if (!key.startsWith(prefix)) continue;
      final suffix = key.substring(prefix.length);
      final int? postId;
      if (suffix == 'new') {
        postId = null;
      } else if (suffix.startsWith('post:')) {
        postId = int.tryParse(suffix.substring(5));
        if (postId == null) continue;
      } else {
        continue;
      }
      final draft = await read(memberId, postId: postId);
      if (draft != null) {
        entries.add(SquareLocalDraftEntry(postId: postId, draft: draft));
      }
    }
    entries.sort((a, b) => (a.postId ?? 0).compareTo(b.postId ?? 0));
    return List<SquareLocalDraftEntry>.unmodifiable(entries);
  }
}
