import 'package:flutter/material.dart';

class StoryAvatar extends StatelessWidget {
  const StoryAvatar({super.key, required this.label, required this.onTap,
    this.image, this.size = 68, this.add = false, this.ring = true});
  final String label;
  final VoidCallback onTap;
  final ImageProvider? image;
  final double size;
  final bool add, ring;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: add ? 'Criar seu story' : 'Ver story de $label',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: size, height: size,
              padding: EdgeInsets.all(ring ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ring ? const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF6265ED), Color(0xFF8B61D9), Color(0xFF37C7B3)],
                ) : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFFEBEDFC),
                  backgroundImage: image,
                  child: image == null ? Text(label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5557BB))) : null,
                ),
              ),
            ),
            if (add) Positioned(right: 0, bottom: 0, child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF5658D9), border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.add, size: 17, color: Colors.white),
            )),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: size + 5, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF353842)))),
        ]),
      ),
    ),
  );
}
