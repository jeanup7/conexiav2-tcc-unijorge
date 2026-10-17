import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../models/preview_content.dart';

class PreviewStore extends ChangeNotifier {
  final List<Publication> _posts = List.of(previewPublications);
  final List<Publication> _stories = previewPublications
      .map(
        (p) => Publication(
          id: 'story-${p.id}',
          userId: p.userId,
          author: p.author,
          text: p.text,
          likes: 0,
          liked: false,
          assetImage: p.assetImage,
          expires:
              DateTime.now()
                  .add(const Duration(hours: 24))
                  .millisecondsSinceEpoch /
              1000,
        ),
      )
      .toList();
  final Map<String, List<Map<String, dynamic>>> comments = {};
  List<Publication> get posts => List.unmodifiable(_posts);
  List<Publication> get stories => List.unmodifiable(_stories);
  List<Publication> forUser(String id) =>
      posts.where((p) => p.userId == id).toList();
  List<({String id, String name, PostPhoto? photo})> get profiles {
    final result = <String, ({String id, String name, PostPhoto? photo})>{};
    for (final p in posts) {
      result[p.userId] = (
        id: p.userId,
        name: p.author,
        photo: p.photos.firstOrNull,
      );
    }
    result.putIfAbsent(
      'preview-self',
      () => (id: 'preview-self', name: 'Você', photo: null),
    );
    return result.values.toList();
  }

  void add(Publication post, {bool story = false}) {
    (story ? _stories : _posts).insert(0, post);
    notifyListeners();
  }

  void like(String id) {
    final i = _posts.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = _posts[i];
    _posts[i] = p.copyWith(
      likes: p.likes + (p.liked ? -1 : 1),
      liked: !p.liked,
    );
    notifyListeners();
  }

  void delete(String id) {
    _posts.removeWhere((p) => p.id == id);
    comments.remove(id);
    notifyListeners();
  }

  void block(String user) {
    _posts.removeWhere((p) => p.userId == user);
    _stories.removeWhere((p) => p.userId == user);
    notifyListeners();
  }

  void comment(String id, String text) {
    comments.putIfAbsent(id, () => []).add({
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'name': 'Você • demonstração',
      'text': text,
    });
    notifyListeners();
  }
}
