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
            ? SolidColorEffect(color: ConexiaPalette.of(context).line)
            : ShimmerEffect(
                baseColor: ConexiaPalette.of(context).line,
                highlightColor: ConexiaPalette.of(context).background,
                duration: Duration(milliseconds: 1400),
              ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 20),
          children: [
            Bone(width: 180, height: 32),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                2,
                (_) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Bone(height: 100),
                  ),
                ),
              ),
            ),
            SizedBox(height: 28),
            ...List.generate(
              2,
              (_) => SurfaceCard(
                margin: EdgeInsets.only(bottom: 24),
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Bone.circle(size: 40),
                        SizedBox(width: 12),
                        Bone(width: 120, height: 16),
                      ],
                    ),
                    SizedBox(height: 16),
                    AspectRatio(
                      aspectRatio: 1.6,
                      child: Bone(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                    SizedBox(height: 14),
                    Bone(width: 110, height: 18),
                    SizedBox(height: 10),
                    Bone(height: 14),
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
