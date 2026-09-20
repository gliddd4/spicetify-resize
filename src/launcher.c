/*
 * launcher.c — starts Spotify with the window-minimum-size helper loaded.
 *
 * Spotify's macOS window refuses to go below 800x600. That floor is NSWindow's
 * minimum size, set from compiled code, so no stylesheet can lift it. The fix
 * is src/nomin.m, injected with DYLD_INSERT_LIBRARIES.
 *
 * WHY THIS IS A SEPARATE APP AND NOT A CFBundleExecutable SHIM
 *
 * The obvious approach — drop a launcher inside Spotify.app and point
 * CFBundleExecutable at it — was tried and abandoned. It breaks Spotify's code
 * signature seal, and macOS kills the process at launch:
 *
 *   procPath:    /Applications/Spotify.app/Contents/MacOS/SpotifyLauncher
 *   signal:      SIGKILL (Code Signature Invalid)
 *   termination: CODESIGNING - "Taskgated Invalid Signature"
 *   parentProc:  launchd
 *
 * It survived `open -a` testing for hours, then died on launchd-initiated
 * launches. A compiled and ad-hoc signed shim did not help: the problem is the
 * bundle seal, not the executable's own signature. Editing Spotify.app is not
 * survivable, so this launcher lives outside it and execs an untouched binary.
 *
 * WHY COMPILED AND NOT A SHELL SCRIPT
 *
 * A script cannot carry a code signature, so the launched process has no
 * signing identity at all. This is a Mach-O and is ad-hoc signed by the build,
 * which is enough for taskgated.
 *
 * Failure policy: if the helper is missing, start Spotify anyway. A missing
 * file must never leave the user with an app that will not open.
 *
 * Build: see scripts/build.sh
 */

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef DEFAULT_APP
#define DEFAULT_APP "/Applications/Spotify.app"
#endif

#ifndef LIB_PATH
#define LIB_PATH "/Users/ab/.spotify-resizer/libnomin.dylib"
#endif

int main(int argc, char *argv[]) {
	const char *app = getenv("SPICETIFY_RESIZE_APP");
	if (!app || !*app) {
		app = DEFAULT_APP;
	}

	char target[PATH_MAX];
	int n = snprintf(target, sizeof(target), "%s/Contents/MacOS/Spotify", app);
	if (n < 0 || (size_t)n >= sizeof(target)) {
		fprintf(stderr, "spicetify-resize: path too long\n");
		return 127;
	}

	if (access(target, X_OK) != 0) {
		fprintf(stderr, "spicetify-resize: no Spotify binary at %s\n", target);
		return 127;
	}

	/* Overridable for testing; falls back to the compiled-in default. */
	const char *lib = getenv("SPICETIFY_RESIZE_LIB");
	if (!lib || !*lib) {
		lib = LIB_PATH;
	}

	if (access(lib, F_OK) == 0) {
		setenv("DYLD_INSERT_LIBRARIES", lib, 1);
	} else {
		fprintf(stderr, "spicetify-resize: helper not found at %s, starting Spotify unpatched\n", lib);
	}

	/* Rebuild argv so argv[0] is the real binary, not this launcher. */
	char **nargv = (char **)calloc((size_t)argc + 2, sizeof(char *));
	if (!nargv) {
		return 127;
	}
	nargv[0] = target;
	for (int i = 1; i < argc; i++) {
		nargv[i] = argv[i];
	}
	nargv[argc] = NULL;

	execv(target, nargv);

	fprintf(stderr, "spicetify-resize: execv %s failed: %s\n", target, strerror(errno));
	return 127;
}
