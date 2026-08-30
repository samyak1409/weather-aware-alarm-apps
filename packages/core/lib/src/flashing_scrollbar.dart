import 'dart:async';

import 'package:flutter/material.dart';

/// A scrollbar that flashes visible for ~1s when its page opens — but only
/// when the content actually overflows — as a "there's more below" cue, then
/// fades back to the modern hidden-until-scrolled default.
///
/// Born on Arunoday's location list (user decision 2026-07-12); when the
/// settings pages became whole-page scrolls (2026-07-20, both apps) the cue
/// moved here so they share it. [builder] must hand the given controller to
/// its scrollable, so the bar and the content agree.
class FlashingScrollbar extends StatefulWidget {
  const FlashingScrollbar({super.key, required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<FlashingScrollbar> createState() => _FlashingScrollbarState();
}

class _FlashingScrollbarState extends State<FlashingScrollbar> {
  final _controller = ScrollController();
  bool _flash = false;

  /// The flash's own timer, **held so `dispose` can cancel it** (2026-08-25).
  ///
  /// It was a bare `Future.delayed`, which cannot be cancelled: the `mounted`
  /// guard stopped the `setState` but the callback stayed pending for its full
  /// 1.1s after the widget was gone. Harmless in the app; in a widget test it
  /// trips `A Timer is still pending even after the widget tree was disposed`,
  /// so every test that unmounts a scrolling page had to know to wait the
  /// flash out first. One `cancel` here instead of that knowledge spread
  /// across four test files.
  Timer? _off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFlash());
  }

  void _maybeFlash() {
    if (!mounted ||
        !_controller.hasClients ||
        _controller.position.maxScrollExtent <= 0) {
      return;
    }
    setState(() => _flash = true);
    _off = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  void dispose() {
    _off?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: _flash ? true : null,
      child: widget.builder(_controller),
    );
  }
}
