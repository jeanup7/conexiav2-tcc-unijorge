import '../design_system.dart';
import '../../theme/design_tokens.dart';
import 'profile_avatar.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    super.key,
    required this.label,
    required this.onTap,
    this.image,
    this.size = 68,
    this.add = false,
    this.ring = true,
  });
  final String label;
  final VoidCallback onTap;
  final ImageProvider? image;
  final double size;
  final bool add, ring;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: add ? 'Criar seu story' : 'Ver story de $label',
    child: PressFeedback(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    padding: EdgeInsets.all(ring ? 3 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ring
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                ConexiaColors.brand,
                                Color(0xFF8789D8),
                                Color(0xFF58B49A),
                              ],
                            )
                          : null,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: ProfileAvatar(
                        image: image,
                        radius: (size - (ring ? 12 : 6)) / 2,
                        label: 'Foto de $label',
                      ),
                    ),
                  ),
                  if (add)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ConexiaColors.brand,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: size + 5,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF353842),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
