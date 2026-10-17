import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../screens/social/private_image.dart';

class PostPhotoView extends StatelessWidget {
  const PostPhotoView({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
  });
  final PostPhoto photo;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        const Center(child: Icon(Icons.broken_image_outlined));
    if (photo.asset != null) {
      return Image.asset(
        photo.asset!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: fallback,
      );
    }
    if (photo.bytes != null) {
      return Image.memory(
        photo.bytes!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: fallback,
      );
    }
    return LayoutBuilder(
      builder: (_, size) => PrivateImage(
        key: ValueKey(photo.media),
        media: photo.media!,
        endpoint: photo.endpoint,
        fit: fit,
        height: size.maxHeight,
      ),
    );
  }
}

class PostGallery extends StatefulWidget {
  const PostGallery({
    super.key,
    required this.photos,
    required this.onDoubleTap,
  });
  final List<PostPhoto> photos;
  final VoidCallback onDoubleTap;
  @override
  State<PostGallery> createState() => _PostGalleryState();
}

class _PostGalleryState extends State<PostGallery> {
  final controller = PageController();
  int selected = 0;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PostGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = widget.photos.isEmpty ? 0 : widget.photos.length - 1;
    if (selected > last) {
      selected = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpToPage(selected);
      });
    }
  }

  void move(int page) {
    if (!controller.hasClients || page < 0 || page >= widget.photos.length) {
      return;
    }
    controller.animateToPage(
      page,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                key: const ValueKey('post-gallery'),
                controller: controller,
                itemCount: widget.photos.length,
                onPageChanged: (i) => setState(() => selected = i),
                itemBuilder: (_, i) => Semantics(
                  label: 'Foto ${i + 1} de ${widget.photos.length}',
                  image: true,
                  child: GestureDetector(
                    onDoubleTap: widget.onDoubleTap,
                    child: PostPhotoView(photo: widget.photos[i]),
                  ),
                ),
              ),
            ),
            if (widget.photos.length > 1) ...[
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${selected + 1}/${widget.photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              if (selected > 0)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      tooltip: 'Foto anterior',
                      onPressed: () => move(selected - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
              if (selected < widget.photos.length - 1)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      tooltip: 'Próxima foto',
                      onPressed: () => move(selected + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      if (widget.photos.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.photos.length,
              (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == selected ? 7 : 5,
                height: i == selected ? 7 : 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == selected
                      ? const Color(0xFF6265ED)
                      : const Color(0xFFD5D7E3),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
