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
}
