import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/models/marketing_consent.dart';
import 'package:chengyin_app/feature/orders/marketing_consent_entry.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

MarketingConsent _row({
  int merchantRowId = 7,
  int ownerMemberId = 5,
  String name = '测试商家',
  bool inApp = false,
}) => MarketingConsent(
  merchantRowId: merchantRowId,
  merchantOwnerMemberId: ownerMemberId,
  merchantName: name,
  inAppOptedIn: inApp,
  couponOptedIn: false,
);

class _FakeApi implements PageParityApi {
  _FakeApi({
    this.rows = const <MarketingConsent>[],
    this.loadError,
    this.setError,
  });

  final List<MarketingConsent> rows;
  final Object? loadError;
  final Object? setError;

  int loadCalls = 0;
  final List<Map<String, Object?>> setCalls = <Map<String, Object?>>[];

  @override
  Future<List<MarketingConsent>> marketingConsents() async {
    loadCalls += 1;
    if (loadError != null) throw loadError!;
    return rows;
  }

  @override
  Future<List<MarketingConsent>> setMarketingConsent({
    required int merchantRowId,
    required int merchantOwnerMemberId,
    required String channel,
    required bool optedIn,
    required String requestId,
  }) async {
    setCalls.add(<String, Object?>{
      'merchantRowId': merchantRowId,
      'merchantOwnerMemberId': merchantOwnerMemberId,
      'channel': channel,
      'optedIn': optedIn,
      'requestId': requestId,
    });
    if (setError != null) throw setError!;
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('pickConsentOffer', () {
    test('owner 缺失/非正一律没有 offer —— 不赌', () {
      final rows = <MarketingConsent>[_row()];
      expect(pickConsentOffer(rows, null), isNull);
      expect(pickConsentOffer(rows, 0), isNull);
      expect(pickConsentOffer(rows, -5), isNull);
    });

    test('0 条或 >1 条匹配都没有 offer(歧义不赌)', () {
      expect(pickConsentOffer(<MarketingConsent>[], 5), isNull);
      expect(
        pickConsentOffer(<MarketingConsent>[
          _row(merchantRowId: 7),
          _row(merchantRowId: 8),
        ], 5),
        isNull,
      );
    });

    test('站内已同意过 → 不再打扰', () {
      expect(
        pickConsentOffer(<MarketingConsent>[_row(inApp: true)], 5),
        isNull,
      );
    });

    test('merchantRowId 非正 → 记录残缺,不给 offer', () {
      expect(
        pickConsentOffer(<MarketingConsent>[_row(merchantRowId: 0)], 5),
        isNull,
      );
    });

    test('命中:三字段带出;空商家名回落「商家」', () {
      final ConsentOffer? offer = pickConsentOffer(<MarketingConsent>[
        _row(),
      ], 5);
      expect(offer, isNotNull);
      expect(offer!.merchantRowId, 7);
      expect(offer.merchantOwnerMemberId, 5);
      expect(offer.merchantName, '测试商家');
      // fromJson 已把空名归一成「商家」,构造器直给空串时这里再兜一次。
      final ConsentOffer? blank = pickConsentOffer(<MarketingConsent>[
        _row(name: ''),
      ], 5);
      expect(blank!.merchantName, '商家');
    });
  });

  group('loadConsentOffer', () {
    test('加载是静默的:任何失败都当没有 offer', () async {
      final api = _FakeApi(loadError: Exception('CRM 不可用'));
      expect(await loadConsentOffer(api, 5), isNull);
    });

    test('成功时按 owner 挑出 offer', () async {
      final api = _FakeApi(rows: <MarketingConsent>[_row()]);
      final ConsentOffer? offer = await loadConsentOffer(api, 5);
      expect(offer!.merchantRowId, 7);
      expect(api.loadCalls, 1);
    });
  });

  group('newConsentRequestId', () {
    test('consent-<kind>-<ts36>-<rand36>,每次不同', () {
      final a = newConsentRequestId('order');
      final b = newConsentRequestId('order');
      expect(a, matches(RegExp(r'^consent-order-[0-9a-z]+-[0-9a-z]+$')));
      expect(a, isNot(b));
    });
  });

  group('submitConsent', () {
    test('成功返回 null;IN_APP + optedIn=true + requestId 原样透传', () async {
      final api = _FakeApi();
      const offer = ConsentOffer(
        merchantRowId: 7,
        merchantOwnerMemberId: 5,
        merchantName: '测试商家',
      );
      expect(
        await submitConsent(
          api,
          offer: offer,
          optedIn: true,
          requestId: 'consent-order-x',
        ),
        isNull,
      );
      expect(api.setCalls.single, <String, Object?>{
        'merchantRowId': 7,
        'merchantOwnerMemberId': 5,
        'channel': 'IN_APP',
        'optedIn': true,
        'requestId': 'consent-order-x',
      });
    });

    test('业务异常带 msg 用 msg,空 msg 回落「同意没有保存成功，请重试」', () async {
      final withMsg = _FakeApi(
        setError: const PageParityApiException('营销同意状态未确认，请重试'),
      );
      const offer = ConsentOffer(
        merchantRowId: 7,
        merchantOwnerMemberId: 5,
        merchantName: '测试商家',
      );
      expect(
        await submitConsent(
          withMsg,
          offer: offer,
          optedIn: true,
          requestId: 'r',
        ),
        '营销同意状态未确认，请重试',
      );
      final blank = _FakeApi(setError: const PageParityApiException('   '));
      expect(
        await submitConsent(blank, offer: offer, optedIn: true, requestId: 'r'),
        '同意没有保存成功，请重试',
      );
    });

    test('网络失败 → 「网络连接失败，请重试」', () async {
      final api = _FakeApi(
        setError: DioException(
          requestOptions: RequestOptions(
            path: '/api/merchant/crm/marketing-consents',
          ),
        ),
      );
      const offer = ConsentOffer(
        merchantRowId: 7,
        merchantOwnerMemberId: 5,
        merchantName: '测试商家',
      );
      expect(
        await submitConsent(api, offer: offer, optedIn: true, requestId: 'r'),
        '网络连接失败，请重试',
      );
    });
    test('localized fallbacks preserve nonempty backend messages and request identity', () async {
      const offer = ConsentOffer(merchantRowId: 7, merchantOwnerMemberId: 5, merchantName: '原始商家');
      for (final entry in <(Object, String)>[
        (const PageParityApiException(''), 'Could not save'),
        (const PageParityApiException('原始后端说明'), '原始后端说明'),
        (DioException(requestOptions: RequestOptions(path: '/test')), 'Connection failed'),
      ]) {
        final api = _FakeApi(setError: entry.$1);
        expect(await submitConsent(api, offer: offer, optedIn: true,
          requestId: 'stable-request', saveFailureText: 'Could not save',
          networkFailureText: 'Connection failed'), entry.$2);
        expect(api.setCalls.single['requestId'], 'stable-request');
        expect(api.setCalls.single['channel'], 'IN_APP');
        expect(api.setCalls.single['merchantOwnerMemberId'], 5);
      }
    });
  });
}
