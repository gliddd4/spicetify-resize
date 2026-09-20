/*
 * nomin.m — remove a macOS app's hard-coded window minimum size.
 *
 * Spotify's desktop window refuses to go below 800x600. That floor is not CSS
 * and not a preference: it is NSWindow's minimum size, set from compiled code.
 * This library neutralises it by swizzling the four NSWindow accessors an app
 * can use to impose or read that floor.
 *
 * It is injected with DYLD_INSERT_LIBRARIES. That only works because Spotify
 * is signed with com.apple.security.cs.disable-library-validation, which
 * permits loading a library that is not signed by Spotify's team. An app
 * without that entitlement will refuse to load this and will simply start
 * normally — which is the intended, harmless failure mode.
 *
 * Nothing on disk is modified. The library exists only in the address space of
 * the process it is injected into.
 *
 * Build:  see scripts/build.sh
 */

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

/* Set SPOTIFY_RESIZER_DEBUG=1 to get a line on stderr for each swizzle. */
static int debug_enabled(void) {
    static int cached = -1;
    if (cached < 0) {
        const char *v = getenv("SPOTIFY_RESIZER_DEBUG");
        cached = (v && *v && *v != '0') ? 1 : 0;
    }
    return cached;
}

/*
 * Hide the window buttons ("traffic lights"). Enabled by default; set
 * SPOTIFY_RESIZER_HIDE_TRAFFIC_LIGHTS=0 to keep them.
 *
 * macOS only dims these when the window loses key status, so they are still
 * drawn over the top-left corner whenever the window is focused - which is
 * exactly when a full-screen now-playing view is being looked at.
 */
static int hide_traffic_lights_enabled(void) {
    static int cached = -1;
    if (cached < 0) {
        const char *v = getenv("SPOTIFY_RESIZER_HIDE_TRAFFIC_LIGHTS");
        cached = (v && *v && *v == '0') ? 0 : 1;
    }
    return cached;
}

static void log_line(const char *fmt, ...) {
    if (!debug_enabled()) return;
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fputc('\n', stderr);
}

/*
 * Swap two instance methods, but only if both exist. A future macOS or app
 * build could drop one; missing a method should degrade to "no change" rather
 * than crash on launch, because a crash here is a crash inside the host app.
 */
static void swizzle(Class cls, SEL original, SEL replacement) {
    if (!cls) {
        log_line("[nomin] no class to swizzle");
        return;
    }
    Method o = class_getInstanceMethod(cls, original);
    Method r = class_getInstanceMethod(cls, replacement);
    if (!o || !r) {
        log_line("[nomin] skipping -[%s %s] (method not found)",
                 class_getName(cls), sel_getName(original));
        return;
    }
    method_exchangeImplementations(o, r);
    log_line("[nomin] swizzled -[%s %s]", class_getName(cls), sel_getName(original));
}

/*
 * Ask the window for each standard button and hide it. -standardWindowButton:
 * creates the button on first ask, so this is safe to call before the window
 * has ever been displayed.
 */
static void hide_traffic_lights(NSWindow *w) {
    if (!w || !hide_traffic_lights_enabled()) return;

    static const NSWindowButton kinds[] = {
        NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton
    };
    static const char *names[] = { "close", "miniaturize", "zoom" };

    for (size_t i = 0; i < sizeof(kinds) / sizeof(kinds[0]); i++) {
        NSButton *b = [w standardWindowButton:kinds[i]];
        if (b && !b.isHidden) {
            b.hidden = YES;
            log_line("[nomin] hid %s button on %s", names[i],
                     NSStringFromClass([w class]).UTF8String);
        }
    }
}

@implementation NSWindow (NoMinimumSize)

/*
 * The setters call through to their (now-swapped) originals with a zero size
 * instead of returning early. Skipping the original outright would also drop
 * any bookkeeping AppKit does inside it, which is not worth the risk.
 */
- (void)nomin_setMinSize:(NSSize)size {
    (void)size;
    [self nomin_setMinSize:NSMakeSize(0, 0)];
}

- (void)nomin_setContentMinSize:(NSSize)size {
    (void)size;
    [self nomin_setContentMinSize:NSMakeSize(0, 0)];
}

/*
 * Some code paths read the floor back and re-apply it, so the getters have to
 * agree that there is no floor. Reporting zero is what makes the removal stick.
 */
- (NSSize)nomin_minSize {
    return NSMakeSize(0, 0);
}

- (NSSize)nomin_contentMinSize {
    return NSMakeSize(0, 0);
}

/*
 * Hide on every path that shows a window. The constructor runs before any
 * window exists, so a single pass at startup is not enough - and AppKit can
 * re-show the buttons when a window changes state, so this has to repeat.
 */
- (void)nomin_makeKeyAndOrderFront:(id)sender {
    [self nomin_makeKeyAndOrderFront:sender];
    hide_traffic_lights(self);
}

- (void)nomin_orderFront:(id)sender {
    [self nomin_orderFront:sender];
    hide_traffic_lights(self);
}

- (void)nomin_orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
    [self nomin_orderWindow:place relativeTo:otherWin];
    hide_traffic_lights(self);
}

@end

__attribute__((constructor))
static void nomin_init(void) {
    log_line("[nomin] injected into pid %d", getpid());

    /*
     * Swizzling on NSWindow covers NSPanel and any subclass that does not
     * override these itself, which is every case seen in practice. A subclass
     * that overrides them would need its own swizzle.
     */
    Class win = objc_getClass("NSWindow");

    swizzle(win, @selector(setMinSize:),        @selector(nomin_setMinSize:));
    swizzle(win, @selector(setContentMinSize:), @selector(nomin_setContentMinSize:));
    swizzle(win, @selector(minSize),            @selector(nomin_minSize));
    swizzle(win, @selector(contentMinSize),     @selector(nomin_contentMinSize));

    if (!hide_traffic_lights_enabled()) {
        log_line("[nomin] traffic lights left visible (opted out)");
        return;
    }

    swizzle(win, @selector(makeKeyAndOrderFront:),  @selector(nomin_makeKeyAndOrderFront:));
    swizzle(win, @selector(orderFront:),            @selector(nomin_orderFront:));
    swizzle(win, @selector(orderWindow:relativeTo:),@selector(nomin_orderWindow:relativeTo:));

    /*
     * Re-hide when a window becomes key/main/exposed. AppKit re-shows the
     * buttons on some state changes, and these fire rarely enough that the
     * repeated work is negligible.
     */
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSArray<NSString *> *events = @[
        NSWindowDidBecomeKeyNotification,
        NSWindowDidBecomeMainNotification,
        NSWindowDidExposeNotification
    ];
    for (NSString *name in events) {
        [nc addObserverForName:name
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        id obj = note.object;
                        if ([obj isKindOfClass:[NSWindow class]]) {
                            hide_traffic_lights((NSWindow *)obj);
                        }
                    }];
    }

    /*
     * The constructor runs before NSApplication finishes launching, so there is
     * no window yet. Sweep whatever exists once the run loop is up.
     */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        for (NSWindow *w in [NSApp windows]) {
            hide_traffic_lights(w);
        }
        log_line("[nomin] traffic light sweep done (%lu windows)",
                 (unsigned long)[NSApp windows].count);
    });
}
