import 'dart:async';

import 'package:flutter/material.dart';

/// Records display, not attention or reading. Never used in the local preview.
class PostExposure extends StatefulWidget {
  const PostExposure({
    super.key,
    required this.child,
    required this.onDisplayed,
  });
  final Widget child;
  final Future<void> Function() onDisplayed;
  @override
  State<PostExposure> createState() => _PostExposureState();
}

class _PostExposureState extends State<PostExposure> {
  Timer? timer;
  int ticks = 0, retry = 0;
  bool reported = false, sending = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) => check());
  }

  bool visible() {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        viewport is! RenderBox ||
        !viewport.hasSize) {
      return false;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final intersection = rect.intersect(bounds).intersect(screen);
    return intersection.width > 0 &&
        intersection.height > 0 &&
        intersection.width * intersection.height >=
            rect.width * rect.height * .5;
  }

  Future<void> check() async {
    if (reported || sending) return;
    if (retry > 0) {
      retry--;
      return;
    }
    if (!visible()) {
      ticks = 0;
      return;
    }
    if (++ticks < 9) return;
    sending = true;
    try {
      await widget.onDisplayed();
      reported = true;
      timer?.cancel();
    } catch (_) {
      ticks = 0;
      retry = 120;
    } finally {
      sending = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
