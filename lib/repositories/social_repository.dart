import '../core/api_client.dart';
import '../models/models.dart';

class SocialRepository {
  SocialRepository(this.api);
  final ApiClient api;
  Future<({List<Publication> items, double? cursor})> feed({bool stories = false, double? cursor}) async {
    final value = await api.request('GET', '${stories ? '/stories' : '/posts'}${cursor == null ? '' : '?cursor=$cursor'}');
    return (items: (value['items'] as List).map((p) => Publication.fromJson(p as Map<String, dynamic>)).toList(), cursor: (value['nextCursor'] as num?)?.toDouble());
  }
  Future<List<Map<String, dynamic>>> list(String path) async =>
      ((await api.request('GET', path))['items'] as List).cast<Map<String, dynamic>>();
}
