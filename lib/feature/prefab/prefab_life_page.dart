import 'dart:async';
import 'dart:math' show min, max, pi;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/map/device_location.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_progress.dart';
import '../../data/api/play_api.dart';
import '../../data/models/checkin_models.dart';
import 'prefab_story_engine.dart';

export 'prefab_story_engine.dart' show isPrefabLifeTopic;

/// 取一张现场照片并换回可回放的地址(真源 `app.chooseImage(…, {bizType:'play_photo'})`
/// 的语义:选图即上传)。测试注入假实现。
typedef PrefabPhotoPicker = Future<String?> Function();

final prefabPhotoPickerProvider = Provider<PrefabPhotoPicker>((ref) {
  return () async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
    );
    if (file == null) return null;
    return ref.read(playApiProvider).uploadImage(file.path);
  };
});

/// 现场定位(gcj02)。测试注入。
typedef PrefabLocationReader = Future<MapCoordinate> Function();

final prefabLocationProvider = Provider<PrefabLocationReader>(
  (ref) =>
      () => DeviceLocation().current(),
);

/// 存档读写(真源 `wx.setStorageSync('prefab_life_v1_…')`)。测试注入内存表。
typedef PrefabSaveReader = Future<String?> Function(String key);
typedef PrefabSaveWriter = Future<void> Function(String key, String value);
typedef PrefabSaveClearer = Future<void> Function(String key);

class PrefabSaveStore {
  const PrefabSaveStore({
    required this.read,
    required this.write,
    required this.clear,
  });

  final PrefabSaveReader read;
  final PrefabSaveWriter write;
  final PrefabSaveClearer clear;
}

final prefabSaveStoreProvider = Provider<PrefabSaveStore>((ref) {
  // 仓内 `wx.setStorageSync` 等价物就是 FlutterSecureStorage(见 roam_session_store)。
  const FlutterSecureStorage storage = FlutterSecureStorage();
  return PrefabSaveStore(
    read: (key) => storage.read(key: key),
    write: (key, value) => storage.write(key: key, value: value),
    clear: (key) => storage.delete(key: key),
  );
});

/// 骰子源(测试注入固定点)。
typedef PrefabDiceRoller = List<int> Function();

final prefabDiceProvider = Provider<PrefabDiceRoller>((_) => prefabRollTwo);

/// 《预制人生》—— 小程序 `subpackagePrefab/index` 的 1:1 移植。
///
/// 结构(13 场景故事引擎、地图、贴纸、结局、存档、签到链)跟真源;外观走
/// iOS 原生(Cupertino)。声音是真源 `wx.createWebAudioContext` 的音鸣,
/// App 侧只有触感 + 轻点击声,差异记入 accepted。
class PrefabLifePage extends ConsumerStatefulWidget {
  const PrefabLifePage({
    super.key,
    this.activityId,
    this.topicId,
    this.mock = false,
  });

  final int? activityId;
  final int? topicId;

  /// 真源 `mock=1`:预览票,不发任何现场请求。
  final bool mock;

  @override
  ConsumerState<PrefabLifePage> createState() => _PrefabLifePageState();
}

class _PrefabLifePageState extends ConsumerState<PrefabLifePage> {
  // ── 会话/存档 ────────────────────────────────────────────────
  late String _storageKey;
  PrefabState _state = const PrefabState();
  List<PlayNode> _nodes = const <PlayNode>[];
  String _stationName = '上海城市规划展示馆';
  String _stationAddress = '人民大道 100 号';

  bool _loading = true;
  String _error = '';
  String _view = 'story';
  bool _soundOn = true;

  // ── 场景内瞬时 UI(真源 setData 的页面态)──────────────────
  bool _routeChoice = false;
  bool _signChoice = false;
  Timer? _walkTimer;

  final List<String> _bootChars = <String>[];
  String _bootGhost = kPrefabBootTarget;
  String _bootNext = 'h';
  double _bootTimerWidth = 100;
  String _bootMessage = '';
  bool _bootError = false;
  bool _bootDone = false;
  String _bootText = '';
  int _bootStartedAt = 0;
  Timer? _bootTimer;
  Timer? _bootResetTimer;

  int _dreamIndex = 0;
  bool _dreamReady = false;
  int _wakeProgress = 0;
  String? _dreamSceneStarted;
  Timer? _dreamTimer;
  Timer? _dreamExitTimer;
  Timer? _wakeTimer;

  bool _holding = false;
  int _holdProgress = 0;
  Timer? _holdTimer;

  int _quizIndex = 0;
  int _quizScore = 0;
  String _countText = '';
  int _teacherSeconds = 8;
  Timer? _teacherTimer;

  String _noteText = '';
  bool _stickerMode = false;
  List<PrefabMapNote> _mapNotes = kPrefabMapNotes;
  PrefabMapNote? _mapBubble;

  PrefabCheckResult? _check;
  String _checkLabel = '';
  void Function(bool ok)? _checkDone;

  bool _showEndings = false;
  bool _syncing = false;
  String _syncError = '';

  @override
  void initState() {
    super.initState();
    _storageKey = prefabStorageKey(
      activityId: widget.activityId,
      topicId: widget.topicId,
    );
    unawaited(_boot());
  }

  @override
  void dispose() {
    _walkTimer?.cancel();
    _bootTimer?.cancel();
    _bootResetTimer?.cancel();
    _dreamTimer?.cancel();
    _dreamExitTimer?.cancel();
    _wakeTimer?.cancel();
    _holdTimer?.cancel();
    _teacherTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final raw = await ref.read(prefabSaveStoreProvider).read(_storageKey);
    _state = raw == null ? const PrefabState() : PrefabState.restore(raw);
    _noteText = _state.note;
    if (widget.mock) {
      // 真源 onLoad:预览票只塞这一颗节点,不发任何请求。
      _nodes = const <PlayNode>[
        PlayNode(
          nodeId: 0,
          name: '上海城市规划展示馆',
          address: '人民大道 100 号',
          sortId: 1,
          done: false,
        ),
      ];
      if (mounted) {
        setState(() {
          _stationName = '上海城市规划展示馆';
          _stationAddress = '人民大道 100 号';
          _loading = false;
        });
      }
      return;
    }
    await _loadRoute();
    if (mounted) setState(() => _loading = false);
  }

  /// 真源 `_loadRoute`:缺参数不是故障,是「场次信息缺失」。
  Future<void> _loadRoute() async {
    final int? activityId = widget.activityId;
    final int? topicId = widget.topicId;
    if (activityId == null && topicId == null) {
      setState(() {
        _loading = false;
        _error = '场次信息缺失，请从票夹重新进入';
      });
      return;
    }
    try {
      final PlayNodesResult result = activityId != null
          ? await ref.read(playApiProvider).fetchNodes(activityId)
          : await ref.read(playApiProvider).fetchTopicNodes(topicId!);
      final PlayNode? first = result.nodes.isEmpty ? null : result.nodes.first;
      setState(() {
        _nodes = result.nodes;
        _error = '';
        _stationName = (first?.name ?? '').isEmpty ? '上海城市规划展示馆' : first!.name;
        _stationAddress = (first?.address ?? '').isEmpty
            ? '人民大道 100 号'
            : first!.address;
      });
    } on PlayException catch (e) {
      setState(() {
        _error = e.message.isEmpty ? '路线没加载出来，请稍后重试' : e.message;
      });
    } catch (_) {
      setState(() => _error = '路线没加载出来，请稍后重试');
    }
  }

  void _commit() {
    setState(() {});
    unawaited(
      ref.read(prefabSaveStoreProvider).write(_storageKey, _state.save()),
    );
  }

  void _toast(String message) => CyNativeNotice.show(context, message);

  void _feel({bool heavy = false}) {
    if (heavy) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    if (_soundOn) unawaited(SystemSound.play(SystemSoundType.click));
  }

  // ══════════════════════════ 场景流转 ══════════════════════════

  void _advance() {
    _state = _state.advance();
    _dreamIndex = 0;
    _enterSceneSideEffects();
    _feel();
    _commit();
  }

  /// 真源 `_sync()` 里挂在场景上的计时器副作用。
  void _enterSceneSideEffects() {
    final String scene = _state.scene;
    if (scene != 'boot' && (_bootTimer != null || _bootResetTimer != null)) {
      _clearBoot();
    }
    if (scene == 'boot' && _bootText.isEmpty && !_bootDone) _prepareBoot();
    if (scene != 'dream1' && scene != 'dream2' && scene != 'dream3') {
      if (_dreamSceneStarted != null) {
        _dreamSceneStarted = null;
        _dreamTimer?.cancel();
        _dreamTimer = null;
        _dreamExitTimer?.cancel();
        _dreamExitTimer = null;
      }
    }
    if (scene == 'learning' && _state.step == 2 && _teacherTimer == null) {
      _startTeacherTimer();
    }
    if (!(scene == 'learning' && _state.step == 2)) _stopTeacherTimer();
  }

  // ══════════════════════════ register ══════════════════════════

  void _profileInput(String key, String value) {
    _state = _state.copyWith(profile: _profilePatch(key, value));
    _commit();
  }

  PrefabProfile _profilePatch(String key, String value) {
    final PrefabProfile p = _state.profile;
    return switch (key) {
      'name' => p.copyWith(name: value),
      'place' => p.copyWith(place: value),
      'gender' => p.copyWith(gender: value),
      'dream' => p.copyWith(dream: value),
      _ => p.copyWith(avatar: value),
    };
  }

  void _registerTextNext(String key) {
    final String value = _fieldOf(key).trim();
    if (value.isEmpty) {
      _toast(switch (key) {
        'name' => '先写下你的名字',
        'place' => '写下出生地',
        _ => '写下长大想做什么',
      });
      return;
    }
    _state = _state
        .copyWith(profile: _profilePatch(key, value))
        .withStep(_state.step + 1);
    _feel();
    _commit();
  }

  String _fieldOf(String key) => switch (key) {
    'name' => _state.profile.name,
    'place' => _state.profile.place,
    'gender' => _state.profile.gender,
    'dream' => _state.profile.dream,
    _ => _state.profile.avatar,
  };

  void _registerChip(String key, String value) {
    _state = _state
        .copyWith(profile: _profilePatch(key, value))
        .withStep(_state.step + 1);
    _feel();
    _commit();
  }

  Future<void> _chooseAvatar() async {
    final String? path = await ref.read(prefabPhotoPickerProvider)();
    if (path == null || !mounted) return;
    _feel();
    _state = _state.copyWith(profile: _state.profile.copyWith(avatar: path));
    _finishRegistration();
    _commit();
  }

  void _skipAvatar() {
    _finishRegistration();
    _commit();
  }

  void _finishRegistration() {
    if (_state.step != 4) return;
    _state = _state.applyProfile(_state.profile).withStep(5);
    _feel(heavy: true);
  }

  void _submitProfile() {
    if (_state.step != 5) return;
    _advance();
  }

  // ══════════════════════════ boot ══════════════════════════

  void _prepareBoot() {
    _clearBoot();
    _bootText = '';
    setState(() {
      _bootChars.clear();
      _bootGhost = kPrefabBootTarget;
      _bootNext = 'h';
      _bootTimerWidth = 100;
      _bootMessage = '';
      _bootError = false;
      _bootDone = false;
    });
  }

  void _clearBoot() {
    _bootTimer?.cancel();
    _bootResetTimer?.cancel();
    _bootTimer = null;
    _bootResetTimer = null;
    _bootStartedAt = 0;
  }

  void _bootRetry(String message) {
    _bootTimer?.cancel();
    _bootTimer = null;
    setState(() {
      _bootMessage = '$message · 重新输入';
      _bootError = true;
    });
    _feel(heavy: true);
    _bootResetTimer = Timer(const Duration(milliseconds: 280), () {
      _bootResetTimer = null;
      _bootStartedAt = 0;
      _bootText = '';
      if (!mounted) return;
      setState(() {
        _bootChars.clear();
        _bootGhost = kPrefabBootTarget;
        _bootNext = 'h';
        _bootTimerWidth = 100;
        _bootMessage = '';
        _bootError = false;
      });
    });
  }

  void _bootKey(String key) {
    if (_bootDone || _bootResetTimer != null) return;
    String typed = _bootText;
    if (key == 'back') {
      typed = typed.substring(0, max(0, typed.length - 1));
      _bootText = typed;
      _setBootEcho(typed);
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (_bootStartedAt == 0) {
      _bootStartedAt = now;
      _bootTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final double left = max(
          0,
          10 - (DateTime.now().millisecondsSinceEpoch - _bootStartedAt) / 1000,
        );
        if (!mounted) return;
        setState(() => _bootTimerWidth = left * 10);
        if (left <= 0) _bootRetry('超时');
      });
    }
    typed += key;
    _feel();
    _bootText = typed;
    _setBootEcho(typed);
    if (typed.length > kPrefabBootTarget.length ||
        typed[typed.length - 1] != kPrefabBootTarget[typed.length - 1]) {
      _bootRetry('打错了');
      return;
    }
    if (typed != kPrefabBootTarget) return;
    final bool fast =
        DateTime.now().millisecondsSinceEpoch - _bootStartedAt < 6000;
    _bootTimer?.cancel();
    _bootTimer = null;
    if (fast) {
      final Map<String, int> skills = <String, int>{..._state.skills};
      skills['precision'] = (skills['precision'] ?? 0) + 1;
      _state = _state.copyWith(skills: skills);
    }
    setState(() {
      _bootDone = true;
      _bootTimerWidth = 0;
      _bootMessage = fast ? '输入完成 · 很快' : '输入完成';
    });
    _feel();
    _bootResetTimer = Timer(const Duration(milliseconds: 900), () {
      _bootResetTimer = null;
      if (mounted) _advance();
    });
  }

  void _setBootEcho(String typed) {
    setState(() {
      _bootChars
        ..clear()
        ..addAll(typed.split(''));
      _bootGhost = kPrefabBootTarget.length > typed.length
          ? kPrefabBootTarget.substring(typed.length)
          : '';
      _bootNext = typed.length < kPrefabBootTarget.length
          ? kPrefabBootTarget[typed.length]
          : '';
    });
  }

  // ══════════════════════════ walk ══════════════════════════

  void _startWalk() {
    if (_walkTimer != null ||
        _routeChoice ||
        _signChoice ||
        _state.walkProgress >= 100) {
      return;
    }
    _walkTimer = Timer.periodic(const Duration(milliseconds: 80), (Timer t) {
      final int next = min(100, _state.walkProgress + 2);
      _state = _state.copyWith(walkProgress: next);
      if (next == 50 && _state.picks['route'] == null) {
        t.cancel();
        _walkTimer = null;
        _feel(heavy: true);
        _commit();
        setState(() => _routeChoice = true);
        return;
      }
      if (next == 74 && _state.picks['signAsked'] != true) {
        t.cancel();
        _walkTimer = null;
        _state = _state.choose('signAsked', true);
        _commit();
        setState(() => _signChoice = true);
        return;
      }
      if (next == 100) {
        t.cancel();
        _walkTimer = null;
        _commit();
        _advance();
        return;
      }
      setState(() {});
    });
  }

  void _routePick(int value) {
    _state = _state.choose('route', value);
    if (value == 1) _state = _state.gain(const PrefabGain(luck: 1));
    setState(() => _routeChoice = false);
    _commit();
    _startWalk();
  }

  Future<void> _signPick(int value) async {
    setState(() => _signChoice = false);
    if (value != 1) {
      _state = _state.choose('sign', 'skip');
      _commit();
      _startWalk();
      return;
    }
    final String? path = await _pickPhoto('sign');
    if (path == null || !mounted) return;
    _state = _state
        .withPhoto('sign', path)
        .choose('sign', 'photo')
        .gain(const PrefabGain(luck: 1));
    _commit();
    _startWalk();
  }

  String _mockAssetFor(String key) => prefabAsset(switch (key) {
    'hall' => 'square',
    'sign' => 'street',
    'avatar' => 'corridor',
    _ => key,
  });

  Future<String?> _pickPhoto(String key) async {
    if (widget.mock) return _mockAssetFor(key);
    final String? path = await ref.read(prefabPhotoPickerProvider)();
    if (path == null) return null;
    _feel();
    return path;
  }

  // ══════════════════════════ hall / arrive ══════════════════════════

  Future<bool> _arrive() async {
    if (widget.mock) return true;
    final PlayNode? node = _nodes.isEmpty ? null : _nodes.first;
    if (node == null) {
      _toast('没有找到第 1 站');
      return false;
    }
    final MapCoordinate coordinate;
    try {
      coordinate = await ref.read(prefabLocationProvider)();
    } catch (_) {
      _toast('需要定位才能在现场签到');
      return false;
    }
    try {
      if (widget.activityId != null) {
        await ref
            .read(playApiProvider)
            .submitArrive(
              activityId: widget.activityId!,
              nodeId: node.nodeId,
              longitude: coordinate.longitude,
              latitude: coordinate.latitude,
            );
      } else {
        await ref
            .read(playApiProvider)
            .submitTopicArrive(
              topicId: widget.topicId!,
              nodeId: node.nodeId,
              longitude: coordinate.longitude,
              latitude: coordinate.latitude,
            );
      }
      return true;
    } on PlayException catch (e) {
      _toast(e.message.isEmpty ? '还没到展示馆附近' : e.message);
      return false;
    } catch (_) {
      _toast('还没到展示馆附近');
      return false;
    }
  }

  Future<void> _hallPhoto() async {
    if (!await _arrive() || !mounted) return;
    final String? path = await _pickPhoto('hall');
    if (path == null || !mounted) return;
    _state = _state.withPhoto('hall', path);
    _commit();
    _advance();
  }

  // ══════════════════════════ birth ══════════════════════════

  void _firstPick(int value) {
    _state = _state.choose('first', value);
    if (value == 1) {
      _state = _state.gain(const PrefabGain(thought: 'afternoon'));
    }
    _state = _state.withStep(1);
    _commit();
  }

  void _standStart() {
    if (_holdTimer != null) return;
    final int started = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _holding = true;
      _holdProgress = 0;
    });
    _holdTimer = Timer.periodic(const Duration(milliseconds: 80), (Timer t) {
      final int progress = min(
        100,
        ((DateTime.now().millisecondsSinceEpoch - started) / 30).round(),
      );
      if (progress >= 100) {
        t.cancel();
        _holdTimer = null;
        _state = _state.withStep(2);
        _feel(heavy: true);
        setState(() {
          _holding = false;
          _holdProgress = 100;
        });
        _commit();
        return;
      }
      setState(() => _holdProgress = progress);
    });
  }

  void _standEnd() {
    if (_holdTimer == null) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    setState(() {
      _holding = false;
      _holdProgress = 0;
    });
  }

  Future<void> _windowPhoto() async {
    final String? path = await _pickPhoto('window');
    if (path == null || !mounted) return;
    _state = _state.withPhoto('window', path).withStep(3);
    _commit();
  }

  void _pickNote(String value) => setState(() => _noteText = value);

  void _submitNote() {
    final String value = _noteText.trim();
    if (value.isEmpty) {
      _toast('写下窗外有什么');
      return;
    }
    _state = _state.copyWith(note: value).observe('展示馆的窗', value);
    _commit();
    _advance();
  }

  // ══════════════════════════ dream ══════════════════════════

  void _startDreamIfNeeded() {
    final String scene = _state.scene;
    if (!scene.startsWith('dream') || _dreamSceneStarted == scene) return;
    _dreamSceneStarted = scene;
    final int length = prefabDreamCards(scene, _state).length;
    _dreamTimer?.cancel();
    _dreamExitTimer?.cancel();
    setState(() {
      _dreamIndex = 0;
      _dreamReady = length <= 1;
      _wakeProgress = 0;
    });
    if (length <= 1) return;
    _dreamTimer = Timer.periodic(const Duration(milliseconds: 1800), (Timer t) {
      final int next = _dreamIndex + 1;
      if (next >= length - 1) {
        t.cancel();
        _dreamTimer = null;
        _feel();
        setState(() {
          _dreamIndex = length - 1;
          _dreamReady = true;
        });
        _dreamExitTimer = Timer(
          const Duration(milliseconds: 2200),
          _finishDream,
        );
        return;
      }
      _feel();
      setState(() => _dreamIndex = next);
    });
  }

  void _wakeStart() {
    if (!_state.scene.startsWith('dream') || _wakeTimer != null) return;
    final int started = DateTime.now().millisecondsSinceEpoch;
    _wakeTimer = Timer.periodic(const Duration(milliseconds: 50), (Timer t) {
      final int progress = min(
        100,
        ((DateTime.now().millisecondsSinceEpoch - started) / 15).round(),
      );
      setState(() => _wakeProgress = progress);
      if (progress >= 100) {
        t.cancel();
        _wakeTimer = null;
        _finishDream();
      }
    });
  }

  void _wakeEnd() {
    if (_wakeTimer == null) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    setState(() => _wakeProgress = 0);
  }

  void _finishDream() {
    if (!_state.scene.startsWith('dream')) return;
    _dreamTimer?.cancel();
    _dreamTimer = null;
    _dreamExitTimer?.cancel();
    _dreamExitTimer = null;
    _state = _state.gain(const PrefabGain(dreams: 1));
    _advance();
  }

  // ══════════════════════════ learning ══════════════════════════

  void _quizPick(int value, int answer) {
    final bool correct = value == answer;
    final int index = _quizIndex + 1;
    _quizScore += correct ? 1 : 0;
    if (index < 3) {
      setState(() => _quizIndex = index);
      return;
    }
    _state = _state.choose('quiz', _quizScore);
    if (_quizScore >= 2) _state = _state.gain(const PrefabGain(luck: 1));
    _state = _state.withStep(1);
    _commit();
  }

  void _submitCount() {
    final int? count = int.tryParse(_countText.trim());
    if (count == null || count < 0) {
      _toast('写下你看到的人数');
      return;
    }
    _state = _state
        .choose('count', count)
        .observe('展示馆', '模型前，有 $count 个人在低头看手机。')
        .withStep(2);
    _commit();
    _enterSceneSideEffects();
  }

  void _startTeacherTimer() {
    int seconds = 8;
    setState(() => _teacherSeconds = seconds);
    _teacherTimer?.cancel();
    _teacherTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      seconds -= 1;
      setState(() => _teacherSeconds = max(0, seconds));
      if (seconds > 0) return;
      _stopTeacherTimer();
      _teacherPick(3);
    });
  }

  void _stopTeacherTimer() {
    _teacherTimer?.cancel();
    _teacherTimer = null;
  }

  void _teacherPick(int value) {
    _stopTeacherTimer();
    _state = _state.choose('teacher', value);
    switch (value) {
      case 1:
        _state = _state.withStep(3);
        _commit();
      case 0:
        _runCheck('rule', 9, '背出标准答案', (bool ok) {
          _state = ok
              ? _state.gain(const PrefabGain(thought: 'standard'))
              : _state.gain(const PrefabGain(hp: -1));
          _advance();
        });
      case 2:
        _runCheck('heart', 10, '问老师：有没有标准答案', (bool ok) {
          if (ok) _state = _state.gain(const PrefabGain(thought: 'noanswer'));
          _advance();
        });
      default:
        _advance();
    }
  }

  void _teacherWindowPick(int value) {
    _state = _state.choose('window', value);
    if (value == 0) {
      _advance();
      return;
    }
    _runCheck('precision', 10, '说出它哪里精密', (bool ok) {
      _state = ok
          ? _state.gain(const PrefabGain(thought: 'precise'))
          : _state.gain(const PrefabGain(hp: -1));
      _advance();
    });
  }

  void _runCheck(String skill, int dc, String label, void Function(bool) done) {
    final List<int> rolls = ref.read(prefabDiceProvider)();
    final PrefabCheckResult result = _state.check(skill, dc, rolls);
    _checkDone = done;
    _feel(heavy: !result.ok);
    setState(() {
      _checkLabel = label;
      _check = result;
    });
  }

  void _closeCheck() {
    final void Function(bool ok)? done = _checkDone;
    final bool ok = _check?.ok ?? false;
    _checkDone = null;
    setState(() => _check = null);
    done?.call(ok);
  }

  // ══════════════════════════ career / work ══════════════════════════

  void _placeSticker(String label) {
    _state = _state
        .copyWith(sticker: PrefabSticker(label: label, x: 150, y: 388))
        .withStep(1);
    _feel();
    setState(() {
      _view = 'story';
      _stickerMode = false;
    });
    _commit();
  }

  void _careerPick(String name) {
    _state = _state.copyWith(job: name);
    _commit();
    _advance();
  }

  void _bossPick(int value) {
    _state = _state.choose('boss', value);
    void finish(bool ok) {
      if (!ok) _state = _state.gain(const PrefabGain(hp: -1));
      _state = _state.withStep(1);
      _commit();
    }

    switch (value) {
      case 1:
        _runCheck('rule', 10, '用系统的语言说话', finish);
      case 2:
        _runCheck('heart', 11, '我想试试这个', finish);
      case 3:
        _state = _state.gain(const PrefabGain(thought: 'afternoon'));
        finish(true);
      default:
        finish(true);
    }
  }

  Future<void> _phonePhoto() async {
    final String? path = await _pickPhoto('phone');
    if (path == null || !mounted) return;
    _state = _state.withPhoto('phone', path);
    _commit();
    _advance();
  }

  // ══════════════════════════ flow / 同步 ══════════════════════════

  /// 真源 `_syncCompletion`:先把现场照片 POST 给服务器,再**重读节点**回验;
  /// 没读回来就不算同步成功(回执 ≠ 观测)。
  Future<void> _syncCompletion() async {
    if (_state.synced || widget.mock) {
      setState(() => _showEndings = true);
      return;
    }
    final PlayNode? node = _nodes.isEmpty ? null : _nodes.first;
    final String picUrl = _state.photos['hall'] ?? '';
    if (node == null || picUrl.isEmpty) {
      setState(() => _showEndings = true);
      return;
    }
    setState(() {
      _syncing = true;
      _syncError = '';
    });
    try {
      if (widget.activityId != null) {
        await ref
            .read(playApiProvider)
            .submitPhoto(
              activityId: widget.activityId!,
              nodeId: node.nodeId,
              picUrl: picUrl,
            );
      } else {
        await ref
            .read(playApiProvider)
            .submitTopicPhoto(
              topicId: widget.topicId!,
              nodeId: node.nodeId,
              picUrl: picUrl,
            );
      }
      final PlayNodesResult fresh = widget.activityId != null
          ? await ref.read(playApiProvider).fetchNodes(widget.activityId!)
          : await ref.read(playApiProvider).fetchTopicNodes(widget.topicId!);
      final PlayNode? readback = fresh.nodes
          .where((PlayNode n) => '${n.nodeId}' == '${node.nodeId}')
          .firstOrNull;
      if (readback != null &&
          (readback.done || (readback.imgUrl ?? '').isNotEmpty)) {
        _state = _state.copyWith(synced: true);
        _commit();
        setState(() {
          _syncing = false;
          _showEndings = true;
        });
        return;
      }
      setState(() {
        _syncing = false;
        _syncError = '服务器已接收，但还没读回这张现场照片，请再核对一次';
      });
    } on PlayException catch (e) {
      setState(() {
        _syncing = false;
        _syncError = e.message.isEmpty ? '本地故事已保存，现场记录暂未同步' : e.message;
      });
    } catch (_) {
      setState(() {
        _syncing = false;
        _syncError = '本地故事已保存，现场记录暂未同步';
      });
    }
  }

  void _primaryAction() {
    switch (_state.scene) {
      case 'prologue':
        _advance();
      case 'walk':
        _startWalk();
      case 'flow':
        unawaited(_syncCompletion());
    }
  }

  Future<void> _reset() async {
    _walkTimer?.cancel();
    _holdTimer?.cancel();
    _dreamTimer?.cancel();
    _wakeTimer?.cancel();
    _dreamExitTimer?.cancel();
    _bootTimer?.cancel();
    _bootResetTimer?.cancel();
    _teacherTimer?.cancel();
    _walkTimer = _holdTimer = _dreamTimer = _wakeTimer = _dreamExitTimer =
        _bootTimer = _bootResetTimer = _teacherTimer = null;
    _dreamSceneStarted = null;
    _bootText = '';
    _quizScore = 0;
    _quizIndex = 0;
    _mapNotes = kPrefabMapNotes;
    await ref.read(prefabSaveStoreProvider).clear(_storageKey);
    _state = const PrefabState();
    setState(() {
      _view = 'story';
      _teacherSeconds = 8;
      _dreamReady = false;
      _wakeProgress = 0;
      _showEndings = false;
      _noteText = '';
      _countText = '';
    });
    _commit();
  }

  // ══════════════════════════ build ══════════════════════════

  int get _walkLeft => (420 * (1 - _state.walkProgress / 100)).round();

  String get _displayName =>
      _state.profile.name.isEmpty ? '我' : _state.profile.name;

  @override
  Widget build(BuildContext context) {
    final bool isDream = _state.scene.startsWith('dream');
    final bool bareChrome = isDream || _state.scene == 'boot';
    return CupertinoPageScaffold(
      // 真源 index.json backgroundColor #000,整页恒暗(玩家角色)。
      backgroundColor: AppColors.bgDeep,
      navigationBar: bareChrome
          ? null
          : CupertinoNavigationBar(
              backgroundColor: AppColors.bgDeep,
              border: null,
              middle: const Text('预制人生'),
              trailing: Semantics(
                label: _soundOn ? '关闭声音' : '打开声音',
                button: true,
                child: CupertinoButton(
                  key: const Key('prefab-sound'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _soundOn = !_soundOn),
                  child: Icon(
                    _soundOn
                        ? CupertinoIcons.speaker_1
                        : CupertinoIcons.speaker_3,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
      child: SafeArea(
        bottom: false,
        child: _loading
            ? const _PrefabLoading()
            : _error.isNotEmpty
            ? _PrefabError(message: _error, onRetry: _retry)
            : _view == 'map'
            ? _mapView()
            : Stack(
                children: <Widget>[
                  _storyView(),
                  if (_routeChoice)
                    _promptSheet(
                      kicker: '地图 · 现在',
                      title: '你已偏离推荐路线，是否重新规划？',
                      left: '重新规划',
                      onLeft: () => _routePick(0),
                      right: '继续这条路',
                      onRight: () => _routePick(1),
                    ),
                  if (_signChoice)
                    _promptSheet(
                      kicker: '路上 · 可选',
                      title: '路边有一块带“新”字的招牌吗？',
                      left: '没看到，继续走',
                      onLeft: () => _signPick(0),
                      right: '拍下来打卡',
                      onRight: () => _signPick(1),
                    ),
                  if (_check case final PrefabCheckResult check)
                    _checkSheet(check),
                  if (_showEndings) _endingsSheet(),
                ],
              ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = '';
    });
    unawaited(
      _loadRoute().then((_) {
        if (mounted) setState(() => _loading = false);
      }),
    );
  }

  Widget _storyView() {
    final String scene = _state.scene;
    final PrefabSceneMeta meta = kPrefabSceneMeta[scene]!;
    if (scene == 'boot') return _bootScreen();
    _startDreamIfNeeded();
    final bool showHud = scene != 'prologue' && scene != 'register';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: <Widget>[
              Semantics(
                label: '小地图，点开看全屏地图',
                button: true,
                child: GestureDetector(
                  key: const Key('prefab-radar'),
                  onTap: () => setState(() => _view = 'map'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Center(
                      child: Text(
                        '${_walkLeft}m',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        text: '预制人生',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        children: _state.profile.name.isEmpty
                            ? null
                            : <InlineSpan>[
                                TextSpan(
                                  text: ' · ${_state.profile.name}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                      ),
                    ),
                    const Text(
                      '第 1 站 · 上海城市规划展示馆',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (showHud)
                const Text(
                  'N',
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
            ],
          ),
        ),
        if (showHud)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '⚡ 精力 ${_state.hp}    ✦ 幸运 ${_state.luck}    '
              '梦 ${_state.dreams}/8    念头 ${_state.thoughts.length}',
              key: const Key('prefab-hud'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '宇宙 · ${meta.cosmos}',
            style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              Text(
                meta.kicker,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta.title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ..._sceneBody(scene),
              if (_ctaLabel(scene) != null) const SizedBox(height: 24),
              if (_ctaLabel(scene) != null)
                CupertinoButton(
                  key: const Key('prefab-cta'),
                  color: AppColors.primary,
                  onPressed: _syncing ? null : _primaryAction,
                  child: Text(
                    _ctaLabel(scene)!,
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
              if (scene == 'walk')
                CupertinoButton(
                  onPressed: () => setState(() => _view = 'map'),
                  child: const Text(
                    '看地图',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String? _ctaLabel(String scene) => switch (scene) {
    'prologue' => '开始（建议戴耳机）',
    'walk' => _state.walkProgress > 0 ? '正在前往第 1 站' : '开始步行',
    'flow' => _syncing ? '正在保存这一站' : '全剧结局',
    _ => null,
  };

  List<Widget> _sceneBody(String scene) => switch (scene) {
    'prologue' => _prologueBody(),
    'register' => _registerBody(),
    'boot' => const <Widget>[],
    'walk' => _walkBody(),
    'hall' => _hallBody(),
    'birth' => _birthBody(),
    'dream1' || 'dream2' || 'dream3' => _dreamBody(),
    'learning' => _learningBody(),
    'career' => _careerBody(),
    'work' => _workBody(),
    'flow' => _flowBody(),
    _ => const <Widget>[],
  };

  // ── 通用小件(对齐 wxml 的段落/NPC/选项样式) ──────────────

  Widget _paragraph(String text, {String? keyName}) => Padding(
    key: keyName == null ? null : Key(keyName),
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        height: 1.7,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _voice(String name, String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.accentViolet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _npc(String name, String meta, String line) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            children: <InlineSpan>[
              TextSpan(
                text: '  $meta',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          line,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _choice({
    required String text,
    String? percent,
    bool red = false,
    required VoidCallback onTap,
    String? keyName,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: CupertinoButton(
      key: keyName == null ? null : Key(keyName),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      alignment: Alignment.centerLeft,
      color: AppColors.bgSurface,
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: red ? AppColors.danger : AppColors.textPrimary,
              ),
            ),
          ),
          if (percent != null)
            Text(
              percent,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _fieldText({
    required String keyName,
    required String value,
    required String placeholder,
    required int maxLength,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: CupertinoTextField(
      key: Key(keyName),
      textCapitalization: TextCapitalization.none,
      maxLength: maxLength,
      controller: TextEditingController.fromValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
      ),
      placeholder: placeholder,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary),
      placeholderStyle: const TextStyle(color: AppColors.textDisabled),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(12),
    ),
  );

  Widget _chips(
    List<String> values,
    ValueChanged<String> onPick, {
    String? keyPrefix,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final String value in values)
        CupertinoButton(
          key: keyPrefix == null ? null : Key('$keyPrefix-$value'),
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.bgElevated,
          onPressed: () => onPick(value),
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
    ],
  );

  Widget _image(String src, {double height = 200, String? keyName}) => Padding(
    key: keyName == null ? null : Key(keyName),
    padding: const EdgeInsets.only(bottom: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      child: Image.asset(
        src,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        // 用户拍的照片是网络地址,回退到包内资源。
        errorBuilder: (_, _, _) =>
            Container(height: height, color: AppColors.bgSurface),
      ),
    ),
  );

  Widget _imageAny(String src, {double height = 200}) {
    if (src.startsWith('http') ||
        src.startsWith('file:') ||
        src.startsWith('/data')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          child: Image.network(
            src,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Container(height: height, color: AppColors.bgSurface),
          ),
        ),
      );
    }
    return _image(src, height: height);
  }

  // ── 各场景 ─────────────────────────────────────────────────

  List<Widget> _prologueBody() => <Widget>[
    _paragraph('是你选择的命运？\n还是命运选择了你？'),
    const SizedBox(height: 8),
    _paragraph('我第一次有意识的时候，没有光，也没有声音。只有一种非常确定的感觉——一切都已经准备好了。'),
    _paragraph('温度刚好，湿度刚好，连空气里的味道都没有多余的部分。'),
  ];

  List<Widget> _registerBody() {
    final PrefabProfile profile = _state.profile;
    final int step = _state.step;
    return <Widget>[
      _npc('护士', '在很亮的地方', '“新生儿登记。我问，你答。”'),
      const Text(
        '新 生 儿 登 记',
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 2,
          color: AppColors.textDisabled,
        ),
      ),
      const SizedBox(height: 8),
      for (final (String label, String value) in <(String, String)>[
        ('姓名', profile.name),
        ('出生地', profile.place),
        ('性别', profile.gender),
        ('长大想做', profile.dream),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      switch (step) {
        0 => _registerQuestion(
          '你叫什么名字？',
          _fieldText(
            keyName: 'register-name',
            value: profile.name,
            placeholder: '写下你的名字',
            maxLength: 8,
            onChanged: (String v) => _profileInput('name', v),
          ),
          () => _registerTextNext('name'),
        ),
        1 => _registerQuestion(
          '你出生在哪？',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _fieldText(
                keyName: 'register-place',
                value: profile.place,
                placeholder: '一座城市，一个镇子，或者想不起来',
                maxLength: 14,
                onChanged: (String v) => _profileInput('place', v),
              ),
              _chips(
                const <String>['上海', '一座很小的县城', '想不起来'],
                (String v) => _registerChip('place', v),
                keyPrefix: 'place-chip',
              ),
            ],
          ),
          () => _registerTextNext('place'),
        ),
        2 => _registerQuestion(
          '男孩还是女孩？',
          const SizedBox.shrink(),
          null,
          chips: _chips(
            const <String>['男孩', '女孩', '不想说'],
            (String v) => _registerChip('gender', v),
            keyPrefix: 'gender-chip',
          ),
        ),
        3 => _registerQuestion(
          '你长大想做什么？',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _fieldText(
                keyName: 'register-dream',
                value: profile.dream,
                placeholder: '比如：宇航员、画家、去很远的地方',
                maxLength: 16,
                onChanged: (String v) => _profileInput('dream', v),
              ),
              _chips(
                const <String>['宇航员', '画家', '医生', '去很远的地方', '不知道'],
                (String v) => _registerChip('dream', v),
                keyPrefix: 'dream-chip',
              ),
            ],
          ),
          () => _registerTextNext('dream'),
        ),
        4 => Column(
          key: const Key('register-avatar'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '最后，贴一张你自己的照片',
              style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Center(
              child: CupertinoButton(
                onPressed: _chooseAvatar,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgSurface,
                    border: Border.all(color: AppColors.divider),
                    image: profile.avatar.startsWith('http')
                        ? DecorationImage(
                            image: NetworkImage(profile.avatar),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: profile.avatar.isEmpty
                      ? Text(
                          _displayName.characters.first,
                          style: const TextStyle(
                            fontSize: 30,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '会出现在登记表、你留给别人的话和最后一个梦里。只存在这台手机上。',
              style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              key: const Key('avatar-upload'),
              color: AppColors.primary,
              onPressed: _chooseAvatar,
              child: const Text(
                '上传我的照片',
                style: TextStyle(color: AppColors.onPrimary),
              ),
            ),
            CupertinoButton(
              key: const Key('avatar-skip'),
              onPressed: _skipAvatar,
              child: const Text(
                '不贴，用名字的第一个字',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ],
        ),
        _ => Column(
          key: const Key('register-sealed'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '各项指标在范围内',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.textDisabled,
              ),
            ),
            const SizedBox(height: 8),
            _npc('护士', '合上登记表', '“$_displayName，各项指标都在范围内。挺好的。”'),
            _voice('规矩', '你也跟着松了一口气。'),
            _paragraph('我不知道“我”是什么。但我知道，我不需要做决定。有一个声音在很远的地方说：“开始吧。”'),
            CupertinoButton(
              key: const Key('register-submit'),
              color: AppColors.primary,
              onPressed: _submitProfile,
              child: const Text(
                '回应那个声音',
                style: TextStyle(color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      },
    ];
  }

  Widget _registerQuestion(
    String question,
    Widget input,
    VoidCallback? next, {
    Widget? chips,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        question,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      const SizedBox(height: 8),
      input,
      ?chips,
      if (next != null)
        CupertinoButton(
          key: const Key('register-next'),
          color: AppColors.bgElevated,
          onPressed: next,
          child: const Text('写好了', style: TextStyle(fontSize: 15)),
        ),
    ],
  );

  Widget _bootScreen() {
    const TextStyle dim = TextStyle(fontSize: 11, color: AppColors.nodeGlow);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 24),
          Text(
            'PRESET-LIFE BIOS v1.0\n'
            '内存检测 ............ ok\n'
            '感官接口 ............ ok\n'
            '语言模块 ............ ${_bootDone ? 'ok' : '等待输入'}',
            style: dim,
          ),
          const SizedBox(height: 16),
          const Text(
            '＞ 请输入：hello world',
            style: TextStyle(fontSize: 14, color: AppColors.nodeGlow),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Row(
              key: const Key('boot-input'),
              children: <Widget>[
                for (final String ch in _bootChars)
                  Text(
                    ch == ' ' ? '·' : ch,
                    style: const TextStyle(
                      fontSize: 22,
                      color: AppColors.nodeGlow,
                    ),
                  ),
                if (!_bootDone)
                  Container(width: 12, height: 24, color: AppColors.nodeGlow),
                Text(
                  _bootGhost,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Color(0x3300E5D4),
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            child: CyNativeProgress(
              key: const Key('boot-timer'),
              progress: _bootTimerWidth / 100,
              height: 3,
              semanticLabel: '启动倒计时',
              trackColor: AppColors.bgSurface,
              progressColor: _bootError ? AppColors.danger : AppColors.nodeGlow,
            ),
          ),
          SizedBox(
            height: 20,
            child: Text(
              _bootMessage,
              style: TextStyle(
                fontSize: 12,
                color: _bootError ? AppColors.danger : AppColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          for (final List<String> row in kPrefabBootRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final String key in row)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _bootKeyButton(key, key == _bootNext),
                    ),
                  if (row == kPrefabBootRows.last)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _bootKeyButton('back', false, label: '⌫'),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _bootKeyButton(' ', _bootNext == ' ', label: 'space'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _bootKeyButton(String key, bool isNext, {String? label}) =>
      CupertinoButton(
        key: Key('boot-key-$key'),
        minimumSize: const Size(28, 34),
        padding: EdgeInsets.zero,
        color: isNext ? AppColors.bgElevated : AppColors.bgSurface,
        onPressed: () => _bootKey(key),
        child: Text(
          label ?? key,
          style: TextStyle(
            fontSize: 13,
            color: isNext ? AppColors.nodeGlow : AppColors.textPrimary,
          ),
        ),
      );

  List<Widget> _walkBody() => <Widget>[
    _paragraph('今天要去人民广场一带的四个地方。走过去，看看那里的人，然后把这一生过完。'),
    Container(
      key: const Key('walk-route-card'),
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '● 路线 · 前往第 1 站',
            style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 6),
          const Text(
            '上海城市规划展示馆 · 约 420 米',
            style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            child: CyNativeProgress(
              key: const Key('walk-progress'),
              progress: _state.walkProgress / 100,
              height: 4,
              semanticLabel: '步行进度',
              trackColor: AppColors.bgElevated,
              progressColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                '左上角的小地图跟着你走',
                style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
              ),
              Text(
                '$_walkLeft m',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    if (_state.walkProgress >= 50) _voice('窗外', '这条路没人推荐。路边的梧桐比别处老。'),
  ];

  List<Widget> _hallBody() => <Widget>[
    _realCard(
      keyName: 'hall-photo',
      imageSrc: prefabAsset('square'),
      kicker: '在现场 · 现实任务',
      title: '拍下展示馆的招牌',
      sub: '走进范围，打开相机。照片会盖上今天的日期。',
      onTap: _hallPhoto,
    ),
    _paragraph('展示馆门口的城市模型，像一个已经安装完成、只等你进入的世界。'),
  ];

  List<Widget> _birthBody() {
    final int step = _state.step;
    final base = <Widget>[
      _image(prefabAsset('hospital')),
      _paragraph(
        '我出生在${_state.profile.place.isEmpty ? '一个想不起来的地方' : _state.profile.place}。那天，没人问我愿不愿意。但所有人都说，我很幸运。',
      ),
      _npc(
        '护士',
        '低头看了一眼',
        '“${_state.profile.name.isEmpty ? '你' : _state.profile.name}，各项指标都在范围内。挺好的。”',
      ),
      _paragraph('空气里有晒过被子的味道，暖烘烘的。电风扇在头顶慢悠悠地转着。窗外的蝉鸣声很远，像是隔着一层水膜。'),
    ];
    switch (step) {
      case 0:
        return <Widget>[
          ...base,
          _paragraph('第一次，我想——'),
          _choice(
            keyName: 'birth-choice-0',
            text: '开心地呜呜丫丫叫起来',
            percent: '38%',
            onTap: () => _firstPick(0),
          ),
          _choice(
            keyName: 'birth-choice-1',
            text: '安静地看着窗外',
            percent: '44%',
            onTap: () => _firstPick(1),
          ),
          _choice(
            keyName: 'birth-choice-2',
            text: '像他们期待的那样哭',
            percent: '18%',
            onTap: () => _firstPick(2),
          ),
        ];
      case 1:
        return <Widget>[
          ...base,
          _npc('妈妈', '总是说', '“坐要有坐相，站要有站相。见到人要问好。别人的东西不能乱动。”'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: GestureDetector(
                key: const Key('birth-hold'),
                onLongPressStart: (_) => _standStart(),
                onLongPressEnd: (_) => _standEnd(),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _HoldRingPainter(
                      progress: _holdProgress / 100,
                      active: _holding,
                    ),
                    child: const Center(
                      child: Text(
                        '按住\n站好',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Text(
            '保持 3 秒。你看，我现在站得直直的。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ];
      case 2:
        return <Widget>[
          ...base,
          _realCard(
            keyName: 'window-photo',
            imageSrc: _state.photos['window'] ?? prefabAsset('win'),
            kicker: '在现场 · 拍一张',
            title: '现在，安静地看着窗外',
            sub: '画面里要看得见窗框，和窗外的光。这张照片会回到梦里。',
            onTap: _windowPhoto,
          ),
        ];
      default:
        return <Widget>[
          ...base,
          _paragraph('那扇窗外，你看到了什么？这句话会留给之后来这里的人——也会留给你自己。'),
          _chips(
            const <String>['有人在遛狗', '有人在拍照', '一片云', '车流', '什么也没有'],
            _pickNote,
            keyPrefix: 'note-chip',
          ),
          const SizedBox(height: 8),
          _fieldText(
            keyName: 'note-field',
            value: _noteText,
            placeholder: '写下你看见的',
            maxLength: 40,
            onChanged: (String v) => setState(() => _noteText = v),
          ),
          CupertinoButton(
            key: const Key('note-submit'),
            color: AppColors.primary,
            onPressed: _submitNote,
            child: const Text(
              '留在这里',
              style: TextStyle(color: AppColors.onPrimary),
            ),
          ),
          const SizedBox(height: 12),
          for (final (String who, String text, String meta)
              in <(String, String, String)>[
                ('晴', '一个老人在等公交，等了很久。', '♡ 23 · 3 天前'),
                ('K', '玻璃门上映着我自己。', '♡ 41 · 昨天'),
                ('阿木', '什么也没有。好安静。', '♡ 9 · 2 小时前'),
              ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 44,
                    child: Text(
                      who,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          text,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ];
    }
  }

  List<Widget> _dreamBody() {
    final List<PrefabDreamCard> cards = prefabDreamCards(_state.scene, _state);
    if (cards.isEmpty) return const <Widget>[];
    final PrefabDreamCard card = cards[min(_dreamIndex, cards.length - 1)];
    return <Widget>[
      GestureDetector(
        key: const Key('dream-stage'),
        onLongPressStart: (_) => _wakeStart(),
        onLongPressEnd: (_) => _wakeEnd(),
        onLongPressCancel: _wakeEnd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _imageAny(card.src, height: 320),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                card.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  // 真源末张卡片 `is-final`:字重落定,其余在漂。
                  fontWeight: _dreamReady ? FontWeight.w600 : FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              '${_dreamIndex + 1} / ${cards.length} · 一张张从眼前穿过去',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              child: CyNativeProgress(
                key: const Key('wake-progress'),
                progress: _wakeProgress / 100,
                height: 3,
                semanticLabel: '唤醒进度',
                trackColor: AppColors.bgSurface,
                progressColor: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '按住屏幕会醒来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _learningBody() {
    final int step = _state.step;
    switch (step) {
      case 0:
        const List<(List<String>, int)> quiz = <(List<String>, int)>[
          (<String>['模型比例是 1:100', '模型比例是 1:500'], 1),
          (<String>['人民广场', '陆家嘴'], 0),
          (<String>['一条已经走过的路', '一块你从没去过的地方'], 1),
        ];
        final (List<String> options, int answer) = quiz[_quizIndex];
        return <Widget>[
          _image(prefabAsset('model')),
          _npc('陈老师', '展示馆讲解员', '“先找到自己熟悉的地方，再找一块你从没去过的。”'),
          _paragraph('讲解员的问题 · ${_quizIndex + 1} / 3'),
          for (int i = 0; i < options.length; i++)
            _choice(
              keyName: 'quiz-$i',
              text: options[i],
              onTap: () => _quizPick(i, answer),
            ),
        ];
      case 1:
        return <Widget>[
          _realCard(
            kicker: '在现场',
            title: '数一数，模型前有几个人在低头看手机？',
            sub: '',
            onTap: () {},
          ),
          _fieldText(
            keyName: 'count-field',
            value: _countText,
            placeholder: '0',
            maxLength: 3,
            onChanged: (String v) => setState(() => _countText = v),
          ),
          CupertinoButton(
            key: const Key('count-submit'),
            color: AppColors.primary,
            onPressed: _submitCount,
            child: const Text(
              '记下来',
              style: TextStyle(color: AppColors.onPrimary),
            ),
          ),
        ];
      case 2:
        return <Widget>[
          _image(prefabAsset('classroom')),
          _paragraph('很多年以后，我第一次被要求坐好，是在一张很小的桌子前。凳子比我想象中硬。我的脚够不到地，只能悬在半空里晃。'),
          _paragraph(
            '我发现问题本身没那么重要，但我需要答对那个“标准答案”。后来，我慢慢坐到了班级的后排。老师的声音很远，让我感到安全。',
          ),
          _voice('精密', '翅膀每秒振动两百次。腿上有绒毛。它很精密，像一道优美的数学题。'),
          _npc(
            '老师',
            '站在你旁边',
            '“${_state.profile.name.isEmpty ? '你' : _state.profile.name}，来，站起来，你来回答一下？”',
          ),
          _paragraph('限时 · 你决定——  $_teacherSeconds 秒'),
          _choice(
            keyName: 'teacher-0',
            text: '背出课本上的标准答案',
            onTap: () => _teacherPick(0),
          ),
          _choice(
            keyName: 'teacher-1',
            text: '“我在看窗外。”',
            onTap: () => _teacherPick(1),
          ),
          _choice(
            keyName: 'teacher-2',
            text: '“这个问题，有标准答案吗？”',
            red: true,
            onTap: () => _teacherPick(2),
          ),
          _choice(
            keyName: 'teacher-3',
            text: '什么也不说，站得直直的',
            onTap: () => _teacherPick(3),
          ),
        ];
      default:
        return <Widget>[
          _imageAny(
            _state.photos['window'].isNullish
                ? prefabAsset('win')
                : _state.photos['window']!,
          ),
          _npc('老师', '挑了挑眉', '“窗外有什么？”'),
          _choice(
            keyName: 'window-0',
            text: '“${_state.note.isEmpty ? '什么也没有' : _state.note}。”',
            onTap: () => _teacherWindowPick(0),
          ),
          _choice(
            keyName: 'window-1',
            text: '“一只苍蝇。它很精密。”',
            red: true,
            onTap: () => _teacherWindowPick(1),
          ),
        ];
    }
  }

  List<Widget> _careerBody() {
    if (_state.step == 0) {
      return <Widget>[
        _realCard(
          keyName: 'career-map',
          kicker: '在现场',
          title: '找一块你从没去过的地方',
          sub: '在地图上贴上“未加载地图”。后来的人会看见它。',
          onTap: () => setState(() {
            _view = 'map';
            _stickerMode = true;
          }),
        ),
      ];
    }
    return <Widget>[
      _paragraph(
        '那个有蝉鸣的下午，就突然不见了。你说过，你长大想当${_state.profile.dream.isEmpty ? '什么' : _state.profile.dream}。',
      ),
      for (final PrefabJob job in kPrefabJobs)
        _choice(
          keyName: 'career-${job.name}',
          text: '${job.name} —— ${job.sub}',
          onTap: () => _careerPick(job.name),
        ),
    ];
  }

  List<Widget> _workBody() {
    final PrefabJob job = kPrefabJobs.firstWhere(
      (PrefabJob j) => j.name == _state.job,
      orElse: () => kPrefabJobs.first,
    );
    final base = <Widget>[
      _image(prefabAsset(prefabJobImage(_state.job))),
      _paragraph(
        '有人把我带到其中一张桌子前，说：“${_state.profile.name.isEmpty ? '你' : _state.profile.name}，这是你的工位。”他说得很自然，像是在把一件物品放回它该在的位置。',
      ),
      _paragraph('桌子上摆放了我需要的所有东西：${job.desk}。我的任务会被拆解，目标会被量化，时间被切成一块一块。'),
      _voice('规矩', '“${job.task}”'),
    ];
    if (_state.step == 0) {
      return <Widget>[
        ...base,
        _npc('老板', '在会议室里', '“这个……先放一放。”'),
        _paragraph('故事里 · 你说——'),
        _choice(keyName: 'boss-0', text: '“收到。”', onTap: () => _bossPick(0)),
        _choice(
          keyName: 'boss-1',
          text: '“从结果来看，这版更好。”',
          onTap: () => _bossPick(1),
        ),
        _choice(
          keyName: 'boss-2',
          text: '“我想试试这个。”',
          red: true,
          onTap: () => _bossPick(2),
        ),
        _choice(
          keyName: 'boss-3',
          text: '站起来，离开会议室',
          onTap: () => _bossPick(3),
        ),
      ];
    }
    return <Widget>[
      ...base,
      _paragraph('有一次，${job.ignored}老板路过你的工位，只说：“先按原来的来。”'),
      if ((_state.photos['window'] ?? '').isNotEmpty)
        _imageAny(_state.photos['window']!),
      _paragraph(
        '那天晚上，我坐在工位上很久。屏幕已经暗了。办公室里只剩下空调的声音。下楼的时候，路口的灯是红的。你想起白天数过的那 ${_state.picks['count'] ?? 0} 个人。',
      ),
      _realCard(
        keyName: 'phone-photo',
        imageSrc: prefabAsset('phone'),
        kicker: '在现场 · 现实任务',
        title: '拍一个低头看手机的人',
        sub: '不拍脸。背影、手，或者只有那块亮着的屏幕。',
        onTap: _phonePhoto,
      ),
    ];
  }

  List<Widget> _flowBody() {
    final Map<String, Object?> picks = _state.picks;
    String picked(
      Object? value,
      Map<int, String> labels, {
      String fallback = '',
    }) => labels[value as int? ?? -1] ?? fallback;
    return <Widget>[
      Center(
        child: Text(
          '$_displayName 的第一段人生',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      const SizedBox(height: 16),
      _flowNode('路上 · 偏离推荐路线', <Widget>[
        _flowOption('重新规划 · 57%', picks['route'] == 0),
        _flowOption('继续这条路 · 43%', picks['route'] == 1),
      ]),
      _flowNode('第一次，我想——', <Widget>[
        _flowOption('开心地叫起来 · 38%', picks['first'] == 0),
        _flowOption('安静地看窗外 · 44%', picks['first'] == 1),
        _flowOption('像他们期待的那样哭 · 18%', picks['first'] == 2),
      ]),
      _flowNode('讲解员的三个问题', <Widget>[
        _flowOption(
          '答对 ${picks['quiz'] ?? 0} 题${(picks['quiz'] as int? ?? 0) >= 2 ? ' · 幸运 +1' : ''}',
          true,
        ),
      ]),
      _flowNode('老师让你站起来', <Widget>[
        _flowOption(
          picked(picks['teacher'], <int, String>{
            0: '背出标准答案',
            1: '“我在看窗外”',
            2: '“这个问题，有标准答案吗？”',
            3: '什么也不说，站得直直的',
          }),
          true,
        ),
      ]),
      _flowNode('老板说“这个……先放一放”', <Widget>[
        _flowOption(
          picked(picks['boss'], <int, String>{
            0: '“收到。”',
            1: '“从结果来看，这版更好。”',
            2: '“我想试试这个。”',
            3: '站起来，离开会议室',
          }),
          true,
        ),
      ]),
      _flowNode('长大了，你希望做什么', <Widget>[_flowOption(_state.job, true)]),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _flowSummary('${_state.photoCount}', '拍下的照片'),
          _flowSummary('${_state.dreams}', '梦'),
          _flowSummary('${_state.thoughts.length}', '念头'),
        ],
      ),
      if ((_state.photos['hall'] ?? '').isNotEmpty ||
          (_state.photos['phone'] ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: <Widget>[
              if ((_state.photos['hall'] ?? '').isNotEmpty)
                Expanded(child: _imageAny(_state.photos['hall']!, height: 120)),
              if ((_state.photos['hall'] ?? '').isNotEmpty &&
                  (_state.photos['phone'] ?? '').isNotEmpty)
                const SizedBox(width: 8),
              if ((_state.photos['phone'] ?? '').isNotEmpty)
                Expanded(
                  child: _imageAny(_state.photos['phone']!, height: 120),
                ),
            ],
          ),
        ),
      if (_syncError.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoButton(
            key: const Key('flow-sync-error'),
            padding: EdgeInsets.zero,
            onPressed: _syncCompletion,
            child: Text(
              '现场记录暂未同步\n$_syncError · 再试一次',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
        ),
    ];
  }

  Widget _flowNode(String title, List<Widget> options) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(height: 4),
        ...options,
      ],
    ),
  );

  Widget _flowOption(String text, bool isMine) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      key: isMine ? Key('flow-mine-$text') : null,
      style: TextStyle(
        fontSize: 14,
        fontWeight: isMine ? FontWeight.w600 : FontWeight.w400,
        color: isMine ? AppColors.textPrimary : AppColors.textDisabled,
      ),
    ),
  );

  Widget _flowSummary(String number, String label) => Column(
    children: <Widget>[
      Text(
        number,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
      ),
    ],
  );

  Widget _realCard({
    String? keyName,
    String? imageSrc,
    required String kicker,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: CupertinoButton(
      key: keyName == null ? null : Key(keyName),
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (imageSrc != null) _image(imageSrc, height: 150),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    kicker,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (sub.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── 地图视图(真源自绘的虚构地图:网格/苏州河/两条路/三个 pin)──

  Widget _mapView() {
    final PrefabSticker? sticker = _state.sticker;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: CustomPaint(painter: _FakeCityMapPainter())),
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    CupertinoButton(
                      key: const Key('map-back-story'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: AppColors.bgSurface,
                      onPressed: () => setState(() {
                        _view = 'story';
                        _stickerMode = false;
                      }),
                      child: const Text(
                        '故事',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '预制人生',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '地图 · 此刻 2 人在附近',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 中缝留空,露出底下 Positioned.fill 的自绘地图。
              const Spacer(),
              if (_mapBubble case final PrefabMapNote bubble)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    key: const Key('map-bubble'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '${bubble.who} 留在这里',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  setState(() => _mapBubble = null),
                              child: const Icon(
                                CupertinoIcons.clear_circled_solid,
                                size: 18,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          bubble.text,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        CupertinoButton(
                          key: const Key('map-bubble-like'),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          onPressed: () => _likeMapNote(bubble),
                          child: Text(
                            '♡ ${bubble.likes}',
                            style: TextStyle(
                              fontSize: 13,
                              color: bubble.liked
                                  ? AppColors.danger
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (sticker != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    '$_displayName · ${sticker.label}',
                    key: const Key('map-sticker'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.nodeGlow,
                    ),
                  ),
                ),
              if (_stickerMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    key: const Key('sticker-picker'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '贴一张在这里',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          for (final String label in const <String>[
                            '未加载地图',
                            '这里有风',
                            '以后再来',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: CupertinoButton(
                                key: Key('sticker-$label'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                color: AppColors.bgSurface,
                                onPressed: () => _placeSticker(label),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '当前任务 · 第 1 站',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textDisabled,
                          ),
                        ),
                        Text(
                          _stationName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _stationAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: () => setState(() => _view = 'story'),
                            child: const Text(
                              '回到故事',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.nodeGlow,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final (int index, String name) in <(int, String)>[
          (1, '城市规划展示馆'),
          (2, '人民广场站'),
          (3, '第一百货'),
        ])
          Positioned(
            left: 30.0 + index * 78,
            top: 140.0 + (index * 90) % 200,
            child: _mapPin(index, name),
          ),
        for (final (int index, PrefabMapNote note) in _mapNotes.indexed)
          Positioned(
            left: index == 0 ? 90 : 210,
            top: index == 0 ? 300 : 210,
            child: CupertinoButton(
              key: Key('map-note-${note.who}'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _mapBubble = note),
              child: Text(
                note.who,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _likeMapNote(PrefabMapNote bubble) {
    if (bubble.liked) return;
    setState(() {
      _mapNotes = <PrefabMapNote>[
        for (final PrefabMapNote n in _mapNotes)
          if (n.id == bubble.id) n.like() else n,
      ];
      _mapBubble = _mapNotes.firstWhere((PrefabMapNote n) => n.id == bubble.id);
    });
    _feel();
  }

  Widget _mapPin(int number, String name) => Column(
    key: Key('map-pin-$number'),
    children: <Widget>[
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
        ),
        child: Text(
          '$number',
          style: const TextStyle(fontSize: 12, color: AppColors.onPrimary),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        name,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    ],
  );

  // ── 覆盖层 ─────────────────────────────────────────────────

  Widget _promptSheet({
    required String kicker,
    required String title,
    required String left,
    required VoidCallback onLeft,
    required String right,
    required VoidCallback onRight,
  }) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xCC000000),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    kicker,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          key: Key('prompt-$left'),
                          color: AppColors.bgElevated,
                          onPressed: onLeft,
                          child: Text(
                            left,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoButton(
                          key: Key('prompt-$right'),
                          color: AppColors.primary,
                          onPressed: onRight,
                          child: Text(
                            right,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _checkSheet(PrefabCheckResult check) => _promptSheet(
    kicker: _checkLabel,
    title: '两颗骰子 ${check.roll} + 能力 = ${check.score} · 难度 ${check.dc}',
    left: check.ok ? '成功' : '失败',
    onLeft: () {},
    right: '继续',
    onRight: _closeCheck,
  );

  Widget _endingsSheet() => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xE6000000),
      child: SafeArea(
        child: Center(
          child: Container(
            key: const Key('endings-panel'),
            width: 340,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  '全剧结局',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '一共 6 个。${_state.profile.name.isEmpty ? '你' : _state.profile.name}在这一站做的事，会一路影响到终章。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final List<String> ending in kPrefabEndings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${ending[0]} · ${ending[3]} 的人',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                ending[1],
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.nodeGlow,
                                ),
                              ),
                              Text(
                                ending[2],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  key: const Key('endings-close'),
                  color: AppColors.primary,
                  onPressed: () => setState(() => _showEndings = false),
                  child: const Text(
                    '回到故事',
                    style: TextStyle(color: AppColors.onPrimary),
                  ),
                ),
                CupertinoButton(
                  key: const Key('endings-reset'),
                  onPressed: _reset,
                  child: const Text(
                    '从头再来',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PrefabLoading extends StatelessWidget {
  const _PrefabLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CupertinoActivityIndicator(radius: 14),
        SizedBox(height: 10),
        Text(
          '正在进入这一段人生',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _PrefabError extends StatelessWidget {
  const _PrefabError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 28,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 10),
          const Text(
            '这一段人生没有加载出来',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          CupertinoButton(
            key: const Key('prefab-retry'),
            color: AppColors.primary,
            onPressed: onRetry,
            child: const Text(
              '重新加载',
              style: TextStyle(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawCircle(
      rect.center,
      size.width / 2 - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.divider,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: rect.center, radius: size.width / 2 - 4),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.nodeGlow,
      );
    }
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) =>
      old.progress != progress || old.active != active;
}

class _FakeCityMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bgDeep);
    final Paint grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 0.6;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // 苏州河:一条斜穿的水带;两条主干道。
    final Paint river = Paint()
      ..color = const Color(0x295587C7)
      ..strokeWidth = 26
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height * 0.32),
      Offset(size.width, size.height * 0.18),
      river,
    );
    final Paint road = Paint()
      ..color = AppColors.bgElevated
      ..strokeWidth = 8;
    canvas.drawLine(
      Offset(size.width * 0.18, 0),
      Offset(size.width * 0.30, size.height),
      road,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width, size.height * 0.55),
      road,
    );
  }

  @override
  bool shouldRepaint(_FakeCityMapPainter old) => false;
}

extension on String? {
  bool get isNullish => this == null || this!.isEmpty;
}
