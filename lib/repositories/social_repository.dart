import '../core/api_client.dart';
import '../models/models.dart';

import 'package:flutter/foundation.dart';

class SocialRepository {
  SocialRepository(this.api);
  final ApiClient api;
  final revision = ValueNotifier<int>(0);
  final postChange = ValueNotifier<Publication?>(null);
  void invalidate() => revision.value++;
  void dispose() {
    revision.dispose();
    postChange.dispose();
  }

  Future<({List<Publication> items, String? cursor})> feed({
    bool stories = false,
    String? cursor,
    String? authorId,
  }) async {
    final query = Uri(queryParameters: {'cursor': ?cursor, 'user': ?authorId})
        .query;
    final value = await api.request(
      'GET',
      '${stories ? '/stories' : '/posts'}${query.isEmpty ? '' : '?$query'}',
    );
    return (
      items: (value['items'] as List)
          .map((p) => Publication.fromJson(p as Map<String, dynamic>))
          .toList(),
      cursor: value['nextCursor']?.toString(),
    );
  }

  Future<List<Map<String, dynamic>>> list(String path) async =>
      ((await api.request('GET', path))['items'] as List)
          .cast<Map<String, dynamic>>();
}
