# spotify-resizer

Remove Spotify's hard-coded **800×600** window minimum on macOS, so the window can be dragged down to a narrow vertical panel — a third of a 1440px display, a sidebar, an always-visible strip.

```
before                          after
┌────────────────────┐          ┌──────────┐
│                    │          │          │
│   won't go below   │          │          │
│      800 × 600     │          │  ~480px  │
│                    │          │          │
└────────────────────┘          └──────────┘
```

## What's in here

```
src/nomin.m              the injected library — four NSWindow swizzles
scripts/build.sh         compile + ad-hoc sign it
scripts/install.sh       install the library and the launch shim
scripts/status.sh        check whether the patch is currently in effect
scripts/uninstall.sh     restore Spotify to stock
scripts/launch-debug.sh  launch with debug logging and a CDP port
scripts/block-updates.sh stop Spotify replacing its own bundle
scripts/allow-updates.sh undo that
spicetify/user.css       the CSS half, installable as a Spicetify theme
```

## The problem

Spotify's macOS window refuses to shrink past 800×600. It looks like a CSS bug, because Spotify's own stylesheet contains a suspiciously matching rule:

```css
body { width: 100%; min-width: 800px; height: 100%; min-height: 600px; overflow: hidden }
```

It isn't the cause. Every CSS route was tested and the window still clamped:

| what was changed | result |
|---|---|
| `body { min-width: 0 }`, verified `getComputedStyle(body).minWidth === "0px"` | still 800×600 |
| `min-width: 800px` → `0px` edited directly in Spotify's own `xpui.css`, before any override | still 800×600 |
| `.main-nowPlayingBar-container { min-width: 620px }` neutralised too | still 800×600 |
| `Browser.setWindowBounds` asked for 700 / 600 / 480 / 400 / 320 / 260 | all clamped to 800 |

The floor is `NSWindow`'s minimum size, set from compiled code. No stylesheet can reach it.

## Why this is not a Spicetify extension

Spicetify ships themes, extensions and custom apps — all of which are files loaded into Spotify's CEF web view. The window minimum lives one layer below that, in native AppKit:

```
Spotify.app — one macOS process
├── Native macOS layer
│     NSWindow minSize = 800 × 600      ← the floor lives here
│     ✓ reachable by an injected library
└── CEF web layer (Chromium)
      HTML · CSS · JS — the xpui bundle
      Spicetify themes/extensions/apps    ← cannot reach NSWindow
```

That is why this is a standalone macOS tool rather than a Spicetify item. The CSS half *can* ship as a Spicetify snippet — see [`spicetify/user.css`](spicetify/user.css).

## How it works

Spotify is signed with `com.apple.security.cs.disable-library-validation`, which permits loading a library that isn't signed by Spotify's team. So a small dylib is injected via `DYLD_INSERT_LIBRARIES` and swizzles the four `NSWindow` accessors that impose or report the floor:

```objc
- (void)nomin_setMinSize:(NSSize)size        { [self nomin_setMinSize:NSMakeSize(0, 0)]; }
- (void)nomin_setContentMinSize:(NSSize)size { [self nomin_setContentMinSize:NSMakeSize(0, 0)]; }
- (NSSize)nomin_minSize                      { return NSMakeSize(0, 0); }
- (NSSize)nomin_contentMinSize               { return NSMakeSize(0, 0); }
```

The setters call through to their originals with a zero size rather than skipping them, so AppKit's internal bookkeeping still runs. The getters report zero because some code paths read the floor back and re-apply it.

**No binary is patched.** The real Spotify executable is never modified.

Getting the variable in place is the fiddly part. These were tried and rejected:

- **`LSEnvironment` in Spotify's `Info.plist`** — macOS strips `DYLD_*` from it for hardened-runtime apps. Verified: Spotify launched with no library loaded.
- **`launchctl setenv`** — global, would inject into every GUI app.
- **A separate launcher `.app`** — works, but macOS gives it its own Dock tile, so you end up with two Spotify icons while it runs.

What works is a **launch shim inside the bundle**: a small script next to the real binary, with `CFBundleExecutable` repointed at it. One icon, works from the Dock, Spotlight, anywhere.

## Install

Requires macOS and Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/gliddd4/spotify-resizer
cd spotify-resizer
sh scripts/install.sh
```

Then restart Spotify:

```sh
osascript -e 'quit app "Spotify"' && sleep 2 && open -a Spotify
```

If you downloaded this as a zip, clear the quarantine flag first — macOS will otherwise let dyld refuse the library, and you'll get a normal, unresizable Spotify with no error:

```sh
xattr -dr com.apple.quarantine .
```

### Verify

```sh
sh scripts/status.sh          # the quick answer
```

Or by hand:

```sh
# the main process (this anchored pattern skips the Helper/renderer children)
pgrep -f '^/Applications/Spotify\.app/Contents/MacOS/Spotify( |$)'

# was the library injected?
lsof -p "$(pgrep -f '^/Applications/Spotify\.app/Contents/MacOS/Spotify( |$)' | head -1)" | grep libnomin
```

Then just drag the window edge.

To watch the swizzles fire, run Spotify with the debug flag set. The shim doesn't pass it through, so launch the real binary directly:

```sh
sh scripts/launch-debug.sh    # also opens a CDP port on 9222
```

which is equivalent to:

```sh
DYLD_INSERT_LIBRARIES="$HOME/.spotify-resizer/libnomin.dylib" \
SPOTIFY_RESIZER_DEBUG=1 \
  /Applications/Spotify.app/Contents/MacOS/Spotify
```

You'll get one line per swizzle on stderr:

```
[nomin] injected into pid 15213
[nomin] swizzled -[NSWindow setMinSize:]
[nomin] swizzled -[NSWindow setContentMinSize:]
[nomin] swizzled -[NSWindow minSize]
[nomin] swizzled -[NSWindow contentMinSize]
```

## Uninstall

```sh
sh scripts/uninstall.sh
```

Restores `CFBundleExecutable` from a byte-exact backup, removes the shim and the library, and re-registers the bundle with LaunchServices. If you blocked updates, also run `sh scripts/allow-updates.sh`.

## Disabling auto-updates

Spotify's desktop client has **no auto-update setting** — no toggle in the UI, and no `"automatic update"` string anywhere in the UI bundles. `spicetify spotify-updates block` is not a workaround either: on Spotify 1.3.1.234 it prints `success  Disabled Spotify updates!` while leaving the binary **byte-identical**. It's a find/replace against version-specific bytes that no longer match, so it fails silently. Don't trust it.

What does work is targeting the swap step. Spotify downloads a new `.app` and hands the swap to a helper, `Contents/MacOS/sp_relauncher`. Inspecting every executable in the bundle shows that `sp_relauncher` is the only one that knows how:

```
replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error:
update_started   old-app-version   new-app-version   launch-updated-client
```

The main `Spotify` binary contains none of those strings — it only references `sp_relauncher` by name. So removing the execute bit blocks the swap while leaving Spotify fully functional:

```sh
sh scripts/block-updates.sh     # chmod -x sp_relauncher
sh scripts/allow-updates.sh     # put it back
```

This is mechanism-based, not vendor-supported. It's been verified to leave Spotify working normally, but it can't be verified to block an update without waiting for one to ship. If an update does slip through, the resize patch is reverted — re-run `install.sh`.

Trade-off worth stating plainly: blocking updates means no security fixes. The alternative is to leave updates on and re-run `install.sh` after each one.

## Checking whether the patch survived

```sh
sh scripts/status.sh
```

```
Spotify 1.3.1.234  (/Applications/Spotify.app)

  launch shim            installed (CFBundleExecutable = SpotifyLauncher)
  shim file              present
  helper library         present at /Users/ab/.spotify-resizer/libnomin.dylib
  running process        pid 15213, helper LOADED
  auto-updates           blocked (sp_relauncher not executable)

Patch is installed. Restart Spotify if the running process has no helper.
```

## Caveats

- **Spotify updates undo this.** An update replaces the bundle, so the shim disappears and the window goes back to 800×600. The failure is silent — Spotify keeps working, it just stops resizing. Either re-run `install.sh` after updating, or block updates with `block-updates.sh`.
- **The code signature is not restorable byte-for-byte.** Editing and re-signing a bundle rewrites it, so `codesign --verify` will complain afterwards. Spotify runs normally, and a Spotify update or reinstall restores the original signature.
- **macOS only.** Windows and Linux enforce this somewhere entirely different; there is no shared fix.
- **Mac App Store builds are not supported.** `install.sh` detects and refuses them.
- **Not notarizable.** You cannot notarize a library whose purpose is injecting into another vendor's app, so distribution will always require the quarantine step.
- Tested against Spotify 1.3.1.234 on macOS (Intel, x86_64). The shim is architecture-independent; the library builds for whatever arch you compile on, and is ad-hoc signed so it loads on Apple Silicon too.

## A note on `Browser.setWindowBounds`

If you're testing this over the Chrome DevTools Protocol: **`Browser.setWindowBounds` still reports a clamp at 800 after the swizzle works.** CEF's implementation goes through Chromium's own `views::Widget` minimum, which the `NSWindow` swizzle doesn't touch. Don't conclude the fix failed from a CDP measurement — check `lsof` for the injected library, and drag the window by hand.

## The CSS companion

[`spicetify/user.css`](spicetify/user.css) removes the web layer's own minimums so the layout reflows instead of clipping, and collapses the search bar and nav rail at narrow widths. Install it as a Spicetify theme. Useful on its own, and required for the narrow layout to look right.

## License

MIT — see [LICENSE](LICENSE).
