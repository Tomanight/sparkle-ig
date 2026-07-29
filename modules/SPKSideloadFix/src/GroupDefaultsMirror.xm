#import <objc/runtime.h>

#import "Header.h"

// Mirrors the main app's app-group NSUserDefaults writes into the shared
// container that the app extensions read from.
//
// Instagram's notification extension boots by reading its group defaults --
// FBMobileConfigStartupConfigs and friends -- out of the app group container.
// Under sideloading the extension's group suites are redirected to the shared
// container (see _initWithSuiteName:container: in SideloadFix.xm) but the main
// app's are not, so the extension finds an empty plist. Without its startup
// config it stalls, burns the whole 30 second extension budget and is killed
// before it can run:
//
//     Extension will be killed because it used its runtime in starting up
//     Did not mutate content for notification request, will deliver original
//     content; runtime: 30.013551
//
// Two visible consequences: notification content is never mutated (empty
// lock-screen previews), and Instagram's own notification dedupe never runs, so
// a push that the app already delivered over its realtime socket arrives a
// second time as a banner.
//
// Every write still goes to Instagram's own container first (%orig before the
// mirror), so nothing that already worked -- cold-launch dismissal flags in
// particular -- changes behaviour. The mirror is additive.

@interface NSUserDefaults (SPKSideloadPrivate)
- (NSString *)_identifier;
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static const void *kSPKMirrorInstanceKey = &kSPKMirrorInstanceKey;

/// The defaults object writing into the shared container for \c suiteName.
/// Memoized: building one per write would thrash the preferences daemon.
static NSUserDefaults *mirrorDefaultsForSuite(NSString *suiteName) {
	static NSMutableDictionary<NSString *, NSUserDefaults *> *cache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [NSMutableDictionary dictionary];
	});

	@synchronized(cache) {
		NSUserDefaults *existing = cache[suiteName];
		if (existing) {
			return existing;
		}

		NSURL *appGroupURL = getAppGroupPathIfExists();
		if (!appGroupURL) {
			return nil;
		}

		NSURL *containerURL = [appGroupURL URLByAppendingPathComponent:suiteName];
		createDirectoryIfNotExists(containerURL.path);

		NSUserDefaults *mirror = [[NSUserDefaults alloc] _initWithSuiteName:suiteName container:containerURL];
		if (!mirror) {
			return nil;
		}

		// Tag it so the hooks below can recognise their own writes and not
		// recurse back into the mirror.
		objc_setAssociatedObject(mirror, kSPKMirrorInstanceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		cache[suiteName] = mirror;
		SPKSideloadLog(@"Mirroring app group defaults suite=%@ into shared container", suiteName);
		return mirror;
	}
}

/// The mirror target for \c defaults, or nil when this write should be left
/// alone. Extensions already read from the shared container directly, so only
/// the main app mirrors.
static NSUserDefaults *mirrorTargetFor(NSUserDefaults *defaults) {
	if (isAppExtensionProcess()) {
		return nil;
	}
	if (objc_getAssociatedObject(defaults, kSPKMirrorInstanceKey)) {
		return nil;
	}
	if (![defaults respondsToSelector:@selector(_identifier)]) {
		return nil;
	}

	NSString *identifier = [defaults _identifier];
	if (![identifier isKindOfClass:[NSString class]] || ![identifier hasPrefix:@"group"]) {
		return nil;
	}

	return mirrorDefaultsForSuite(identifier);
}

%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setObject:value forKey:key];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setBool:value forKey:key];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setInteger:value forKey:key];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setDouble:value forKey:key];
}

- (void)setFloat:(float)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setFloat:value forKey:key];
}

- (void)setURL:(NSURL *)value forKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) setURL:value forKey:key];
}

- (void)removeObjectForKey:(NSString *)key {
	%orig;
	[mirrorTargetFor(self) removeObjectForKey:key];
}

// KVC path. A nil value here means removal, and forwarding it as-is to
// setValue:forKey: on the mirror would raise instead.
- (void)setValue:(id)value forKey:(NSString *)key {
	%orig;
	NSUserDefaults *mirror = mirrorTargetFor(self);
	if (!mirror) {
		return;
	}
	if (value) {
		[mirror setValue:value forKey:key];
	} else {
		[mirror removeObjectForKey:key];
	}
}

%end
