import 'dart:convert';

import 'package:flutter/material.dart';

import '../common.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    this.media,
    this.image,
    this.radius = 20,
    this.label,
  });
  final String? media, label;
  final ImageProvider? image;
  final double radius;
  @override
  State<ProfileAvatar> createState() => _AvatarState();
}

class _AvatarState extends State<ProfileAvatar> {
  Future<Map<String, dynamic>>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.media != null) {
      future ??= AppScope.of(context).api
          .request('GET', '/media/${widget.media}');
    }
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.media != widget.media) {
      future = widget.media == null
          ? null
          : AppScope.of(context).api.request('GET', '/media/${widget.media}');
    }
  }

  Widget avatar(ImageProvider? image) => Semantics(
    image: true,
    label: widget.label ?? 'Foto de perfil',
    child: ClipOval(
      child: SizedBox.square(
        dimension: widget.radius * 2,
        child: ColoredBox(
          color: const Color(0xFFEBEDFC),
          child: image == null
              ? Icon(Icons.person_outline, size: widget.radius)
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.person_outline, size: widget.radius),
                ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => future == null
      ? avatar(widget.image)
      : FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (_, s) {
            ImageProvider? image;
            if (s.connectionState == ConnectionState.done && s.hasData) {
              try {
                image = MemoryImage(base64Decode(s.data!['data'] as String));
              } catch (_) {
                image = null;
              }
            }
            return avatar(image);
          },
        );
}
