// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation_objc/FVPEventBridge.h"

@import Foundation;

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

@interface FVPEventBridge () <FlutterStreamHandler>

/// The event channel to dispatch notifications to.
// TODO(stuartmorgan): Convert this to Pigeon event channels once the plugin is using Swift
// Pigeon generation.
@property(nonatomic) FlutterEventChannel *eventChannel;

/// The event sink associated with eventChannel.
///
/// Will be nil both before the channel listener is ready on the Dart side, and after it has been
/// closed on the Dart side.
@property(nonatomic, nullable) FlutterEventSink eventSink;

/// A queue of events received before eventSink is ready, to dispatch once the channel is fully
/// set up.
@property(nonatomic) NSMutableArray<NSObject *> *queuedEvents;

@end

@implementation FVPEventBridge

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger
                      channelName:(NSString *)channelName {
  self = [super init];
  if (self) {
    _queuedEvents = [[NSMutableArray alloc] init];
    _eventChannel = [FlutterEventChannel eventChannelWithName:channelName
                                              binaryMessenger:messenger];
    // This retain loop is broken in videoPlayerWasDisposed.
    [_eventChannel setStreamHandler:self];
  }
  return self;
}

#pragma mark FlutterStreamHandler

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
  self.eventSink = events;

  // Send any events that came in before the sink was ready.
  for (id event in self.queuedEvents) {
    self.eventSink(event);
  }
  [self.queuedEvents removeAllObjects];

  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  self.eventSink = nil;
  // No need to queue events coming in after this point; nil the queue so they will be discarded.
  self.queuedEvents = nil;
  return nil;
}

#pragma mark FVPVideoEventListener

- (void)videoPlayerDidInitializeWithDuration:(int64_t)duration size:(CGSize)size {
  [self sendOrQueue:@{
    @"event" : @"initialized",
    @"duration" : @(duration),
    @"width" : @(size.width),
    @"height" : @(size.height)
  }];
}

- (void)videoPlayerDidErrorWithMessage:(NSString *)errorMessage {
  [self sendOrQueue:[FlutterError errorWithCode:@"VideoError" message:errorMessage details:nil]];
}

- (void)videoPlayerDidComplete {
  [self sendOrQueue:@{@"event" : @"completed"}];
}

- (void)videoPlayerDidStartBuffering {
  [self sendOrQueue:@{@"event" : @"bufferingStart"}];
}

- (void)videoPlayerDidEndBuffering {
  [self sendOrQueue:@{@"event" : @"bufferingEnd"}];
}

- (void)videoPlayerDidUpdateBufferRegions:(NSArray<NSArray<NSNumber *> *> *)regions {
  [self sendOrQueue:@{@"event" : @"bufferingUpdate", @"values" : regions}];
}

- (void)videoPlayerDidSetPlaying:(BOOL)playing {
  [self sendOrQueue:@{@"event" : @"isPlayingStateUpdate", @"isPlaying" : @(playing)}];
}

- (void)videoPlayerDidChangePipState:(BOOL)isPipActive {
  [self sendOrQueue:@{@"event" : @"pipStateChanged", @"isPipActive" : @(isPipActive)}];
}

- (void)videoPlayerDidChangeQualityWithWidth:(NSInteger)width
                                      height:(NSInteger)height
                                     bitrate:(NSInteger)bitrate {
  [self sendOrQueue:@{
    @"event" : @"qualityChanged",
    @"width" : @(width),
    @"height" : @(height),
    @"bitrate" : @(bitrate),
  }];
}

- (void)videoPlayerWasDisposed {
  [self.eventChannel setStreamHandler:nil];
}

#pragma mark Private methods

/// Sends the given event to the event sink if it is ready to receive events, or enqueues it to send
/// later if not.
- (void)sendOrQueue:(id)event {
  FlutterEventSink eventSink = self.eventSink;
  if (!eventSink) {
    [self.queuedEvents addObject:event];
    return;
  }

  // The event sink dispatches over the Flutter binary messenger, which asserts that the engine is
  // running. The engine can be torn down (or suspended into a not-running state) while AVPlayer KVO
  // callbacks are still firing — most notably for "Designed for iPad" apps running on Apple Silicon
  // Macs, where the app keeps ticking while its window is backgrounded. Sending on a dead engine
  // raises NSInternalInconsistencyException ("Sending a message before the FlutterEngine has been
  // run."), which would otherwise propagate as an uncaught fatal exception. Catch it and re-queue
  // the event so it is delivered if the channel is listened to again.
  @try {
    eventSink(event);
  } @catch (NSException *exception) {
    // queuedEvents is nil once the Dart side has cancelled the stream, in which case the event is
    // intentionally discarded (messaging nil is a no-op).
    [self.queuedEvents addObject:event];
  }
}

@end
