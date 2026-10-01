import 'package:flutter/foundation.dart';

import '../../../data/models/object_card.dart';

/// Keeps a failed filter separate from a successfully loaded empty collection.
class ObjectCardsController extends ChangeNotifier {
  ObjectCardsController(this.fetch);
  final Future<ObjectCardCollection> Function(String category) fetch;
  ObjectCardCollection? collection;
  String category = '';
  bool loading = false;
  bool error = false;
  bool _disposed = false;
  int _generation = 0;

  /// Invalidate all in-flight work before switching the authenticated owner.
  void reset() {
    if (_disposed) return;
    _generation++;
    collection = null;
    category = '';
    loading = false;
    error = false;
    notifyListeners();
  }

  /// False means failure; a previous collection/category remains authoritative.
  Future<bool> load(String next) async {
    if (loading || _disposed) return false;
    final generation = _generation;
    loading = true;
    error = false;
    notifyListeners();
    try {
      final result = await fetch(next);
      if (_disposed || generation != _generation) return false;
      collection = result;
      category = next;
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) error = collection == null;
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
