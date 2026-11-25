import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../models/models.dart';
import 'post_gallery.dart';

/// Horizontal editorial tickets: no circular story ring.
class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    super.key,
    required this.label,
    required this.onTap,
    this.image,
    this.photo,
    this.size = 68,
    this.add = false,
    this.ring = true,
  });
  final String label;
  final VoidCallback onTap;
  final ImageProvider? image;
  final PostPhoto? photo;
  final double size;
  final bool add, ring;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: add ? 'Criar seu recorte' : 'Ver recorte de $label',
    child: Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 4),
      child: SizedBox(
        width: 170,
        child: Material(
          color: add ? ConexiaColors.ink : ConexiaColors.lavender,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(28),
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  PostPhotoView(photo: photo!)
                else if (image != null)
                  Image(image: image!, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33132123), Color(0xED132123)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        add ? '+ CRIAR' : 'RECORTE / 24H',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD9F279),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
