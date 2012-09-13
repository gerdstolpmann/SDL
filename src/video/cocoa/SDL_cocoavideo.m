/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2012 Sam Lantinga <slouken@libsdl.org>

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
#include "SDL_config.h"

#if SDL_VIDEO_DRIVER_COCOA

#if defined(__APPLE__) && defined(__POWERPC__)
#include <altivec.h>
#undef bool
#undef vector
#endif

#include "SDL.h"
#include "SDL_endian.h"
#include "SDL_cocoavideo.h"
#include "SDL_cocoashape.h"
#include "SDL_assert.h"

/* Initialization/Query functions */
static int Cocoa_VideoInit(_THIS);
static void Cocoa_VideoQuit(_THIS);

/* Cocoa driver bootstrap functions */

static int
Cocoa_Available(void)
{
    return (1);
}

static void
Cocoa_DeleteDevice(SDL_VideoDevice * device)
{
    SDL_free(device->driverdata);
    SDL_free(device);
}

static SDL_VideoDevice *
Cocoa_CreateDevice(int devindex)
{
    SDL_VideoDevice *device;
    SDL_VideoData *data;

    Cocoa_RegisterApp();

    /* Initialize all variables that we clean on shutdown */
    device = (SDL_VideoDevice *) SDL_calloc(1, sizeof(SDL_VideoDevice));
    if (device) {
        data = (struct SDL_VideoData *) SDL_calloc(1, sizeof(SDL_VideoData));
    } else {
        data = NULL;
    }
    if (!data) {
        SDL_OutOfMemory();
        if (device) {
            SDL_free(device);
        }
        return NULL;
    }
    device->driverdata = data;

    /* Find out what version of Mac OS X we're running */
    Gestalt(gestaltSystemVersion, &data->osversion);

    /* Set the function pointers */
    device->VideoInit = Cocoa_VideoInit;
    device->VideoQuit = Cocoa_VideoQuit;
    device->GetDisplayBounds = Cocoa_GetDisplayBounds;
    device->GetDisplayModes = Cocoa_GetDisplayModes;
    device->SetDisplayMode = Cocoa_SetDisplayMode;
    device->PumpEvents = Cocoa_PumpEvents;

    device->CreateWindow = Cocoa_CreateWindow;
    device->CreateWindowFrom = Cocoa_CreateWindowFrom;
    device->SetWindowTitle = Cocoa_SetWindowTitle;
    device->SetWindowIcon = Cocoa_SetWindowIcon;
    device->SetWindowPosition = Cocoa_SetWindowPosition;
    device->SetWindowSize = Cocoa_SetWindowSize;
    device->ShowWindow = Cocoa_ShowWindow;
    device->HideWindow = Cocoa_HideWindow;
    device->RaiseWindow = Cocoa_RaiseWindow;
    device->MaximizeWindow = Cocoa_MaximizeWindow;
    device->MinimizeWindow = Cocoa_MinimizeWindow;
    device->RestoreWindow = Cocoa_RestoreWindow;
    device->SetWindowFullscreen = Cocoa_SetWindowBordered;
    device->SetWindowFullscreen = Cocoa_SetWindowFullscreen;
    device->SetWindowGammaRamp = Cocoa_SetWindowGammaRamp;
    device->GetWindowGammaRamp = Cocoa_GetWindowGammaRamp;
    device->SetWindowGrab = Cocoa_SetWindowGrab;
    device->DestroyWindow = Cocoa_DestroyWindow;
    device->GetWindowWMInfo = Cocoa_GetWindowWMInfo;
    
    device->shape_driver.CreateShaper = Cocoa_CreateShaper;
    device->shape_driver.SetWindowShape = Cocoa_SetWindowShape;
    device->shape_driver.ResizeWindowShape = Cocoa_ResizeWindowShape;
    
#if SDL_VIDEO_OPENGL_CGL
    device->GL_LoadLibrary = Cocoa_GL_LoadLibrary;
    device->GL_GetProcAddress = Cocoa_GL_GetProcAddress;
    device->GL_UnloadLibrary = Cocoa_GL_UnloadLibrary;
    device->GL_CreateContext = Cocoa_GL_CreateContext;
    device->GL_MakeCurrent = Cocoa_GL_MakeCurrent;
    device->GL_SetSwapInterval = Cocoa_GL_SetSwapInterval;
    device->GL_GetSwapInterval = Cocoa_GL_GetSwapInterval;
    device->GL_SwapWindow = Cocoa_GL_SwapWindow;
    device->GL_DeleteContext = Cocoa_GL_DeleteContext;
#endif

    device->StartTextInput = Cocoa_StartTextInput;
    device->StopTextInput = Cocoa_StopTextInput;
    device->SetTextInputRect = Cocoa_SetTextInputRect;

    device->SetClipboardText = Cocoa_SetClipboardText;
    device->GetClipboardText = Cocoa_GetClipboardText;
    device->HasClipboardText = Cocoa_HasClipboardText;

    device->free = Cocoa_DeleteDevice;

    return device;
}

VideoBootStrap COCOA_bootstrap = {
    "cocoa", "SDL Cocoa video driver",
    Cocoa_Available, Cocoa_CreateDevice
};


int
Cocoa_VideoInit(_THIS)
{
    Cocoa_InitModes(_this);
    Cocoa_InitKeyboard(_this);
    Cocoa_InitMouse(_this);
    return 0;
}

void
Cocoa_VideoQuit(_THIS)
{
    Cocoa_QuitModes(_this);
    Cocoa_QuitKeyboard(_this);
    Cocoa_QuitMouse(_this);
}

/* This function assumes that it's called from within an autorelease pool */
NSImage *
Cocoa_CreateImage(SDL_Surface * surface)
{
    SDL_Surface *converted;
    NSBitmapImageRep *imgrep;
    Uint8 *pixels;
    int i;
    NSImage *img;

    converted = SDL_ConvertSurfaceFormat(surface, 
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
                                         SDL_PIXELFORMAT_RGBA8888,
#else
                                         SDL_PIXELFORMAT_ABGR8888,
#endif
                                         0);
    if (!converted) {
        return nil;
    }

    imgrep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                    pixelsWide: converted->w
                    pixelsHigh: converted->h
                    bitsPerSample: 8
                    samplesPerPixel: 4
                    hasAlpha: YES
                    isPlanar: NO
                    colorSpaceName: NSDeviceRGBColorSpace
                    bytesPerRow: converted->pitch
                    bitsPerPixel: converted->format->BitsPerPixel] autorelease];
    if (imgrep == nil) {
        SDL_FreeSurface(converted);
        return nil;
    }

    /* Copy the pixels */
    pixels = [imgrep bitmapData];
    SDL_memcpy(pixels, converted->pixels, converted->h * converted->pitch);
    SDL_FreeSurface(converted);

    /* Premultiply the alpha channel */
    for (i = (surface->h * surface->w); i--; ) {
        Uint8 alpha = pixels[3];
        pixels[0] = (Uint8)(((Uint16)pixels[0] * alpha) / 255);
        pixels[1] = (Uint8)(((Uint16)pixels[1] * alpha) / 255);
        pixels[2] = (Uint8)(((Uint16)pixels[2] * alpha) / 255);
        pixels += 4;
    }

    img = [[[NSImage alloc] initWithSize: NSMakeSize(surface->w, surface->h)] autorelease];
    if (img != nil) {
        [img addRepresentation: imgrep];
    }
    return img;
}

/*
 * Mac OS X assertion support.
 *
 * This doesn't really have aything to do with the interfaces of the SDL video
 *  subsystem, but we need to stuff this into an Objective-C source code file.
 */

SDL_assert_state
SDL_PromptAssertion_cocoa(const SDL_assert_data *data)
{
    const int initialized = (SDL_WasInit(SDL_INIT_VIDEO) != 0);
    if (!initialized) {
        if (SDL_InitSubSystem(SDL_INIT_VIDEO) == -1) {
            fprintf(stderr, "Assertion failed AND couldn't init video mode!\n");
            return SDL_ASSERTION_BREAK;  /* oh well, crash hard. */
        }
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *msg = [NSString stringWithFormat:
            @"Assertion failure at %s (%s:%d), triggered %u time%s:\n  '%s'",
                data->function, data->filename, data->linenum,
                data->trigger_count, (data->trigger_count == 1) ? "" : "s",
                data->condition];

    NSLog(@"%@", msg);

    /*
     * !!! FIXME: this code needs to deal with fullscreen modes:
     * !!! FIXME:  reset to default desktop, runModal, reset to current?
     */

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert setMessageText:msg];
    [alert addButtonWithTitle:@"Retry"];
    [alert addButtonWithTitle:@"Break"];
    [alert addButtonWithTitle:@"Abort"];
    [alert addButtonWithTitle:@"Ignore"];
    [alert addButtonWithTitle:@"Always Ignore"];
    const NSInteger clicked = [alert runModal];
    [pool release];

    if (!initialized) {
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
    }

    return (SDL_assert_state) (clicked - NSAlertFirstButtonReturn);
}

#endif /* SDL_VIDEO_DRIVER_COCOA */

/* vim: set ts=4 sw=4 expandtab: */
