// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import Foundation;

#import "FVPViewProvider.h"

NS_ASSUME_NONNULL_BEGIN

// A cross-platform display link abstraction.
@protocol FVPDisplayLink <NSObject>

/// Whether the display link is currently running (i.e., firing events).
///
/// Defaults to NO.
@property(nonatomic, assign) BOOL running;

/// The time interval between screen refresh updates.
@property(nonatomic, readonly) CFTimeInterval duration;

/// Stops the display link and removes it from the run loop, so that it will never fire again.
///
/// Unlike setting `running` to NO (which only pauses), this permanently tears the link down. It
/// must be called when the owning player is disposed: a merely-paused link stays registered in the
/// run loop and can still deliver a deferred callback during app termination (e.g. the AppKit
/// `-[NSApplication terminate:]` run-loop pump for "Designed for iPad" apps on Apple Silicon Macs),
/// firing `textureFrameAvailable:` into an engine that is being torn down. Idempotent.
- (void)invalidate;

@end

// An implementation of FVPDisplayLink using CADisplayLink.
API_AVAILABLE(ios(4.0), macos(14.0))
@interface FVPCADisplayLink : NSObject <FVPDisplayLink>

/// Initializes a display link that calls the given callback when fired.
///
/// The display link starts paused, so must be started, by setting 'running' to YES, before the
/// callback will fire.
- (instancetype)initWithViewProvider:(NSObject<FVPViewProvider> *)viewProvider
                            callback:(void (^)(void))callback NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

#if TARGET_OS_OSX
// An implementation of FVPDisplayLink using CVDisplayLink.
@interface FVPCoreVideoDisplayLink : NSObject <FVPDisplayLink>

/// Initializes a display link that calls the given callback when fired.
///
/// The display link starts paused, so must be started, by setting 'running' to YES, before the
/// callback will fire.
- (instancetype)initWithViewProvider:(NSObject<FVPViewProvider> *)viewProvider
                            callback:(void (^)(void))callback NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end
#endif

NS_ASSUME_NONNULL_END
