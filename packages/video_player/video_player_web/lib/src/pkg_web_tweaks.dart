// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Adds a "controlsList" setter to [web.HTMLMediaElement]s.
///
/// `disablePictureInPicture` and `disableRemotePlayback` are now available
/// directly in `package:web`, but `controlsList` is not yet included.
extension NonStandardSettersOnMediaElement on web.HTMLMediaElement {
  external set controlsList(String? controlsList);
}

/// Interop for [MediaSessionActionDetails] which is not yet in `package:web`.
///
/// This is the details object passed to MediaSession action handlers.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaSessionActionDetails
extension type MediaSessionActionDetails._(JSObject _) implements JSObject {
  /// The media session action that was triggered (e.g. 'play', 'seekto').
  external String get action;

  /// The offset in seconds for seek actions (seekbackward/seekforward).
  external double? get seekOffset;

  /// The absolute time in seconds to seek to (for 'seekto' action).
  external double? get seekTime;

  /// Whether this is a rapid sequential seek (for 'seekto' action).
  external bool? get fastSeek;
}
