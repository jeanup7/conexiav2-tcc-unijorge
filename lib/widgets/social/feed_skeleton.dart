import '../design_system.dart';
import '../../theme/design_tokens.dart';

import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Layout placeholders only; no fictitious posts or image requests.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando publicações',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Skeletonizer.zone(
        effect: MediaQuery.disableAnimationsOf(context)
            ? const SolidColorEffect(color: ConexiaColors.line)
            : const ShimmerEffect(
                baseColor: ConexiaColors.line,
                highlightColor: ConexiaColors.canvas,
                duration: Duration(milliseconds: 1400),
              ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
          children: [
            const Bone(width: 180, height: 32),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(4, (_) => const Bone.circle(size: 64)),
            ),
            const SizedBox(height: 28),
            ...List.generate(
              2,
              (_) => SurfaceCard(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Bone.circle(size: 40),
                        SizedBox(width: 12),
                        Bone(width: 120, height: 16),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const AspectRatio(
                      aspectRatio: 1,
                      child: Bone(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Bone(width: 110, height: 18),
                    const SizedBox(height: 10),
                    const Bone(height: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
