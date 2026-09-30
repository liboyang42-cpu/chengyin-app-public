import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/community_report_reason.dart';
import 'package:chengyin_app/data/models/square_draft.dart';
import 'package:chengyin_app/data/models/square_post.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions options) reply;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 小程序契约的入参是 form 表单(`FormData`),不是 JSON —— 取字段走 `.fields`。
String? _formField(RequestOptions options, String name) {
  final Object? data = options.data;
  if (data is! FormData) return null;
  for (final MapEntry<String, String> field in data.fields) {
    if (field.key == name) return field.value;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('关注流把 following 作为真实后端查询条件发送', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[]},
      },
    );
    client.dio.httpClientAdapter = adapter;

    await SquareApi(client).list(feedMode: SquareFeedMode.following);

    expect(adapter.sent.single.path, '/api/v1/community/feeds/FOLLOWING');
    expect(adapter.sent.single.method, 'GET');
  });

  test('附近流没有真实城市时拒绝发送占位参数', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );

    await expectLater(
      SquareApi(client).list(feedMode: SquareFeedMode.nearby),
      throwsA(isA<StateError>()),
    );
  });

  test('热门流续页同时发送分数和 id 游标', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'items': <dynamic>[]},
      },
    );
    client.dio.httpClientAdapter = adapter;

    await SquareApi(
      client,
    ).listPage(feedMode: SquareFeedMode.trending, cursor: 42, cursorScore: 987);

    expect(adapter.sent.single.queryParameters['cursor'], 42);
    expect(adapter.sent.single.queryParameters['cursorScore'], 987);
  });

  test('话题与社群流必须携带明确分区标识', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'items': <dynamic>[]},
      },
    );
    client.dio.httpClientAdapter = adapter;
    final SquareApi api = SquareApi(client);

    await api.listPage(feedMode: SquareFeedMode.topic, topicCode: '9201');
    await api.listPage(feedMode: SquareFeedMode.community, communityId: 55);

    expect(adapter.sent[0].path, '/api/v1/community/feeds/TOPIC');
    expect(adapter.sent[0].queryParameters['topicCode'], '9201');
    expect(adapter.sent[1].path, '/api/v1/community/feeds/COMMUNITY');
    expect(adapter.sent[1].queryParameters['communityId'], 55);
    await expectLater(
      api.listPage(feedMode: SquareFeedMode.topic),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      api.listPage(feedMode: SquareFeedMode.community),
      throwsA(isA<StateError>()),
    );
  });

  test('广场举报打到真实端点,只带 id', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{'code': 200, 'msg': '举报已提交，内容将进入审核'},
    );
    client.dio.httpClientAdapter = adapter;

    final String msg = await SquareApi(client).report(42);

    expect(adapter.sent.single.path, '/api/creativesquare/report');
    // 后端 /api/creativesquare/report 不收理由 —— 界面也不该收一个送不出去的
    // 理由(「收了就半路扔掉」是同一条门禁判过的病)。
    expect(_formField(adapter.sent.single, 'id'), '42');
    expect(msg, '举报已提交，内容将进入审核');
  });

  test('评论举报打在评论自己身上,不是帖文', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{'code': 200, 'msg': '举报已提交，评论将进入审核'},
    );
    client.dio.httpClientAdapter = adapter;

    await SquareApi(client).reportComment(17);

    expect(adapter.sent.single.path, '/api/comment/report');
    expect(_formField(adapter.sent.single, 'id'), '17');
  });

  test('广场从后端读取带版本号的举报原因合同', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reporting': <String, dynamic>{
            'policyVersion': 'COMMUNITY_REPORT_POLICY_V2',
            'reasons': <Map<String, dynamic>>[
              <String, dynamic>{
                'code': 'SAFETY_V2',
                'label': '新版安全风险',
                'priority': 'URGENT',
                'firstResponseMinutes': 10,
                'emergency': true,
              },
            ],
          },
        },
      },
    );
    client.dio.httpClientAdapter = adapter;

    final CommunityReportPolicySnapshot policy = await SquareApi(
      client,
    ).reportPolicy();

    expect(adapter.sent.single.path, '/api/v1/community/capabilities');
    expect(policy.policyVersion, 'COMMUNITY_REPORT_POLICY_V2');
    expect(policy.reasons.single.code, 'SAFETY_V2');
    expect(policy.reasons.single.label, '新版安全风险');
  });

  test('作者能读取帖文处置并提交申诉', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/me/enforcements')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'id': 17, 'post_id': 42, 'status': 'ACTIVE'},
            ],
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final SquareApi api = SquareApi(client);
    final rows = await api.myEnforcements(cursor: 23);
    await api.appealEnforcement(17, '这是一次误判，请复核');

    expect(rows.single['post_id'], 42);
    expect(adapter.sent[0].path, '/api/v1/community/me/enforcements');
    expect(adapter.sent[0].queryParameters['cursor'], 23);
    expect(adapter.sent[1].path, '/api/v1/community/appeals');
    expect(
      adapter.sent[1].data as Map<String, dynamic>,
      containsPair('enforcementId', 17),
    );
  });

  test('发布按公约确认、草稿、内容安全发布的顺序完成', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/guidelines/active')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'id': 5},
        };
      }
      if (options.path.endsWith('/posts')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 77,
              'authorId': 9,
              'body': '在地记录',
              'version': 0,
              'lifecycle': 'DRAFT',
            },
            'media': <dynamic>[],
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final api = SquareApi(client);
    final guideline = await api.activeGuideline();
    await api.publish(
      const SquareDraft(
        workflowId: 'workflow-publish-1',
        contents: '在地记录',
        address: '昌平路桥',
        cityCode: '上海市',
        audience: 'FOLLOWERS',
        commentPolicy: 'OFF',
        replyApprovalEnabled: true,
        slowModeSeconds: 30,
        disclosureType: 'GIFTED',
        safetyLabels: <String>['WEATHER_RISK', 'ACCESSIBILITY_LIMIT'],
      ),
      guidelineVersionId: (guideline['id'] as num).toInt(),
    );

    expect(adapter.sent.map((RequestOptions item) => item.path), <String>[
      '/api/v1/community/guidelines/active',
      '/api/v1/community/guidelines/ack',
      '/api/v1/community/posts',
      '/api/v1/community/posts/77/publish',
    ]);
    final create = adapter.sent[2].data as Map<String, dynamic>;
    expect(create['audience'], 'FOLLOWERS');
    expect(create['commentPolicy'], 'OFF');
    expect(create['replyApprovalEnabled'], 1);
    expect(create['slowModeSeconds'], 30);
    expect(create['disclosureType'], 'GIFTED');
    expect(create['safetyLabels'], <String>[
      'WEATHER_RISK',
      'ACCESSIBILITY_LIMIT',
    ]);
    expect(create['cityCode'], '上海市');
    expect(create['locationPrecision'], 'CITY');
  });

  test('显式保存草稿不会确认发布公约或进入发布送审', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/posts')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 88,
              'authorId': 9,
              'body': '稍后继续写',
              'version': 0,
              'lifecycle': 'DRAFT',
            },
            'media': <dynamic>[],
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final SquarePost saved = await SquareApi(client).saveDraft(
      const SquareDraft(workflowId: 'workflow-save-draft-1', contents: '稍后继续写'),
      guidelineVersionId: 5,
    );

    expect(saved.id, 88);
    expect(adapter.sent.map((RequestOptions item) => item.path), <String>[
      '/api/v1/community/posts',
    ]);
  });

  test('已发布帖文不允许把修改稿误当服务端草稿保存', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{'code': 200},
    );
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      SquareApi(client).saveDraft(
        const SquareDraft(
          workflowId: 'edit-published-1',
          id: 77,
          expectedVersion: 4,
          sourceLifecycle: 'PUBLISHED',
          contents: '修改稿',
        ),
        guidelineVersionId: 5,
      ),
      throwsA(isA<SquarePublishException>()),
    );
    expect(adapter.sent, isEmpty);
  });

  test('仅提及者回复会发送成员范围', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/posts')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 78,
              'authorId': 9,
              'body': '邀请讨论',
              'version': 0,
              'lifecycle': 'DRAFT',
            },
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    await SquareApi(client).publish(
      const SquareDraft(
        workflowId: 'workflow-mentioned-1',
        contents: '邀请讨论',
        commentPolicy: 'MENTIONED',
        mentionedMemberIds: <int>[11, 12],
      ),
      guidelineVersionId: 5,
    );

    final create = adapter.sent.singleWhere(
      (RequestOptions request) => request.path.endsWith('/posts'),
    );
    expect(
      create.data as Map<String, dynamic>,
      containsPair('mentionedMemberIds', <int>[11, 12]),
    );
  });

  test('媒体登记发送选图得到的真实字节数', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/guidelines/active')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'id': 5},
        };
      }
      if (options.path.endsWith('/media/register')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'id': 31},
        };
      }
      if (options.path.endsWith('/posts')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 77,
              'authorId': 9,
              'body': '在地记录',
              'version': 0,
            },
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final api = SquareApi(client);
    final guideline = await api.activeGuideline();
    await api.publish(
      const SquareDraft(
        workflowId: 'workflow-media-1',
        contents: '在地记录',
        pics: <String>['https://img.test/a.jpg'],
        picByteSizes: <int>[34567],
        picMimeTypes: <String>['image/png'],
        picUploadReceipts: <String>['receipt-1'],
      ),
      guidelineVersionId: (guideline['id'] as num).toInt(),
    );

    final media =
        adapter.sent
                .firstWhere(
                  (RequestOptions item) =>
                      item.path.endsWith('/media/register'),
                )
                .data
            as Map<String, dynamic>;
    expect(media['byteSize'], 34567);
    expect(media['mimeType'], 'image/png');
    expect(media['uploadReceipt'], 'receipt-1');
  });

  test('新版读模型不会把作者私有字段误当公开媒体', () {
    final post = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{
        'id': 3,
        'authorId': 8,
        'body': '城市角落',
        'viewerBookmarked': 1,
        'approximateGeohash': 'wtw3sj',
      },
      'media': <Map<String, dynamic>>[
        <String, dynamic>{'derived_object_key': 'https://img.test/a.jpg'},
      ],
    });

    expect(post.bookmarked, isTrue);
    expect(post.pics, <String>['https://img.test/a.jpg']);
    expect(post.contents, '城市角落');
  });

  test('新版读模型解析作者安全提示标签', () {
    final post = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{
        'id': 3,
        'authorId': 8,
        'body': '夜跑路线',
        'safetyLabelsJson': '["WEATHER_RISK","ACCESSIBILITY_LIMIT"]',
      },
    });

    expect(post.safetyLabels, <String>['WEATHER_RISK', 'ACCESSIBILITY_LIMIT']);
  });

  test('评论资格缺席不能当闸门 —— 真实契约根本不投影这个字段', () {
    // ★ 2026-09-17 改口径:线上真实契约 `/api/creativesquare/info` 返的是
    //   ViewCreativeSquare,**没有** viewerCanComment —— 它只活在未落地的
    //   `/api/v1/community` 那一代。原来「缺席 ⇒ false」等于:后端说能评论、
    //   小程序里输入框常显,而 App 把整块输入框藏了。
    //   现在的规则:只有后端**显式**说 false 才关;缺席 = 没说不能 = 能评论。
    final missing = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{'id': 4, 'authorId': 8, 'body': '真实契约的帖文'},
    });
    final closed = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{'id': 5, 'authorId': 8, 'body': '显式关闭'},
      'viewerCanComment': false,
    });
    final allowed = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{'id': 3, 'authorId': 8, 'body': '城市角落'},
      'viewerCanComment': true,
    });

    expect(missing.viewerCanComment, isTrue, reason: '缺席就藏输入框 = App 里评论不了');
    expect(closed.viewerCanComment, isFalse, reason: '后端显式关闭要认');
    expect(allowed.viewerCanComment, isTrue);
  });

  test('新版读模型保留业务关联并区分图片与地图快照', () {
    final post = SquarePost.fromJson(<String, dynamic>{
      'post': <String, dynamic>{'id': 3, 'authorId': 8, 'body': '跑完了'},
      'media': <Map<String, dynamic>>[
        <String, dynamic>{
          'media_type': 'MAP_SNAPSHOT',
          'derived_object_key': 'https://img.test/route.jpg',
        },
        <String, dynamic>{
          'media_type': 'IMAGE',
          'derived_object_key': 'https://img.test/photo.jpg',
        },
      ],
      'references': <Map<String, dynamic>>[
        <String, dynamic>{'reference_type': 'ACTIVITY', 'reference_id': 91},
      ],
    });

    expect(post.pics, <String>['https://img.test/photo.jpg']);
    expect(post.routePreviewImg, 'https://img.test/route.jpg');
    expect(post.sportName, '活动 #91');
  });

  test('评论续页发真实页码并保留回复树字段', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 11,
              'ownerId': 42,
              'memberId': 8,
              'contents': '回复你',
              'replyId': 7,
            },
          ],
          'total': 1,
        },
      },
    );
    client.dio.httpClientAdapter = adapter;

    final List<Comment> rows = await SquareApi(
      client,
    ).comments(42, page: 2, limit: 20);

    expect(adapter.sent.single.path, '/api/comment/list');
    expect(_formField(adapter.sent.single, 'owner_type'), '3');
    expect(_formField(adapter.sent.single, 'owner_id'), '42');
    expect(_formField(adapter.sent.single, 'pageNum'), '2');
    expect(_formField(adapter.sent.single, 'pageSize'), '20');
    // reply_id 是被回复的那条评论 —— 回复树靠它挂上去。
    expect(rows.single.parentId, 7);
  });

  test('消息中心可读取并以独立命令标记已读', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.method == 'GET') {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'id': 31, 'notification_type': 'COMMENT'},
            ],
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final SquareApi api = SquareApi(client);
    final rows = await api.notifications(cursor: 40);
    await api.readNotification(31);

    expect(rows.single['id'], 31);
    expect(adapter.sent[0].path, '/api/v1/community/notifications');
    expect(adapter.sent[0].queryParameters, containsPair('cursor', 40));
    expect(adapter.sent[1].path, '/api/v1/community/notifications/31/read');
    expect(adapter.sent[1].method, 'POST');
  });

  test('通知偏好可读取并按字段更新，治理通知不可由客户端关闭', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'interactionEnabled': true,
          'mentionEnabled': false,
          'socialEnabled': true,
          'governanceEnabled': true,
        },
      };
    });
    client.dio.httpClientAdapter = adapter;
    final api = SquareApi(client);

    final current = await api.notificationPreferences();
    final updated = await api.updateNotificationPreferences(
      mentionEnabled: false,
    );

    expect(current['governanceEnabled'], isTrue);
    expect(updated['mentionEnabled'], isFalse);
    expect(adapter.sent[0].method, 'GET');
    expect(adapter.sent[1].method, 'PATCH');
    expect(adapter.sent[1].data, <String, dynamic>{'mentionEnabled': false});
  });

  test('发布保留路线、俱乐部、社区可见性和地点名', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/guidelines/active')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'id': 5},
        };
      }
      if (options.path.endsWith('/posts')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 77,
              'authorId': 9,
              'body': '路线记录',
              'version': 0,
            },
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;
    final SquareApi api = SquareApi(client);
    final guideline = await api.activeGuideline();

    await api.publish(
      const SquareDraft(
        workflowId: 'workflow-route-club-1',
        contents: '路线记录',
        referenceType: 'ROUTE',
        referenceId: 66,
        communityId: 18,
        audience: 'COMMUNITY',
        address: '苏河湾',
        cityCode: '上海市',
      ),
      guidelineVersionId: (guideline['id'] as num).toInt(),
    );

    final create = adapter.sent[2].data as Map<String, dynamic>;
    expect(create['communityId'], 18);
    expect(create['audience'], 'COMMUNITY');
    expect(create['postType'], 'ROUTE_DISCOVERY');
    expect(create['poiName'], '苏河湾');
    expect(
      (create['references'] as List<dynamic>).single,
      equals(<String, dynamic>{
        'referenceType': 'ROUTE',
        'referenceId': 66,
        'snapshotJson': '{}',
        'privacySnapshot': 'PUBLIC_SAFE',
      }),
    );
  });

  test('编辑复用既有媒体并以版本号 PATCH，不重复登记媒体', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path.endsWith('/guidelines/ack')) {
        return <String, dynamic>{'code': 200};
      }
      if (options.method == 'PATCH') {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'post': <String, dynamic>{
              'id': 77,
              'authorId': 9,
              'body': '改过的城市记录',
              'version': 4,
              'lifecycle': 'CHECKING',
            },
          },
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;

    final post = await SquareApi(client).publish(
      const SquareDraft(
        workflowId: 'workflow-edit-post-77',
        id: 77,
        expectedVersion: 3,
        contents: '改过的城市记录',
        pics: <String>['https://img.test/existing.jpg'],
        existingMediaIds: <int>[31],
        existingPicCount: 1,
      ),
      guidelineVersionId: 5,
    );

    expect(post.lifecycle, 'CHECKING');
    expect(
      adapter.sent.where(
        (RequestOptions request) => request.path.endsWith('/media/register'),
      ),
      isEmpty,
    );
    final patch = adapter.sent.singleWhere(
      (RequestOptions request) => request.method == 'PATCH',
    );
    expect(patch.path, '/api/v1/community/posts/77');
    expect(
      patch.data as Map<String, dynamic>,
      containsPair('expectedVersion', 3),
    );
    expect(
      patch.data as Map<String, dynamic>,
      containsPair('mediaIds', <int>[31]),
    );
  });

  test('草稿、修订、关联选项与地点撤回都有真实接口', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter((RequestOptions options) {
      if (options.path == '/api/v1/community/drafts') {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'post': <String, dynamic>{
                  'id': 7,
                  'authorId': 9,
                  'body': '未发布记录',
                  'lifecycle': 'DRAFT',
                },
              },
            ],
            'nextCursor': 7,
          },
        };
      }
      if (options.path.endsWith('/revisions')) {
        return <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{'id': 2, 'post_id': 7},
          ],
        };
      }
      if (options.path.contains('/reference-options/')) {
        return <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{'id': 66, 'name': '苏河慢跑线'},
          ],
        };
      }
      return <String, dynamic>{'code': 200};
    });
    client.dio.httpClientAdapter = adapter;
    final SquareApi api = SquareApi(client);

    final drafts = await api.drafts(cursor: 99);
    final revisions = await api.revisions(7);
    final routes = await api.referenceOptions('ROUTE');
    final members = await api.referenceOptions('MEMBER');
    await api.withdrawLocation(7, version: 4);

    expect(drafts.items.single.lifecycle, 'DRAFT');
    expect(revisions.single['id'], 2);
    expect(routes.single['name'], '苏河慢跑线');
    expect(members.single['id'], 66);
    expect(adapter.sent[0].queryParameters['cursor'], 99);
    expect(adapter.sent[1].path, '/api/v1/community/posts/7/revisions');
    expect(adapter.sent[2].path, '/api/v1/community/reference-options/ROUTE');
    expect(adapter.sent[3].path, '/api/v1/community/reference-options/MEMBER');
    final withdraw = adapter.sent[4];
    expect(withdraw.path, '/api/v1/community/posts/7/location');
    expect(withdraw.method, 'DELETE');
    expect(
      withdraw.data as Map<String, dynamic>,
      containsPair('expectedVersion', 4),
    );
  });
}
