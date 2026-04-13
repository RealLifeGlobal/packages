// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

/// Best-practice example for iterating through video decoders on failure.
///
/// This is NOT part of the plugin — it lives in the example app to show how
/// apps should handle decoder fallback on problematic devices.
///
/// Strategy:
///   1. Query available decoders for the current video's MIME type.
///   2. Order: HW decoders first, then SW decoders.
///   3. Try each decoder, actively monitoring for errors (including runtime
///      MediaCodec crashes that happen during frame decoding, not just init).
///   4. Return the working decoder name (or null if all failed).
///
/// The app can persist the working decoder name (e.g. SharedPreferences)
/// and pass it to `controller.setVideoDecoder(savedName)` on next launch.
library;

import 'dart:async';

import 'package:video_player/video_player.dart';

class DecoderRetrier {
  DecoderRetrier(
    this.controller, {
    this.onAttempt,
    this.onSuccess,
    this.onExhausted,
    this.settleDelay = const Duration(seconds: 3),
  });

  final VideoPlayerController controller;

  /// Called before each decoder attempt.
  final void Function(VideoDecoderInfo decoder, int attempt)? onAttempt;

  /// Called when a working decoder is found.
  final void Function(VideoDecoderInfo decoder)? onSuccess;

  /// Called when all decoders have been exhausted without success.
  final void Function()? onExhausted;

  /// How long to wait after switching to confirm no runtime decoder crash.
  ///
  /// Runtime MediaCodec errors (e.g. Huawei HiSilicon OMX.hisi crashes)
  /// can occur several hundred milliseconds after init succeeds, so this
  /// should be long enough to catch those. 3 seconds is a good default.
  final Duration settleDelay;

  /// Tries each available decoder in priority order (HW first, then SW).
  ///
  /// Returns the name of the working decoder, or null if all failed.
  Future<String?> retryWithFallback() async {
    final List<VideoDecoderInfo> decoders =
        await controller.getAvailableDecoders();
    if (decoders.isEmpty) {
      onExhausted?.call();
      return null;
    }

    // Priority: HW decoders first, then SW decoders.
    final ordered = <VideoDecoderInfo>[
      ...decoders.where((VideoDecoderInfo d) => d.isHardwareAccelerated),
      ...decoders.where((VideoDecoderInfo d) => d.isSoftwareOnly),
    ];

    for (var i = 0; i < ordered.length; i++) {
      final VideoDecoderInfo decoder = ordered[i];
      onAttempt?.call(decoder, i + 1);

      try {
        await controller.setVideoDecoder(decoder.name);

        // Actively listen for errors during the settle period.
        // Runtime MediaCodec crashes (the Huawei/HiSilicon bug) happen
        // after init succeeds, during actual frame decoding — so a simple
        // hasError check after a delay is not enough. We need to watch
        // for errors that arrive asynchronously.
        final bool stable = await _waitForStability();
        if (!stable) {
          continue;
        }

        onSuccess?.call(decoder);
        return decoder.name;
      } catch (_) {
        // setVideoDecoder itself threw — try next decoder.
        continue;
      }
    }

    onExhausted?.call();
    return null;
  }

  /// Waits [settleDelay] while monitoring for errors.
  ///
  /// Returns true if the player remained error-free, false if an error
  /// was detected (including runtime MediaCodec errors).
  Future<bool> _waitForStability() async {
    // If already in error state (e.g. init-time failure), fail immediately.
    if (controller.value.hasError) {
      return false;
    }

    final completer = Completer<bool>();

    // Listen for value changes that indicate an error.
    void listener() {
      if (controller.value.hasError && !completer.isCompleted) {
        completer.complete(false);
      }
    }

    controller.addListener(listener);

    // If no error arrives within settleDelay, consider it stable.
    final timeout = Timer(settleDelay, () {
      if (!completer.isCompleted) {
        completer.complete(!controller.value.hasError);
      }
    });

    try {
      return await completer.future;
    } finally {
      controller.removeListener(listener);
      timeout.cancel();
    }
  }
}
