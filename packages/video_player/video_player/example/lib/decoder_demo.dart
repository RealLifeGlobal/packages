// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'decoder_retry_example.dart';

class DecoderDemo extends StatefulWidget {
  const DecoderDemo(this.viewType, {super.key});

  final VideoViewType viewType;

  @override
  State<DecoderDemo> createState() => _DecoderDemoState();
}

class _DecoderDemoState extends State<DecoderDemo> {
  late VideoPlayerController _controller;
  List<VideoDecoderInfo> _decoders = <VideoDecoderInfo>[];
  String? _currentDecoder;
  bool? _isCurrentHw;
  String? _selectedDecoderName; // null = auto
  final List<String> _log = <String>[];
  bool _retrying = false;

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
      _refreshDecoders();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final String? name = _controller.value.decoderName;
    final bool? isHw = _controller.value.isDecoderHardwareAccelerated;
    if (name != null && name != _currentDecoder) {
      _addLog(
        'Decoder changed -> $name '
        '(${(isHw ?? false) ? 'HW' : 'SW'})',
      );
      _currentDecoder = name;
      _isCurrentHw = isHw;
      // Refresh decoder list to update isSelected
      _refreshDecoders();
    }
    setState(() {});
  }

  Future<void> _refreshDecoders() async {
    final List<VideoDecoderInfo> decoders =
        await _controller.getAvailableDecoders();
    final String? current = await _controller.getCurrentDecoderName();
    setState(() {
      _decoders = decoders;
      _currentDecoder = current;
    });
  }

  Future<void> _selectDecoder(String? decoderName) async {
    _selectedDecoderName = decoderName;
    final String label = decoderName ?? 'Auto';
    _addLog('Switching to decoder: $label');
    try {
      await _controller.setVideoDecoder(decoderName);
      _addLog('Decoder switch complete');
      await _refreshDecoders();
    } catch (e) {
      _addLog('Decoder switch failed: $e');
    }
  }

  Future<void> _runRetryDemo() async {
    if (_retrying) {
      return;
    }
    setState(() {
      _retrying = true;
    });
    _addLog('--- Retry demo started ---');

    final retrier = DecoderRetrier(
      _controller,
      settleDelay: const Duration(seconds: 1),
      onAttempt: (VideoDecoderInfo decoder, int attempt) {
        _addLog(
          'Attempt $attempt: trying ${decoder.name} '
          '(${decoder.isHardwareAccelerated ? 'HW' : 'SW'})',
        );
      },
      onSuccess: (VideoDecoderInfo decoder) {
        _addLog('Success: ${decoder.name} works!');
      },
      onExhausted: () {
        _addLog('All decoders exhausted — none worked');
      },
    );

    final String? result = await retrier.retryWithFallback();
    _addLog(
      result != null
          ? '--- Retry demo done: using $result ---'
          : '--- Retry demo done: no working decoder ---',
    );
    await _refreshDecoders();
    setState(() => _retrying = false);
  }

  void _addLog(String message) {
    setState(() {
      final String ts = TimeOfDay.now().format(context);
      _log.insert(0, '[$ts] $message');
      if (_log.length > 50) {
        _log.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Video player
            if (_controller.value.isInitialized)
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            else
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),

            const SizedBox(height: 8),

            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  onPressed: () => _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play(),
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                ),
              ],
            ),

            const Divider(),

            // Current decoder info
            Text(
              'Current Decoder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            if (_currentDecoder != null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _currentDecoder!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  Chip(
                    label: Text((_isCurrentHw ?? false) ? 'HW' : 'SW'),
                    backgroundColor:
                        (_isCurrentHw ?? false) ? Colors.green[100] : Colors.orange[100],
                  ),
                ],
              )
            else
              const Text('Not initialized yet'),

            const Divider(),

            // Available decoders
            Text(
              'Available Decoders',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),

            // Auto option
            RadioListTile<String?>(
              title: const Text('Auto (system default)'),
              value: null,
              groupValue: _selectedDecoderName,
              dense: true,
              onChanged: (String? value) => _selectDecoder(null),
            ),

            // Decoder list
            if (_decoders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('No decoders available (play a video first)'),
              )
            else
              ..._decoders.map(
                (VideoDecoderInfo d) => RadioListTile<String?>(
                  title: Text(
                    d.name,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  subtitle: Row(
                    children: <Widget>[
                      Text(d.mimeType, style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: d.isHardwareAccelerated
                              ? Colors.green[100]
                              : Colors.orange[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.isHardwareAccelerated ? 'HW' : 'SW',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  value: d.name,
                  groupValue: _selectedDecoderName,
                  dense: true,
                  onChanged: (String? value) => _selectDecoder(value),
                ),
              ),

            const Divider(),

            // Retry demo
            Text(
              'Decoder Retry Demo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Iterates through all available decoders (HW first, then SW) '
              'until one works. Demonstrates best practices for handling '
              'decoder failures on problematic devices.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _retrying ? null : _runRetryDemo,
              icon: _retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_retrying ? 'Retrying...' : 'Run Decoder Retry'),
            ),

            const Divider(),

            // Event log
            Text(
              'Event Log',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: _log.isEmpty
                  ? const Center(
                      child: Text(
                        'Events will appear here',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _log.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (BuildContext context, int index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            _log[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
