import 'dart:async';

import 'package:chengyin_app/data/models/object_card.dart';
import 'package:chengyin_app/feature/p3/object_cards/object_cards_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-load failure is not empty; failed category keeps previous cards', () async {
    var fail = true;
    const original = ObjectCardCollection(cards: [
      ObjectCard(id: '1', title: 'Original', frames: ['photo']),
    ], total: 80);
    final controller = ObjectCardsController((_) async {
      if (fail) throw StateError('offline');
      return original;
    });
    expect(await controller.load(''), isFalse);
    expect(controller.error, isTrue);
    expect(controller.collection, isNull);
    expect(controller.loading, isFalse);
    fail = false;
    expect(await controller.load(''), isTrue);
    fail = true;
    expect(await controller.load('电子产品'), isFalse);
    expect(controller.collection, same(original));
    expect(controller.category, '');
    expect(controller.error, isFalse);
    controller.dispose();
  });

  test('successful empty filter is distinct from failure', () async {
    final controller = ObjectCardsController((_) async =>
        const ObjectCardCollection(cards: [], total: 0));
    expect(await controller.load('书籍文具'), isTrue);
    expect(controller.category, '书籍文具');
    expect(controller.collection!.cards, isEmpty);
    expect(controller.error, isFalse);
    controller.dispose();
  });

  test('late response after disposal does not notify or replace state', () async {
    final response = Completer<ObjectCardCollection>();
    final controller = ObjectCardsController((_) => response.future);
    final pending = controller.load('');
    expect(controller.loading, isTrue);
    expect(await controller.load('其他'), isFalse);
    controller.dispose();
    response.complete(const ObjectCardCollection(cards: [], total: 0));
    expect(await pending, isFalse);
    expect(controller.collection, isNull);
  });
  test('account reset clears old data and rejects pending earlier owner response', () async {
    final oldResponse = Completer<ObjectCardCollection>();
    var calls = 0;
    const next = ObjectCardCollection(cards: [], total: 0);
    final controller = ObjectCardsController((_) {
      calls++;
      return calls == 1 ? oldResponse.future : Future.value(next);
    });
    final pending = controller.load('');
    controller.reset();
    expect(controller.collection, isNull);
    expect(controller.loading, isFalse);
    expect(await controller.load('其他'), isTrue);
    oldResponse.complete(const ObjectCardCollection(cards: [
      ObjectCard(id: 'old-owner', title: 'Private', frames: []),
    ], total: 1));
    expect(await pending, isFalse);
    expect(controller.collection, same(next));
    expect(controller.category, '其他');
    controller.reset();
    expect(controller.collection, isNull);
    controller.dispose();
  });

}
