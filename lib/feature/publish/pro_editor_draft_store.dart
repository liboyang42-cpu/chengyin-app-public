import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';

/// 专业编辑器本地草稿存储 —— 移植自小程序 `utils/publish/pro-editor-draft.js`。
///
/// 一个 storage key 一次写入完整信封:新草稿按 draftUuid 分桶、既有主题按
/// topicId 分桶;memberId 只用于恢复前防串号(不能拿「key 是我算的」代替
/// 对信封归属的校验 —— 真源注释原话)。

const String kProEditorDraftStatusMissing = 'missing';
const String kProEditorDraftStatusMemberMismatch = 'member_mismatch';
const String kProEditorDraftStatusConflict = 'revision_conflict';
const String kProEditorDraftStatusReady = 'ready';

class ProEditorDraftIdentity {
  const ProEditorDraftIdentity({this.topicId, this.draftUuid});

  final String? topicId;
  final String? draftUuid;

  /// 真源 draftKeyFor:topicId 优先;两个都空抛错(调用方以「无身份」处理)。
  String? get storageKey {
    final t = (topicId ?? '').trim();
    if (t.isNotEmpty) return 'pro_editor_draft_topic_${Uri.encodeComponent(t)}';
    final u = (draftUuid ?? '').trim();
    if (u.isNotEmpty) return 'pro_editor_draft_new_${Uri.encodeComponent(u)}';
    return null;
  }
}

class ProEditorDraftEnvelope {
  const ProEditorDraftEnvelope({
    required this.memberId,
    required this.state,
    this.topicId,
    this.draftUuid,
    this.baseRevision = '',
    this.savedAt = 0,
  });

  final String memberId;
  final Map<String, dynamic> state;
  final String? topicId;
  final String? draftUuid;
  final String baseRevision;
  final int savedAt;

  static ProEditorDraftEnvelope? decode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    final state = m['formData'];
    if (state is! Map) return null;
    return ProEditorDraftEnvelope(
      memberId: '${m['memberId'] ?? ''}',
      state: Map<String, dynamic>.from(state),
      topicId: m['topicId'] == null ? null : '${m['topicId']}',
      draftUuid: m['draftUuid'] == null ? null : '${m['draftUuid']}',
      baseRevision: '${m['baseRevision'] ?? ''}',
      savedAt: (m['savedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

final proEditorDraftStoreProvider = Provider<ProEditorDraftStore>((ref) {
  return ProEditorDraftStore(ref.watch(secureStorageProvider));
});

class ProEditorDraftStore {
  const ProEditorDraftStore(this._storage);

  final FlutterSecureStorage _storage;

  /// 真源 createDraftUuid:时间戳 36 进制 + 随机熵。
  static String createDraftUuid() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final entropy = (DateTime.now().microsecondsSinceEpoch % 0x100000000)
        .toRadixString(36);
    return '$ts-$entropy';
  }

  String _activeKey(String memberId) =>
      'pro_editor_active_${Uri.encodeComponent(memberId)}';

  /// 唯一一次写入(信封与 active 指针)。写失败返回 false → 页面按真源弹
  /// 「本地草稿保存失败」。
  Future<bool> save({
    required ProEditorDraftIdentity identity,
    required String memberId,
    required Map<String, dynamic> state,
    String baseRevision = '',
  }) async {
    final key = identity.storageKey;
    if (memberId.isEmpty || key == null) return false;
    final envelope = <String, dynamic>{
      'memberId': memberId,
      'baseRevision': baseRevision,
      'formData': state,
      'chapters': (state['chapters'] as List<dynamic>?) ?? <dynamic>[],
      // App 未移植待编排区(盘点 1435):字段口径保留,恒空。
      'pendingMaterials': const <dynamic>[],
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      if (identity.topicId != null && identity.topicId!.isNotEmpty)
        'topicId': identity.topicId
      else
        'draftUuid': identity.draftUuid,
    };
    try {
      await _storage.write(key: key, value: jsonEncode(envelope));
      final uuid = identity.draftUuid;
      if ((uuid ?? '').isNotEmpty) {
        await _storage.write(key: _activeKey(memberId), value: uuid!);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 真源 loadDraft:missing / member_mismatch / revision_conflict / ready。
  Future<({String status, ProEditorDraftEnvelope? envelope})> load({
    required ProEditorDraftIdentity identity,
    required String memberId,
    String currentBaseRevision = '',
  }) async {
    final key = identity.storageKey;
    if (key == null) {
      return (status: kProEditorDraftStatusMissing, envelope: null);
    }
    Object? raw;
    try {
      raw = await _storage.read(key: key);
    } catch (_) {
      return (status: kProEditorDraftStatusMissing, envelope: null);
    }
    final envelope = ProEditorDraftEnvelope.decode(raw);
    if (envelope == null) {
      return (status: kProEditorDraftStatusMissing, envelope: null);
    }
    if (envelope.memberId.trim() != memberId.trim()) {
      return (status: kProEditorDraftStatusMemberMismatch, envelope: null);
    }
    final stored = envelope.baseRevision.trim();
    final current = currentBaseRevision.trim();
    if (stored.isNotEmpty && current.isNotEmpty && stored != current) {
      return (status: kProEditorDraftStatusConflict, envelope: envelope);
    }
    return (status: kProEditorDraftStatusReady, envelope: envelope);
  }

  Future<bool> remove({
    required ProEditorDraftIdentity identity,
    required String memberId,
  }) async {
    final key = identity.storageKey;
    if (key == null) return false;
    try {
      await _storage.delete(key: key);
      final uuid = identity.draftUuid;
      if ((uuid ?? '').isNotEmpty) {
        final active = await _storage.read(key: _activeKey(memberId));
        if (active == uuid) {
          await _storage.delete(key: _activeKey(memberId));
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 真源 readActiveNewDraft:该账号最近一次编辑的新草稿桶。
  Future<String> activeNewDraftUuid(String memberId) async {
    if (memberId.isEmpty) return '';
    try {
      return (await _storage.read(key: _activeKey(memberId)) ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}
