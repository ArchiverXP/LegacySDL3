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

// This is the iOS implementation of the SDL joystick API
#include "../SDL_sysjoystick.h"
#include "../SDL_joystick_c.h"
#include "../hidapi/SDL_hidapijoystick_c.h"
#include "../usb_ids.h"
#include "../../events/SDL_events_c.h"

#include "SDL_mfijoystick_c.h"


#if defined(SDL_PLATFORM_IOS) && !defined(SDL_PLATFORM_TVOS)
#import <CoreMotion/CoreMotion.h>
#endif

#ifdef SDL_PLATFORM_MACOS
#include <IOKit/hid/IOHIDManager.h>
#include <AppKit/NSApplication.h>
#ifndef NSAppKitVersionNumber10_15
#define NSAppKitVersionNumber10_15 1894
#endif
#endif // SDL_PLATFORM_MACOS

//#import <GameController/GameController.h>

static int numjoysticks = 0;
int SDL_AppleTVRemoteOpenedAsJoystick = 0;
