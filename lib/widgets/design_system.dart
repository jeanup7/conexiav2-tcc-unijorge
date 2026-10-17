import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/design_tokens.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 28 : 36,
        height: compact ? 28 : 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ConexiaColors.brand, Color(0xFF7779E7)],
          ),
          borderRadius: BorderRadius.circular(compact ? 9 : 12),
        ),
        child: Icon(
          Icons.shield_rounded,
          color: Colors.white,
          size: compact ? 18 : 23,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'conexia',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: compact ? 24 : 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
      ),
    ],
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.gradient,
  });
  final Widget child;
  final EdgeInsetsGeometry padding, margin;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: ConexiaColors.shadow,
    ),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: ConexiaColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: gradient),
        padding: padding,
        child: child,
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon = Icons.shield_outlined,
    this.positive = false,
  });
  final String label;
  final IconData icon;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: positive ? ConexiaColors.mint : ConexiaColors.lavender,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: positive ? ConexiaColors.green : ConexiaColors.brand,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: positive ? ConexiaColors.green : ConexiaColors.brand,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pointer feedback decorates the real Material control and keeps its semantics.
class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child});
  final Widget child;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool pressed = false;
  void update(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => update(true),
    onPointerUp: (_) => update(false),
    onPointerCancel: (_) => update(false),
    child: AnimatedScale(
      scale: pressed && !MediaQuery.disableAnimationsOf(context) ? .97 : 1,
      duration: ConexiaMotion.duration(context, 120),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => PressFeedback(
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: AnimatedSwitcher(
        duration: ConexiaMotion.duration(context, 160),
        child: busy
            ? Row(
                key: const ValueKey('busy'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: MediaQuery.disableAnimationsOf(context)
                          ? .72
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label),
                ],
              )
            : Row(
                key: const ValueKey('ready'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                  if (icon != null) ...[
                    const SizedBox(width: 10),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    ),
  );
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.message, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFEEF1) : ConexiaColors.lavender,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 19,
            color: error ? ConexiaColors.danger : ConexiaColors.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: error ? ConexiaColors.danger : ConexiaColors.ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.label = 'Carregando conteúdo'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Skeletonizer.zone(
        effect: MediaQuery.disableAnimationsOf(context)
            ? const SolidColorEffect(color: ConexiaColors.line)
            : const ShimmerEffect(
                baseColor: ConexiaColors.line,
                highlightColor: Colors.white,
                duration: Duration(milliseconds: 1500),
              ),
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, _) => const SurfaceCard(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                Bone.circle(size: 44),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: 128, height: 14),
                      SizedBox(height: 10),
                      Bone(height: 10),
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

class PageReveal extends StatelessWidget {
  const PageReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: ConexiaMotion.duration(context, 320),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - value)),
        child: child,
      ),
    ),
  );
}

class MediaSkeleton extends StatelessWidget {
  const MediaSkeleton({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando imagem',
    child: ExcludeSemantics(
      child: Skeletonizer.zone(
        effect: MediaQuery.disableAnimationsOf(context)
            ? const SolidColorEffect(color: ConexiaColors.line)
            : const ShimmerEffect(
                baseColor: ConexiaColors.line,
                highlightColor: ConexiaColors.canvas,
                duration: Duration(milliseconds: 1500),
              ),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: const Bone(),
        ),
      ),
    ),
  );
}
