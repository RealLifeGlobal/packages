// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../video_player.dart';

/// A utility widget that monitors its position inside the enclosing [Scrollable]
/// and automatically detaches the platform-view rendering tree when scrolled
/// off-screen or when explicitly deactivated.
///
/// ### Why this is needed
/// On Android, when using `VideoViewType.platformView` (which backs the video
/// inside a native `SurfaceView`), the native surface composites in its own window
/// layer directly via Android's `SurfaceFlinger`. Standard Flutter widget clipping
/// and stacking contexts do not apply to this system-level layer, causing the
/// video to float over headers, AppBars, or other tabs in an [IndexedStack].
///
/// `VideoPlayerViewportGuard` solves this by replacing the platform view with a
/// static [placeholder] as soon as it leaves the active viewport or loses focus.
///
/// ### Deterministic State Transitions
/// When detaching:
/// * If [pauseOnDetach] is true and the video is currently playing, it automatically
///   pauses playback and remembers that it was playing.
///
/// When re-attaching:
/// * If it was playing before detachment and [isActive] is true, it synchronously
///   calls [VideoPlayerController.play] to resume rendering immediately.
///
/// ### Multi-Platform Behavior
/// By default, this widget only detaches the video from the widget tree on Android
/// when using platform-view rendering. On other platforms (iOS, macOS, web) or modes
/// (`textureView`), standard canvas clipping works perfectly, so the widget keeps
/// the [child] mounted to avoid layout thrashing, but still supports optional
/// auto-pausing/resuming via [pauseOnDetach]. Set [forceDetach] to true to force
/// detachment on all platforms.
class VideoPlayerViewportGuard extends StatefulWidget {
  /// Creates a new [VideoPlayerViewportGuard].
  const VideoPlayerViewportGuard({
    super.key,
    required this.controller,
    required this.child,
    this.isActive = true,
    this.predictiveBuffer = 0.0,
    this.pauseOnDetach = true,
    this.forceDetach = false,
    this.placeholder = const ColoredBox(color: Colors.black),
  });

  /// The [VideoPlayerController] being guarded.
  final VideoPlayerController controller;

  /// The actual [VideoPlayer] widget being wrapped.
  final Widget child;

  /// Whether the parent screen, tab, or stack page is currently active.
  ///
  /// If set to false (e.g., when the video belongs to a hidden tab inside
  /// an [IndexedStack]), the platform view is detached immediately.
  final bool isActive;

  /// Buffer in pixels to predictively detach the platform view before it scrolls off-screen.
  ///
  /// Defaults to `0.0` (exact viewport boundaries) to prevent visible placeholder
  /// pop-out artifacts while the video is still inside the viewport.
  final double predictiveBuffer;

  /// Whether to automatically pause the video upon detachment and resume on re-attachment.
  ///
  /// Set to false if background audio or Picture-in-Picture (PiP) is active so that
  /// playback is not cut off when the widget leaves the screen.
  final bool pauseOnDetach;

  /// If true, swaps the player for the placeholder on all platforms when scrolled off-screen.
  ///
  /// If false (default), only detaches on Android when using [VideoViewType.platformView],
  /// while on other platforms it keeps the player mounted and only performs auto-pausing.
  final bool forceDetach;

  /// The placeholder widget displayed in the tree while the video is detached.
  final Widget placeholder;

  @override
  State<VideoPlayerViewportGuard> createState() =>
      _VideoPlayerViewportGuardState();
}

class _VideoPlayerViewportGuardState extends State<VideoPlayerViewportGuard> {
  ScrollableState? _scrollable;

  /// Whether the widget's bounds currently overlap the scroll viewport.
  bool _onScreen = true;

  /// Whether the player is currently detached.
  bool _detached = false;

  /// Whether the video was actively playing before it was detached, so it
  /// can be resumed immediately upon re-attachment.
  bool _wasPlayingBeforeDetach = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the enclosing scrollable.
    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      if (_scrollable != null) {
        try {
          _scrollable!.position.removeListener(_evaluateVisibility);
        } catch (_) {}
      }
      _scrollable = scrollable;
      if (_scrollable != null) {
        try {
          _scrollable!.position.addListener(_evaluateVisibility);
        } catch (_) {}
      }
    }

    // Run visibility evaluation after the first layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluateVisibility();
      _updateDetachedState();
    });
  }

  @override
  void didUpdateWidget(covariant VideoPlayerViewportGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
    if (widget.isActive != oldWidget.isActive ||
        widget.predictiveBuffer != oldWidget.predictiveBuffer ||
        widget.forceDetach != oldWidget.forceDetach) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _evaluateVisibility();
        _updateDetachedState();
      });
    }
  }

  void _onControllerUpdate() {
    if (mounted) {
      // Re-evaluate state if the controller transitions to initialized.
      _updateDetachedState();
    }
  }

  void _evaluateVisibility() {
    if (!mounted || !widget.isActive) {
      return;
    }
    final RenderObject? guardObject = context.findRenderObject();
    final RenderObject? viewportObject = _scrollable?.context
        .findRenderObject();

    if (guardObject is! RenderBox ||
        viewportObject is! RenderBox ||
        !guardObject.attached ||
        !viewportObject.attached ||
        !guardObject.hasSize ||
        !viewportObject.hasSize) {
      return;
    }

    try {
      final Rect guardRect =
          guardObject.localToGlobal(Offset.zero) & guardObject.size;
      final Rect viewportRect =
          viewportObject.localToGlobal(Offset.zero) & viewportObject.size;

      // Adjust the active viewport boundary by the predictive buffer.
      final activeViewport = viewportRect.height > widget.predictiveBuffer * 2
          ? Rect.fromLTRB(
              viewportRect.left,
              viewportRect.top + widget.predictiveBuffer,
              viewportRect.right,
              viewportRect.bottom - widget.predictiveBuffer,
            )
          : viewportRect;

      final bool onScreen = guardRect.overlaps(activeViewport);
      if (onScreen != _onScreen) {
        _onScreen = onScreen;
        _updateDetachedState();
      }
    } catch (_) {
      // Gracefully catch any geometric transformations errors during teardown.
    }
  }

  void _updateDetachedState() {
    final bool isAndroidPlatformView =
        defaultTargetPlatform == TargetPlatform.android &&
        widget.controller.viewType == VideoViewType.platformView;

    final bool shouldDetach =
        ((!_onScreen && (isAndroidPlatformView || widget.forceDetach)) ||
            !widget.isActive) &&
        widget.controller.value.isInitialized;

    if (shouldDetach != _detached) {
      setState(() {
        _detached = shouldDetach;
      });
      _handleDetachedTransition(shouldDetach);
    }
  }

  void _handleDetachedTransition(bool detached) {
    if (detached) {
      // Transitioning from attached to detached: pause if currently playing.
      if (widget.pauseOnDetach && widget.controller.value.isPlaying) {
        _wasPlayingBeforeDetach = true;
        unawaited(widget.controller.pause());
      } else {
        _wasPlayingBeforeDetach = false;
      }
    } else {
      // Transitioning from detached to attached: resume synchronously and immediately.
      if (_wasPlayingBeforeDetach) {
        _wasPlayingBeforeDetach = false;
        if (widget.isActive) {
          unawaited(widget.controller.play());
        }
      }
    }
  }

  @override
  void dispose() {
    if (_scrollable != null) {
      try {
        _scrollable!.position.removeListener(_evaluateVisibility);
      } catch (_) {}
    }
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _detached ? widget.placeholder : widget.child;
  }
}
