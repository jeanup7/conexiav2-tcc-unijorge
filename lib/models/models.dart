import 'dart:typed_data';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.email,
    required this.bio,
    required this.verified,
    required this.approved,
    required this.needsGuardian,
    required this.private,
    required this.messages,
    this.avatar,
    this.needsNickname = false,
    this.isAdmin = false,
    this.accountStatus = 'active',
  });
  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    bio: json['bio'] as String? ?? '',
    verified: json['verified'] == 1,
    approved: json['approved'] == 1,
    needsGuardian: json['needsGuardian'] == true,
    private: json['private'] == 1,
    messages: json['messages'] == 1,
    avatar: json['avatar'] as String?,
    needsNickname: json['needsNickname'] == true,
    isAdmin: json['isAdmin'] == true,
    accountStatus: json['accountStatus'] as String? ?? 'active',
  );
  final String id, name, email, bio;
  final String? avatar;
  final bool needsNickname;
  final bool isAdmin;
  final String accountStatus;
  final bool verified, approved, needsGuardian, private, messages;
  bool get active =>
      accountStatus == 'active' &&
      verified &&
      (!needsGuardian || approved) &&
      !needsNickname;
}

class Publication {
  const Publication({
    required this.id,
    required this.userId,
    required this.author,
    required this.text,
    required this.likes,
    required this.liked,
    this.media,
    this.authorAvatar,
    this.category = 'other',
    this.expires,
    this.assetImage,
    this.assetImages = const [],
    this.mediaItems = const [],
    this.localImages = const [],
  });
  factory Publication.fromJson(Map<String, dynamic> json) => Publication(
    id: json['id'] as String,
    userId: json['user'] as String,
    author: (json['author'] as Map)['name'] as String,
    authorAvatar: (json['author'] as Map)['avatar'] as String?,
    category: json['category'] as String? ?? 'other',
    text: json['text'] as String,
    likes: json['likes'] as int,
    liked: json['liked'] as bool,
    media: json['media'] as String?,
    expires: (json['expires'] as num?)?.toDouble(),
    mediaItems: (json['mediaItems'] as List?)?.cast<String>() ?? const [],
  );
  final String id, userId, author, text;
  final String category;
  final int likes;
  final bool liked;
  final String? media;
  final String? authorAvatar;
  final String? assetImage;
  final double? expires;
  final List<String> assetImages, mediaItems;
  final List<Uint8List> localImages;
  List<PostPhoto> get photos => [
    ...((assetImages.isNotEmpty ? assetImages : [?assetImage]).map(
      PostPhoto.asset,
    )),
    ...localImages.map(PostPhoto.memory),
    ...((mediaItems.isNotEmpty ? mediaItems : [?media]).map(PostPhoto.remote)),
  ];
  Publication copyWith({String? text, int? likes, bool? liked}) => Publication(
    id: id,
    userId: userId,
    author: author,
    text: text ?? this.text,
    likes: likes ?? this.likes,
    liked: liked ?? this.liked,
    media: media,
    authorAvatar: authorAvatar,
    category: category,
    expires: expires,
    assetImage: assetImage,
    assetImages: assetImages,
    mediaItems: mediaItems,
    localImages: localImages,
  );
}

class PostPhoto {
  const PostPhoto.asset(String value)
    : endpoint = null,
      asset = value,
      media = null,
      bytes = null;
  const PostPhoto.remote(String value, {this.endpoint})
    : media = value,
      asset = null,
      bytes = null;
  const PostPhoto.memory(Uint8List value)
    : endpoint = null,
      bytes = value,
      asset = null,
      media = null;
  final String? asset, media, endpoint;
  final Uint8List? bytes;
}
