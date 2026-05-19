// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

/// A demo that stresses platform-view video rendering in the two ways that are
/// most likely to surface bugs on Android:
///
///  1. Scrolling a *playing* video completely off-screen (and back) inside a
///     long, non-lazy [ListView]. The [VideoPlayerController] stays alive the
///     whole time — only the platform view leaves the viewport.
///  2. Switching between tabs backed by an [IndexedStack], so every feed (and
///     every video) is kept alive in the widget tree even while not visible.
///     Feed A and Feed B have videos; the third tab has none, to exercise the
///     "go to a tab with no videos and come back" path.
///
/// The "Detach off-screen" toggle is an app-level workaround for the Android
/// `SurfaceView` clipping bug: when on, each card removes its [VideoPlayer]
/// widget (and therefore the underlying platform view) as soon as it scrolls
/// out of the viewport, and re-inserts it when it scrolls back in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Push this page with a [MaterialPageRoute] to open the demo.
class PlatformViewScrollDemo extends StatefulWidget {
  const PlatformViewScrollDemo({super.key});

  @override
  State<PlatformViewScrollDemo> createState() => _PlatformViewScrollDemoState();
}

class _PlatformViewScrollDemoState extends State<PlatformViewScrollDemo> {
  int _tabIndex = 0;
  bool _detachOffScreen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform view: scroll & tabs')),
      body: Column(
        children: <Widget>[
          SwitchListTile(
            key: const ValueKey<String>('detach_off_screen_toggle'),
            secondary: const Icon(Icons.flip_to_back),
            title: const Text('Detach platform view when off-screen'),
            subtitle: const Text(
              'Removes the AndroidView once a card leaves the viewport, '
              'and re-inserts it when it scrolls back.',
            ),
            value: _detachOffScreen,
            onChanged: (bool value) => setState(() => _detachOffScreen = value),
          ),
          const Divider(height: 1),
          // IndexedStack keeps every feed mounted, so the videos in the
          // non-visible tabs keep their controllers and platform views alive.
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: <Widget>[
                _VideoFeed(
                  key: const ValueKey<String>('feed-a'),
                  label: 'Feed A',
                  videoCount: 3,
                  detachOffScreen: _detachOffScreen,
                  isActive: _tabIndex == 0,
                ),
                _VideoFeed(
                  key: const ValueKey<String>('feed-b'),
                  label: 'Feed B',
                  videoCount: 3,
                  detachOffScreen: _detachOffScreen,
                  isActive: _tabIndex == 1,
                ),
                _VideoFeed(
                  key: const ValueKey<String>('feed-empty'),
                  label: 'No videos',
                  videoCount: 0,
                  detachOffScreen: _detachOffScreen,
                  isActive: _tabIndex == 2,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (int index) => setState(() => _tabIndex = index),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed),
            label: 'Feed A',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library),
            label: 'Feed B',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.crop_din),
            label: 'No videos',
          ),
        ],
      ),
    );
  }
}

/// A long scrollable feed with [videoCount] platform-view videos spread out
/// between blocks of filler cards, so each video can be scrolled fully past
/// both edges of the viewport.
class _VideoFeed extends StatelessWidget {
  const _VideoFeed({
    super.key,
    required this.label,
    required this.videoCount,
    required this.detachOffScreen,
    required this.isActive,
  });

  final String label;
  final int videoCount;
  final bool detachOffScreen;
  final bool isActive;

  /// Total filler cards spread across the feed, sized so videos can be
  /// scrolled fully off-screen even on a tall display.
  static const int _fillerCount = 30;

  /// Sources cycled through for the embedded videos. A remote stream and a
  /// bundled asset, so both code paths are exercised.
  static const List<_VideoSource> _sources = <_VideoSource>[
    _VideoSource.network(
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    ),
    _VideoSource.asset('assets/Butterfly-209.mp4'),
  ];

  @override
  Widget build(BuildContext context) {
    final int blocks = videoCount + 1;
    final int fillerPerBlock = (_fillerCount / blocks).ceil();

    final children = <Widget>[
      _HeaderCard(label: label, hasVideos: videoCount > 0),
    ];
    var fillerIndex = 0;
    for (var block = 0; block < blocks; block++) {
      for (var i = 0; i < fillerPerBlock; i++) {
        fillerIndex++;
        children.add(_FillerCard(title: '$label · filler $fillerIndex'));
      }
      if (block < videoCount) {
        children.add(
          _PlatformVideoCard(
            // A stable key keeps each video's State (and controller) attached
            // to the same element across rebuilds and scroll passes.
            key: ValueKey<String>('$label-video-$block'),
            title: '$label · video ${block + 1}',
            source: _sources[block % _sources.length],
            detachOffScreen: detachOffScreen,
            isActive: isActive,
          ),
        );
      }
    }

    // A plain ListView (not ListView.builder) builds every child up front and
    // never disposes them, so off-screen videos keep playing — exactly the
    // case where the platform view detaches from the viewport.
    return ListView(
      key: PageStorageKey<String>('feed-scroll-$label'),
      padding: const EdgeInsets.all(8),
      children: children,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.label, required this.hasVideos});

  final String label;
  final bool hasVideos;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              hasVideos
                  ? 'Scroll so the videos leave the viewport, then scroll '
                        'back. Switch tabs while videos are off-screen too.'
                  : 'No videos here. Use the tab bar to jump here and back '
                        'to a feed that has videos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A filler list item used to pad the feed so videos can be scrolled away.
class _FillerCard extends StatelessWidget {
  const _FillerCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(title),
        subtitle: const Text('Scroll past me to push videos off-screen.'),
      ),
    );
  }
}

/// A single video rendered with [VideoViewType.platformView].
///
/// When [detachOffScreen] is true the card tracks its own position relative to
/// the enclosing scroll viewport and stops building the [VideoPlayer] widget
/// while it is fully out of view, so the underlying platform view is removed
/// from the tree instead of floating over the list.
class _PlatformVideoCard extends StatefulWidget {
  const _PlatformVideoCard({
    super.key,
    required this.title,
    required this.source,
    required this.detachOffScreen,
    required this.isActive,
  });

  final String title;
  final _VideoSource source;
  final bool detachOffScreen;
  final bool isActive;

  @override
  State<_PlatformVideoCard> createState() => _PlatformVideoCardState();
}

class _PlatformVideoCardState extends State<_PlatformVideoCard> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = widget.source.createController();
    _controller
      ..addListener(_onUpdate)
      ..setLooping(true);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
      await _controller.play();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerValue value = _controller.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.movie),
              title: Text(widget.title),
              subtitle: Text(
                'viewType: platformView · '
                '${value.isInitialized ? 'initialized' : 'loading…'}',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (value.isInitialized)
              AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayerViewportGuard(
                  controller: _controller,
                  isActive: widget.isActive,
                  forceDetach: widget.detachOffScreen,
                  placeholder: const _DetachedPlaceholder(),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      VideoPlayer(_controller),
                      VideoProgressIndicator(_controller, allowScrubbing: true),
                    ],
                  ),
                ),
              )
            else
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black12,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: value.isInitialized
                      ? () {
                          value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        }
                      : null,
                ),
                Text(value.isPlaying ? 'Playing' : 'Paused'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the [VideoPlayer] while a card is detached off-screen.
class _DetachedPlaceholder extends StatelessWidget {
  const _DetachedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.flip_to_back, color: Colors.white70, size: 32),
            SizedBox(height: 8),
            Text(
              'Platform view detached\n(off-screen)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// Describes where a video comes from and builds a platform-view controller
/// for it.
class _VideoSource {
  const _VideoSource.asset(this.asset) : url = null;
  const _VideoSource.network(this.url) : asset = null;

  final String? asset;
  final String? url;

  VideoPlayerController createController() {
    final String? assetPath = asset;
    if (assetPath != null) {
      return VideoPlayerController.asset(
        assetPath,
        viewType: VideoViewType.platformView,
      );
    }
    return VideoPlayerController.networkUrl(
      Uri.parse(url!),
      viewType: VideoViewType.platformView,
    );
  }
}
