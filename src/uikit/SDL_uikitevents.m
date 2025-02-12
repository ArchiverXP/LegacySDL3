/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2025 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_UIKIT

#include "../../events/SDL_events_c.h"
#include "../../main/SDL_main_callbacks.h"

#include "SDL_uikitevents.h"
#include "SDL_uikitopengles.h"
#include "SDL_uikitvideo.h"
#include "SDL_uikitwindow.h"

#import <Foundation/Foundation.h>
//#import <GameController/GameController.h>: not on ios 6

static BOOL UIKit_EventPumpEnabled = YES;

@interface SDL_LifecycleObserver : NSObject
@property(nonatomic, assign) BOOL isObservingNotifications;
@end

@implementation SDL_LifecycleObserver

- (void)update
{
    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    bool wants_observation = (UIKit_EventPumpEnabled || SDL_HasMainCallbacks());
    if (!wants_observation) {
        // Make sure no windows have active animation callbacks
        int num_windows = 0;
        SDL_free(SDL_GetWindows(&num_windows));
        if (num_windows > 0) {
            wants_observation = true;
        }
    }
    if (wants_observation && !self.isObservingNotifications) {
        self.isObservingNotifications = YES;
        [notificationCenter addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [notificationCenter addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
        [notificationCenter addObserver:self selector:@selector(applicationDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [notificationCenter addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
        [notificationCenter addObserver:self selector:@selector(applicationWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
        [notificationCenter addObserver:self selector:@selector(applicationDidReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#if !defined(SDL_PLATFORM_TVOS) && !defined(SDL_PLATFORM_VISIONOS)
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidChangeStatusBarOrientation)
                                   name:UIApplicationDidChangeStatusBarOrientationNotification
                                 object:nil];
#endif
    } else if (!wants_observation && self.isObservingNotifications) {
        self.isObservingNotifications = NO;
        [notificationCenter removeObserver:self];
    }
}

- (void)applicationDidBecomeActive
{
    SDL_OnApplicationDidEnterForeground();
}

- (void)applicationWillResignActive
{
    SDL_OnApplicationWillEnterBackground();
}

- (void)applicationDidEnterBackground
{
    SDL_OnApplicationDidEnterBackground();
}

- (void)applicationWillEnterForeground
{
    SDL_OnApplicationWillEnterForeground();
}

- (void)applicationWillTerminate
{
    SDL_OnApplicationWillTerminate();
}

- (void)applicationDidReceiveMemoryWarning
{
    SDL_OnApplicationDidReceiveMemoryWarning();
}

#if !defined(SDL_PLATFORM_TVOS) && !defined(SDL_PLATFORM_VISIONOS)
- (void)applicationDidChangeStatusBarOrientation
{
    SDL_OnApplicationDidChangeStatusBarOrientation();
}
#endif

@end

void SDL_UpdateLifecycleObserver(void)
{
    static SDL_LifecycleObserver *lifecycleObserver;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      lifecycleObserver = [SDL_LifecycleObserver new];
    });
    [lifecycleObserver update];
}

void SDL_SetiOSEventPump(bool enabled)
{
    UIKit_EventPumpEnabled = enabled;

    SDL_UpdateLifecycleObserver();
}

Uint64 UIKit_GetEventTimestamp(NSTimeInterval nsTimestamp)
{
    static Uint64 timestamp_offset;
    Uint64 timestamp = (Uint64)(nsTimestamp * SDL_NS_PER_SECOND);
    Uint64 now = SDL_GetTicksNS();

    if (!timestamp_offset) {
        timestamp_offset = (now - timestamp);
    }
    timestamp += timestamp_offset;

    if (timestamp > now) {
        timestamp_offset -= (timestamp - now);
        timestamp = now;
    }
    return timestamp;
}

void UIKit_PumpEvents(SDL_VideoDevice *_this)
{
    if (!UIKit_EventPumpEnabled) {
        return;
    }

    /* Let the run loop run for a short amount of time: long enough for
       touch events to get processed (which is important to get certain
       elements of Game Center's GKLeaderboardViewController to respond
       to touch input), but not long enough to introduce a significant
       delay in the rest of the app.
    */
    const CFTimeInterval seconds = 0.000002;

    // Pump most event types.
    SInt32 result;
    do {
        result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, TRUE);
    } while (result == kCFRunLoopRunHandledSource);

    // Make sure UIScrollView objects scroll properly.
    do {
        result = CFRunLoopRunInMode((CFStringRef)UITrackingRunLoopMode, seconds, TRUE);
    } while (result == kCFRunLoopRunHandledSource);

    // See the comment in the function definition.
#if defined(SDL_VIDEO_OPENGL_ES) || defined(SDL_VIDEO_OPENGL_ES2)
    UIKit_GL_RestoreCurrentContext();
#endif
}

static id keyboard_connect_observer = nil;
static id keyboard_disconnect_observer = nil;

static id mouse_connect_observer = nil;
static id mouse_disconnect_observer = nil;
static bool mouse_relative_mode = false;

static SDL_MouseWheelDirection mouse_scroll_direction = SDL_MOUSEWHEEL_NORMAL;

static void UpdateScrollDirection(void)
{
#if 0 // This code doesn't work for some reason
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults boolForKey:@"com.apple.swipescrolldirection"]) {
        mouse_scroll_direction = SDL_MOUSEWHEEL_FLIPPED;
    } else {
        mouse_scroll_direction = SDL_MOUSEWHEEL_NORMAL;
    }
#else
    Boolean keyExistsAndHasValidFormat = NO;
    Boolean naturalScrollDirection = CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"), kCFPreferencesAnyApplication, &keyExistsAndHasValidFormat);
    if (!keyExistsAndHasValidFormat) {
        // Couldn't read the preference, assume natural scrolling direction
        naturalScrollDirection = YES;
    }
    if (naturalScrollDirection) {
        mouse_scroll_direction = SDL_MOUSEWHEEL_FLIPPED;
    } else {
        mouse_scroll_direction = SDL_MOUSEWHEEL_NORMAL;
    }
#endif
}

static void UpdatePointerLock(void)
{
    SDL_VideoDevice *_this = SDL_GetVideoDevice();
    SDL_Window *window;

    for (window = _this->windows; window != NULL; window = window->next) {
        UIKit_UpdatePointerLock(_this, window);
    }
}

static bool SetGCMouseRelativeMode(bool enabled)
{
    mouse_relative_mode = enabled;
    UpdatePointerLock();
    return true;
}

static void OnGCMouseButtonChanged(SDL_MouseID mouseID, Uint8 button, BOOL pressed)
{
    Uint64 timestamp = SDL_GetTicksNS();
    SDL_SendMouseButton(timestamp, SDL_GetMouseFocus(), mouseID, button, pressed);
}


bool SDL_GCMouseRelativeMode(void)
{
    return mouse_relative_mode;
}

#endif // SDL_VIDEO_DRIVER_UIKIT
