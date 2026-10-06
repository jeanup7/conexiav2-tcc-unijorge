class Account {
  const Account({required this.id, required this.name, required this.email, required this.bio, required this.verified, required this.approved, required this.needsGuardian, required this.private, required this.messages});
  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String, name: json['name'] as String,
    email: json['email'] as String, bio: json['bio'] as String? ?? '',
    verified: json['verified'] == 1, approved: json['approved'] == 1,
    needsGuardian: json['needsGuardian'] == true,
    private: json['private'] == 1, messages: json['messages'] == 1);
  final String id, name, email, bio;
  final bool verified, approved, needsGuardian, private, messages;
  bool get active => verified && (!needsGuardian || approved);
}

class Publication {
  const Publication({required this.id, required this.userId, required this.author, required this.text, required this.likes, required this.liked, this.media, this.expires, this.assetImage});
  factory Publication.fromJson(Map<String, dynamic> json) => Publication(
    id: json['id'] as String, userId: json['user'] as String,
    author: (json['author'] as Map)['name'] as String,
    text: json['text'] as String, likes: json['likes'] as int,
    liked: json['liked'] as bool, media: json['media'] as String?,
    expires: (json['expires'] as num?)?.toDouble());
  final String id, userId, author, text;
  final int likes;
  final bool liked;
  final String? media;
  final String? assetImage;
  final double? expires;
}
