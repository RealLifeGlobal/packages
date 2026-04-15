// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

/// An example of using the plugin, controlling lifecycle and playback of the
/// video.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'audio_tracks_demo.dart';
import 'decoder_demo.dart';

void main() {
  runApp(MaterialApp(home: _App()));
}

class _App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        key: const ValueKey<String>('home_page'),
        appBar: AppBar(
          title: const Text('Video player example'),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('push_tab'),
              icon: const Icon(Icons.navigation),
              onPressed: () {
                Navigator.push<_PlayerVideoAndPopPage>(
                  context,
                  MaterialPageRoute<_PlayerVideoAndPopPage>(
                    builder: (BuildContext context) => _PlayerVideoAndPopPage(),
                  ),
                );
              },
            ),
            IconButton(
              key: const ValueKey<String>('audio_tracks_demo'),
              icon: const Icon(Icons.audiotrack),
              tooltip: 'Audio Tracks Demo',
              onPressed: () {
                Navigator.push<AudioTracksDemo>(
                  context,
                  MaterialPageRoute<AudioTracksDemo>(
                    builder: (BuildContext context) => const AudioTracksDemo(),
                  ),
                );
              },
            ),
            IconButton(
              key: const ValueKey<String>('pip_bg_demo'),
              icon: const Icon(Icons.picture_in_picture),
              tooltip: 'PiP & Background Demo',
              onPressed: () {
                Navigator.push<_PipBackgroundDemo>(
                  context,
                  MaterialPageRoute<_PipBackgroundDemo>(
                    builder: (BuildContext context) =>
                        const _PipBackgroundDemo(),
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.cloud), text: 'Remote'),
              Tab(icon: Icon(Icons.insert_drive_file), text: 'Asset'),
              Tab(icon: Icon(Icons.list), text: 'List example'),
              Tab(icon: Icon(Icons.hd), text: 'HLS / ABR'),
              Tab(icon: Icon(Icons.memory), text: 'Decoders'),
              Tab(icon: Icon(Icons.headphones), text: 'Audio'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  _BumbleBeeRemoteVideo(viewType),
            ),
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  _ButterFlyAssetVideo(viewType),
            ),
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  _ButterFlyAssetVideoInList(viewType),
            ),
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  _HlsAbrDemo(viewType),
            ),
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  DecoderDemo(viewType),
            ),
            _ViewTypeTabBar(
              builder: (VideoViewType viewType) =>
                  _AudioOnlyRemote(viewType),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewTypeTabBar extends StatefulWidget {
  const _ViewTypeTabBar({required this.builder});

  final Widget Function(VideoViewType) builder;

  @override
  State<_ViewTypeTabBar> createState() => _ViewTypeTabBarState();
}

class _ViewTypeTabBarState extends State<_ViewTypeTabBar>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const <Widget>[
            Tab(icon: Icon(Icons.texture), text: 'Texture view'),
            Tab(icon: Icon(Icons.construction), text: 'Platform view'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              widget.builder(VideoViewType.textureView),
              widget.builder(VideoViewType.platformView),
            ],
          ),
        ),
      ],
    );
  }
}

class _ButterFlyAssetVideoInList extends StatelessWidget {
  const _ButterFlyAssetVideoInList(this.viewType);

  final VideoViewType viewType;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        const _ExampleCard(title: 'Item a'),
        const _ExampleCard(title: 'Item b'),
        const _ExampleCard(title: 'Item c'),
        const _ExampleCard(title: 'Item d'),
        const _ExampleCard(title: 'Item e'),
        const _ExampleCard(title: 'Item f'),
        const _ExampleCard(title: 'Item g'),
        Card(
          child: Column(
            children: <Widget>[
              Column(
                children: <Widget>[
                  const ListTile(
                    leading: Icon(Icons.cake),
                    title: Text('Video video'),
                  ),
                  Stack(
                    alignment:
                        FractionalOffset.bottomRight +
                        const FractionalOffset(-0.1, -0.1),
                    children: <Widget>[
                      _ButterFlyAssetVideo(viewType),
                      Image.asset('assets/flutter-mark-square-64.png'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const _ExampleCard(title: 'Item h'),
        const _ExampleCard(title: 'Item i'),
        const _ExampleCard(title: 'Item j'),
        const _ExampleCard(title: 'Item k'),
        const _ExampleCard(title: 'Item l'),
      ],
    );
  }
}

/// A filler card to show the video in a list of scrolling contents.
class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.airline_seat_flat_angled),
            title: Text(title),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8.0,
              children: <Widget>[
                TextButton(
                  child: const Text('BUY TICKETS'),
                  onPressed: () {
                    /* ... */
                  },
                ),
                TextButton(
                  child: const Text('SELL TICKETS'),
                  onPressed: () {
                    /* ... */
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ButterFlyAssetVideo extends StatefulWidget {
  const _ButterFlyAssetVideo(this.viewType);

  final VideoViewType viewType;

  @override
  _ButterFlyAssetVideoState createState() => _ButterFlyAssetVideoState();
}

class _ButterFlyAssetVideoState extends State<_ButterFlyAssetVideo> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/Butterfly-209.mp4',
      viewType: widget.viewType,
    );

    _controller.addListener(() {
      setState(() {});
    });
    _controller.setLooping(true);
    _controller.initialize().then((_) => setState(() {}));
    _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Container(padding: const EdgeInsets.only(top: 20.0)),
          const Text('With assets mp4'),
          Container(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  VideoPlayer(_controller),
                  _ControlsOverlay(controller: _controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BumbleBeeRemoteVideo extends StatefulWidget {
  const _BumbleBeeRemoteVideo(this.viewType);

  final VideoViewType viewType;

  @override
  _BumbleBeeRemoteVideoState createState() => _BumbleBeeRemoteVideoState();
}

class _BumbleBeeRemoteVideoState extends State<_BumbleBeeRemoteVideo> {
  late VideoPlayerController _controller;

  Future<ClosedCaptionFile> _loadCaptions() async {
    final String fileContents = await DefaultAssetBundle.of(
      context,
    ).loadString('assets/bumble_bee_captions.vtt');
    return WebVTTCaptionFile(
      fileContents,
    ); // For vtt files, use WebVTTCaptionFile
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      ),
      closedCaptionFile: _loadCaptions(),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      viewType: widget.viewType,
    );

    _controller.addListener(() {
      setState(() {});
    });
    _controller.setLooping(true);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Container(padding: const EdgeInsets.only(top: 20.0)),
          const Text('With remote mp4'),
          Container(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  VideoPlayer(_controller),
                  ClosedCaption(text: _controller.value.caption.text),
                  _ControlsOverlay(controller: _controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({required this.controller});

  static const List<Duration> _exampleCaptionOffsets = <Duration>[
    Duration(seconds: -10),
    Duration(seconds: -3),
    Duration(seconds: -1, milliseconds: -500),
    Duration(milliseconds: -250),
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(seconds: 1, milliseconds: 500),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];
  static const List<double> _examplePlaybackRates = <double>[
    0.25,
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    5.0,
    10.0,
  ];

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 50),
          reverseDuration: const Duration(milliseconds: 200),
          child: controller.value.isPlaying
              ? const SizedBox.shrink()
              : const ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 100.0,
                      semanticLabel: 'Play',
                    ),
                  ),
                ),
        ),
        GestureDetector(
          onTap: () {
            controller.value.isPlaying ? controller.pause() : controller.play();
          },
        ),
        Align(
          alignment: Alignment.topLeft,
          child: PopupMenuButton<Duration>(
            initialValue: controller.value.captionOffset,
            tooltip: 'Caption Offset',
            onSelected: (Duration delay) {
              controller.setCaptionOffset(delay);
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuItem<Duration>>[
                for (final Duration offsetDuration in _exampleCaptionOffsets)
                  PopupMenuItem<Duration>(
                    value: offsetDuration,
                    child: Text('${offsetDuration.inMilliseconds}ms'),
                  ),
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                // Using less vertical padding as the text is also longer
                // horizontally, so it feels like it would need more spacing
                // horizontally (matching the aspect ratio of the video).
                vertical: 12,
                horizontal: 16,
              ),
              child: Text('${controller.value.captionOffset.inMilliseconds}ms'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: PopupMenuButton<double>(
            initialValue: controller.value.playbackSpeed,
            tooltip: 'Playback speed',
            onSelected: (double speed) {
              controller.setPlaybackSpeed(speed);
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuItem<double>>[
                for (final double speed in _examplePlaybackRates)
                  PopupMenuItem<double>(value: speed, child: Text('${speed}x')),
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                // Using less vertical padding as the text is also longer
                // horizontally, so it feels like it would need more spacing
                // horizontally (matching the aspect ratio of the video).
                vertical: 12,
                horizontal: 16,
              ),
              child: Text('${controller.value.playbackSpeed}x'),
            ),
          ),
        ),
      ],
    );
  }
}

class _PipBackgroundDemo extends StatefulWidget {
  const _PipBackgroundDemo();

  @override
  State<_PipBackgroundDemo> createState() => _PipBackgroundDemoState();
}

class _PipBackgroundDemoState extends State<_PipBackgroundDemo> {
  late VideoPlayerController _controller;
  bool _pipSupported = false;
  bool _autoEnterPip = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      ),
    );
    _controller.addListener(() => setState(() {}));
    _controller.setLooping(true);
    _controller.initialize().then((_) {
      setState(() {});
      _checkPipSupport();
    });
  }

  Future<void> _checkPipSupport() async {
    final supported = await _controller.isPipSupported;
    setState(() {
      _pipSupported = supported;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPipActive = _controller.value.isPipActive;
    final Size? pipSize = _controller.value.pipSize;

    // TODO(you): pipSize workaround for Flutter viewport bug in PiP.
    // Remove this block and uncomment the MediaQuery block below once
    // https://github.com/flutter/flutter/pull/182326 lands in stable.
    if (isPipActive && _controller.value.isInitialized && pipSize != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: pipSize.width,
          height: pipSize.height,
          child: FittedBox(
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          ),
        ),
      );
    }
    // // https://github.com/flutter/flutter/pull/182326 lands in stable.
    // // MediaQuery-based PiP layout — requires Flutter with #182326 fix.
    // final Size windowSize = MediaQuery.sizeOf(context);
    // final bool isPipLayout = isPipActive || windowSize.shortestSide < 250;
    //
    // if (isPipLayout && _controller.value.isInitialized) {
    //   return Scaffold(
    //     backgroundColor: Colors.black,
    //     body: AspectRatio(
    //       aspectRatio: _controller.value.aspectRatio,
    //       child: VideoPlayer(_controller),
    //     ),
    //   );
    // }

    return Scaffold(
      appBar: AppBar(title: const Text('PiP & Background Playback')),
      body: Column(
        children: <Widget>[
          if (_controller.value.isInitialized)
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  VideoPlayer(_controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            )
          else
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Play/Pause
                    Row(
                      children: <Widget>[
                        IconButton(
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          onPressed: () {
                            _controller.value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          },
                        ),
                        Text(
                          _controller.value.isPlaying ? 'Playing' : 'Paused',
                        ),
                      ],
                    ),
                    const Divider(),

                    // PiP section
                    Text(
                      'Picture-in-Picture',
                      style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Supported: $_pipSupported'),
                    Text('Active: ${_controller.value.isPipActive}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.picture_in_picture),
                          label: const Text('Enter PiP'),
                          onPressed: _pipSupported
                              ? () => _controller.enterPip()
                              : null,
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.fullscreen_exit),
                          label: const Text('Exit PiP'),
                          onPressed: _controller.value.isPipActive
                              ? () => _controller.exitPip()
                              : null,
                        ),
                        ElevatedButton.icon(
                          icon: Icon(_autoEnterPip
                              ? Icons.auto_awesome
                              : Icons.auto_awesome_outlined),
                          label: Text(_autoEnterPip
                              ? 'Disable Auto-PiP'
                              : 'Enable Auto-PiP'),
                          onPressed: _pipSupported
                              ? () {
                            final newValue = !_autoEnterPip;
                            _controller.setAutoEnterPip(newValue);
                            setState(() => _autoEnterPip = newValue);
                          }
                              : null,
                        ),
                      ],
                    ),
                    const Divider(),

                    // Background playback section
                    Text(
                      'Background Playback',
                      style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enabled: ${_controller.value.isPlayingInBackground}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.volume_up),
                          label: const Text('Enable Background'),
                          onPressed: !_controller.value.isPlayingInBackground
                              ? () =>
                              _controller.enableBackgroundPlayback(
                                mediaInfo: const MediaInfo(
                                  title: 'Bumblebee Video',
                                  artist: 'Flutter',
                                  artworkUrl:
                                      'https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
                                ),
                              )
                              : null,
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.volume_off),
                          label: const Text('Disable Background'),
                          onPressed: _controller.value.isPlayingInBackground
                              ? () => _controller.disableBackgroundPlayback()
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tip: Enable background playback, start playing, '
                          'then press the home button. Audio should continue '
                          'playing.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HlsAbrDemo extends StatefulWidget {
  const _HlsAbrDemo(this.viewType);

  final VideoViewType viewType;

  @override
  State<_HlsAbrDemo> createState() => _HlsAbrDemoState();
}

class _HlsAbrDemoState extends State<_HlsAbrDemo> {
  late VideoPlayerController _controller;
  List<VideoQuality> _qualities = <VideoQuality>[];
  VideoQuality? _currentQuality;
  int _cacheSizeBytes = 0;
  bool _cacheEnabled = true;
  String? _activeConstraint;
  final List<String> _log = <String>[];

  // Quality buttons are built dynamically from getAvailableQualities().

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://test-storage.reallifeglobal.com/demo_hls_1080/master.m3u8',
      ),
      formatHint: VideoFormat.hls,
      viewType: widget.viewType,
    );
    _controller.addListener(_onControllerUpdate);
    _controller.setLooping(true);
    _controller.initialize().then((_) {
      setState(() {});
      _refreshAll();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final VideoQuality? q = _controller.value.currentQuality;
    if (q != null && q != _currentQuality) {
      _addLog(
        'Quality changed -> ${q.width}x${q.height} '
        '@ ${_formatBitrate(q.bitrate)}',
      );
      _currentQuality = q;
    }
    setState(() {});
  }

  Future<void> _refreshAll() async {
    await Future.wait(<Future<void>>[
      _refreshQualities(),
      _refreshCacheInfo(),
    ]);
  }

  Future<void> _refreshQualities() async {
    final List<VideoQuality> qualities =
        await _controller.getAvailableQualities();
    // Sort by height ascending so buttons show low-to-high.
    qualities.sort(
      (VideoQuality a, VideoQuality b) => a.height.compareTo(b.height),
    );
    setState(() {
      _qualities = qualities;
    });
  }

  Future<void> _refreshCacheInfo() async {
    final int size = await VideoPlayerController.getCacheSize();
    final bool enabled = await VideoPlayerController.isCacheEnabled();
    setState(() {
      _cacheSizeBytes = size;
      _cacheEnabled = enabled;
    });
  }

  Future<void> _forceQuality(int width, int height, String label) async {
    // To force a specific quality, set BOTH max resolution AND max bitrate.
    // This tells the track selector to pick the variant that fits both
    // constraints.
    await _controller.setMaxResolution(width, height);
    _addLog('Set max resolution: ${width}x$height ($label)');
    setState(() {
      _activeConstraint = label;
    });
  }

  Future<void> _removeConstraints() async {
    await _controller.setMaxBitrate(999999999);
    await _controller.setMaxResolution(9999, 9999);
    _addLog('Removed all quality constraints (auto ABR)');
    setState(() {
      _activeConstraint = 'Auto';
    });
  }

  void _addLog(String message) {
    final String timestamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _log.insert(0, '[$timestamp] $message');
      if (_log.length > 30) {
        _log.removeLast();
      }
    });
  }

  String _formatBitrate(int bps) {
    if (bps <= 0) {
      return 'unknown';
    }
    if (bps < 1000) {
      return '$bps bps';
    }
    if (bps < 1000000) {
      return '${(bps / 1000).toStringAsFixed(0)} kbps';
    }
    return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _qualityLabel(VideoQuality q) {
    return '${q.width}x${q.height} @ ${_formatBitrate(q.bitrate)}';
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleMedium;
    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Video player
          Container(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: _controller.value.isInitialized
                  ? _controller.value.aspectRatio
                  : 16 / 9,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  VideoPlayer(_controller),
                  // Current quality badge overlay
                  if (_currentQuality != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_currentQuality!.height}p  '
                          '${_formatBitrate(_currentQuality!.bitrate)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  _ControlsOverlay(controller: _controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Force Quality section
                Text('Force Quality', style: titleStyle),
                const SizedBox(height: 4),
                Text(
                  'Active: ${_activeConstraint ?? "Auto (no constraint)"}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final VideoQuality q in _qualities)
                      _QualityButton(
                        label: '${q.height}p',
                        detail: _formatBitrate(q.bitrate),
                        isActive: _activeConstraint == '${q.height}p',
                        onPressed: () =>
                            _forceQuality(q.width, q.height, '${q.height}p'),
                      ),
                    _QualityButton(
                      label: 'Auto',
                      detail: 'ABR decides',
                      isActive: _activeConstraint == 'Auto',
                      onPressed: _removeConstraints,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Text(
                    'Note: Already-buffered segments play at their original '
                    'quality. After changing quality, seek forward past the '
                    'buffer to see the new quality immediately, or wait for '
                    'the buffer to drain during normal playback.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),

                // Available qualities
                if (_qualities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('Available Variants', style: titleStyle),
                  const SizedBox(height: 4),
                  for (final VideoQuality q in _qualities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${q.isSelected ? "-> " : "   "}'
                        '${_qualityLabel(q)}'
                        '${q.codec != null ? "  [${q.codec}]" : ""}',
                        style: monoStyle.copyWith(
                          fontWeight: q.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: q.isSelected ? Colors.green.shade700 : null,
                        ),
                      ),
                    ),
                ] else ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Load available qualities'),
                    onPressed: _refreshQualities,
                  ),
                ],
                const Divider(),

                // Cache section
                Row(
                  children: <Widget>[
                    Text('Cache', style: titleStyle),
                    const Spacer(),
                    Text(
                      '${_formatBytes(_cacheSizeBytes)}'
                      '  ${_cacheEnabled ? "(ON)" : "(OFF)"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: _refreshCacheInfo,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Refresh cache info',
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () async {
                        await VideoPlayerController.clearCache();
                        _addLog('Cache cleared');
                        await _refreshCacheInfo();
                      },
                      child: const Text('Clear'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await VideoPlayerController.setCacheEnabled(
                            !_cacheEnabled);
                        _addLog(
                          'Cache ${!_cacheEnabled ? "enabled" : "disabled"}',
                        );
                        await _refreshCacheInfo();
                      },
                      child: Text(_cacheEnabled ? 'Disable' : 'Enable'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await VideoPlayerController.setCacheMaxSize(
                          100 * 1024 * 1024,
                        );
                        _addLog('Cache max set to 100 MB');
                      },
                      child: const Text('100 MB'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await VideoPlayerController.setCacheMaxSize(
                          500 * 1024 * 1024,
                        );
                        _addLog('Cache max set to 500 MB');
                      },
                      child: const Text('500 MB'),
                    ),
                  ],
                ),
                const Divider(),

                // Log section
                Row(
                  children: <Widget>[
                    Text('Event Log', style: titleStyle),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _log.clear()),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  height: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _log.isEmpty
                      ? Text(
                          'No events yet...',
                          style: monoStyle.copyWith(color: Colors.grey),
                        )
                      : ListView.builder(
                          itemCount: _log.length,
                          itemBuilder: (BuildContext context, int index) {
                            return Text(
                              _log[index],
                              style: monoStyle.copyWith(
                                color: Colors.green.shade300,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.label,
    required this.detail,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blue : null,
        foregroundColor: isActive ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(detail, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

/// Plays an audio-only remote .m4a through the video_player controller.
///
/// This exists specifically to reproduce a crash in the platform-view path:
/// on Android, `PlatformViewExoPlayerEventListener.sendInitialized` used to
/// NPE because `exoPlayer.getVideoFormat()` returns null for audio-only
/// sources. Switch to the "Platform view" sub-tab to verify the fix.
class _AudioOnlyRemote extends StatefulWidget {
  const _AudioOnlyRemote(this.viewType);

  final VideoViewType viewType;

  @override
  State<_AudioOnlyRemote> createState() => _AudioOnlyRemoteState();
}

class _AudioOnlyRemoteState extends State<_AudioOnlyRemote> {
  late VideoPlayerController _controller;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://storage.reallifeglobal.com/podcasts/17084864-4093-41f0-b354-8620d841cb7e/LEwTV_-_Rihanna_APP.m4a',
      ),
      viewType: widget.viewType,
    );
    _controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    }).catchError((Object err) {
      if (mounted) {
        setState(() {
          _initError = err;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final String mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerValue value = _controller.value;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Audio-only remote .m4a (podcast)\n'
            'Use this tab with "Platform view" to repro the '
            'PlatformViewExoPlayerEventListener NPE on audio-only sources.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_initError != null)
            Text(
              'Init error: $_initError',
              style: const TextStyle(color: Colors.red),
            )
          else if (!value.isInitialized)
            const Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Initializing…'),
              ],
            )
          else ...<Widget>[
            Text('Duration: ${_fmt(value.duration)}'),
            Text('Position: ${_fmt(value.position)}'),
            Text('Size: ${value.size.width.toInt()}x${value.size.height.toInt()}'
                ' (audio-only = 0x0)'),
            const SizedBox(height: 12),
            VideoProgressIndicator(_controller, allowScrubbing: true),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    value.isPlaying ? _controller.pause() : _controller.play();
                  },
                ),
                Text(value.isPlaying ? 'Playing' : 'Paused'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerVideoAndPopPage extends StatefulWidget {
  @override
  _PlayerVideoAndPopPageState createState() => _PlayerVideoAndPopPageState();
}

class _PlayerVideoAndPopPageState extends State<_PlayerVideoAndPopPage> {
  late VideoPlayerController _videoPlayerController;
  bool startedPlaying = false;

  @override
  void initState() {
    super.initState();

    _videoPlayerController = VideoPlayerController.asset(
      'assets/Butterfly-209.mp4',
    );
    _videoPlayerController.addListener(() {
      if (startedPlaying && !_videoPlayerController.value.isPlaying) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    super.dispose();
  }

  Future<bool> started() async {
    await _videoPlayerController.initialize();
    await _videoPlayerController.play();
    startedPlaying = true;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Center(
        child: FutureBuilder<bool>(
          future: started(),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.data ?? false) {
              return AspectRatio(
                aspectRatio: _videoPlayerController.value.aspectRatio,
                child: VideoPlayer(_videoPlayerController),
              );
            } else {
              return const Text('waiting for video to load');
            }
          },
        ),
      ),
    );
  }
}
