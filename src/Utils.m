#import "Utils.h"
#import "App/SPKCore.h"
#import "App/SPKStabilityGuard.h"
#import "AssetUtils.h"
#import "Settings/SPKPreferenceAvailability.h"
#import "Settings/SPKPreferences.h"
#import "Shared/Account/SPKAccountManager.h"
#import "Shared/Gallery/SPKGalleryLockViewController.h"
#import "Shared/Gallery/SPKGalleryPaths.h"
#import "Shared/MediaPreview/SPKMediaCacheManager.h"
#import "Shared/Settings/SPKSettingsLockManager.h"
#import "Shared/UI/SPKIGAlertPresenter.h"
#import "Shared/UI/SPKMediaChrome.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString *const kSPKPrefPerAccountSettings = @"general_per_account_settings";

Class SPKReelsVerticalUFIClass(void) {
    // IG 436+ : Swift-mangled name (module + class both "IGSundialViewerVerticalUFI").
    Class cls = objc_getClass("_TtC26IGSundialViewerVerticalUFI26IGSundialViewerVerticalUFI");
    // IG <=435 : class exposed to ObjC under its plain name.
    if (!cls)
        cls = objc_getClass("IGSundialViewerVerticalUFI");
    // Defensive: demangled "Module.Class" form some runtimes report.
    if (!cls)
        cls = objc_getClass("IGSundialViewerVerticalUFI.IGSundialViewerVerticalUFI");
    return cls;
}

Class SPKResolveIGClass(NSString *qualified, NSString *legacy) {
    Class c = Nil;
    if (qualified.length) {
        // NSClassFromString demangles a Swift "Module.Class" spelling (IG 436+).
        c = NSClassFromString(qualified);
        if (!c) {
            // Fall back to building the mangled _TtC<len><Module><len><Class> symbol.
            NSArray<NSString *> *p = [qualified componentsSeparatedByString:@"."];
            if (p.count == 2) {
                NSString *m = p[0], *n = p[1];
                NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@",
                                                               (unsigned long)m.length, m, (unsigned long)n.length, n];
                c = objc_getClass(mangled.UTF8String);
            }
        }
    }
    // IG <=435 : plain ObjC name.
    if (!c && legacy.length)
        c = NSClassFromString(legacy);
    return c;
}

static NSString *SPKTrimmedLogBody(NSString *body) {
    return [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SPKNormalizedLogBody(NSString *category, NSString *body, NSString **outCategory) {
    NSString *resolvedCategory = category.length ? category : @"General";
    NSString *resolvedBody = body ?: @"";
    NSArray<NSDictionary<NSString *, NSString *> *> *legacyPrefixes = @[
        @{@"prefix" : @"[Sparkle][startup]", @"category" : @"Startup"},
        @{@"prefix" : @"[Sparkle Gallery]", @"category" : @"Gallery"},
        @{@"prefix" : @"[Sparkle BulkDownload]", @"category" : @"BulkDownload"},
        @{@"prefix" : @"[Sparkle]", @"category" : resolvedCategory},
    ];

    for (NSDictionary<NSString *, NSString *> *entry in legacyPrefixes) {
        NSString *prefix = entry[@"prefix"];
        if ([resolvedBody hasPrefix:prefix]) {
            resolvedCategory = entry[@"category"] ?: resolvedCategory;
            resolvedBody = SPKTrimmedLogBody([resolvedBody substringFromIndex:prefix.length]);
            break;
        }
    }

    if (outCategory) {
        *outCategory = resolvedCategory;
    }
    return resolvedBody;
}

void SPKLogMessage(NSString *category, os_log_type_t type, NSString *format, ...) {
    NSString *body = @"";
    if (format.length > 0) {
        va_list args;
        va_start(args, format);
        body = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
    }

    NSString *resolvedCategory = nil;
    NSString *resolvedBody = SPKNormalizedLogBody(category, body ?: @"", &resolvedCategory);
    NSString *line = [NSString stringWithFormat:@"[Sparkle %@]: %@", resolvedCategory ?: @"General", resolvedBody ?: @""];
    os_log_with_type(OS_LOG_DEFAULT, type, "%{public}s", line.UTF8String);
}

static NSNumber *SPKNumericValueForSelector(id target, NSString *selectorName) {
    if (!target || !selectorName.length)
        return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector])
        return nil;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    if (!returnType || !returnType[0])
        return nil;

    switch (returnType[0]) {
    case '@': {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        if ([value respondsToSelector:@selector(doubleValue)]) {
            return @([value doubleValue]);
        }
        if ([value respondsToSelector:@selector(integerValue)]) {
            return @(((NSInteger (*)(id, SEL))objc_msgSend)(value, @selector(integerValue)));
        }
        return nil;
    }
    case 'd':
        return @(((double (*)(id, SEL))objc_msgSend)(target, selector));
    case 'f':
        return @((double)((float (*)(id, SEL))objc_msgSend)(target, selector));
    case 'q':
        return @((double)((long long (*)(id, SEL))objc_msgSend)(target, selector));
    case 'Q':
        return @((double)((unsigned long long (*)(id, SEL))objc_msgSend)(target, selector));
    case 'i':
        return @((double)((int (*)(id, SEL))objc_msgSend)(target, selector));
    case 'I':
        return @((double)((unsigned int (*)(id, SEL))objc_msgSend)(target, selector));
    case 'l':
        return @((double)((long (*)(id, SEL))objc_msgSend)(target, selector));
    case 'L':
        return @((double)((unsigned long (*)(id, SEL))objc_msgSend)(target, selector));
    case 's':
        return @((double)((short (*)(id, SEL))objc_msgSend)(target, selector));
    case 'S':
        return @((double)((unsigned short (*)(id, SEL))objc_msgSend)(target, selector));
    case 'c':
        return @((double)((char (*)(id, SEL))objc_msgSend)(target, selector));
    case 'C':
        return @((double)((unsigned char (*)(id, SEL))objc_msgSend)(target, selector));
    case 'B':
        return @((double)((BOOL (*)(id, SEL))objc_msgSend)(target, selector));
    default:
        return nil;
    }
}

static id SPKObjectForSelector(id target, NSString *selectorName) {
    if (!target || !selectorName.length)
        return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id SPKKVCObject(id target, NSString *key) {
    if (!target || !key.length)
        return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSURL *SPKURLFromStringOrURL(id value) {
    if (!value)
        return nil;

    if ([value isKindOfClass:[NSURL class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return [NSURL URLWithString:(NSString *)value];
    }

    return nil;
}

static double SPKDoubleValue(id value) {
    if (!value)
        return 0.0;

    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }

    return 0.0;
}

static NSInteger SPKIntegerValue(id value) {
    if (!value)
        return 0;

    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }

    return 0;
}

static NSArray *SPKArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return collection;
    }

    if ([collection isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)collection array];
    }

    if ([collection isKindOfClass:[NSSet class]]) {
        return [(NSSet *)collection allObjects];
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in collection) {
            [items addObject:item];
        }
        return items;
    }

    return nil;
}

static NSString *const kSPKCacheAutoClearModeKey = @"general_cache_auto_clear";
static NSString *const kSPKCacheLastClearedAtKey = @"general_cache_last_cleared_at";

static UIColor *SPKDynamicInstagramColor(CGFloat lightRed,
                                         CGFloat lightGreen,
                                         CGFloat lightBlue,
                                         CGFloat darkRed,
                                         CGFloat darkGreen,
                                         CGFloat darkBlue) {
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *_Nonnull traitCollection) {
        BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        CGFloat red = dark ? darkRed : lightRed;
        CGFloat green = dark ? darkGreen : lightGreen;
        CGFloat blue = dark ? darkBlue : lightBlue;
        return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
    }];
}

static UIColor *SPKInstagramColorFromClassSelector(NSString *className, SEL selector) {
    Class colorClass = NSClassFromString(className);
    if (!colorClass || ![colorClass respondsToSelector:selector])
        return nil;

    id color = ((id (*)(id, SEL))objc_msgSend)(colorClass, selector);
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

static UIColor *SPKInstagramPrimaryAccentColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *_Nonnull traitCollection) {
        if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithRed:0.408 green:0.557 blue:1.032 alpha:1.0];
        } else {
            return [UIColor colorWithRed:0.270 green:0.367 blue:1.013 alpha:1.0];
        }
    }];
}

static UIColor *SPKInstagramDestructiveColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *_Nonnull traitCollection) {
        if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithRed:0.957 green:0.357 blue:0.420 alpha:1.0];
        } else {
            return [UIColor colorWithRed:0.867 green:0.082 blue:0.208 alpha:1.0];
        }
    }];
}

static NSArray *SPKImageVersionsFromPhoto(IGPhoto *photo) {
    if (!photo)
        return nil;

    NSArray *versions = SPKArrayFromCollection(SPKObjectForSelector(photo, @"imageVersions"));
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection([SPKUtils getIvarForObj:photo name:"_originalImageVersions"]);
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection(SPKObjectForSelector(photo, @"imageVersionDictionaries"));
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection([SPKUtils getIvarForObj:photo name:"_imageVersions"]);
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection([SPKUtils getIvarForObj:photo name:"_imageVersionDictionaries"]);
    return versions.count > 0 ? versions : nil;
}

static NSArray *SPKVideoVersionsFromVideo(IGVideo *video) {
    if (!video)
        return nil;

    NSArray *versions = SPKArrayFromCollection(SPKObjectForSelector(video, @"videoVersions"));
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection(SPKObjectForSelector(video, @"videoVersionDictionaries"));
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection([SPKUtils getIvarForObj:video name:"_videoVersions"]);
    if (versions.count > 0)
        return versions;

    versions = SPKArrayFromCollection([SPKUtils getIvarForObj:video name:"_videoVersionDictionaries"]);
    return versions.count > 0 ? versions : nil;
}

static NSArray<NSDictionary *> *SPKSortedMediaVariantsFromVersions(NSArray *versions) {
    if (![versions isKindOfClass:[NSArray class]] || versions.count == 0) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
    NSMutableSet<NSString *> *seenURLs = [NSMutableSet set];

    for (id version in versions) {
        id rawURL = nil;
        id widthValue = nil;
        id heightValue = nil;
        id bandwidthValue = nil;

        if ([version isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)version;
            rawURL = dict[@"url"] ?: dict[@"urlString"];
            widthValue = dict[@"width"];
            heightValue = dict[@"height"];
            bandwidthValue = dict[@"bandwidth"];
        } else {
            rawURL = SPKObjectForSelector(version, @"url");
            if (!rawURL) {
                rawURL = SPKObjectForSelector(version, @"urlString");
            }
            widthValue = SPKNumericValueForSelector(version, @"width");
            heightValue = SPKNumericValueForSelector(version, @"height");
            bandwidthValue = SPKNumericValueForSelector(version, @"bandwidth");
        }

        NSURL *url = SPKURLFromStringOrURL(rawURL);
        if (!url)
            continue;

        NSString *absolute = url.absoluteString;
        if (absolute.length == 0 || [seenURLs containsObject:absolute]) {
            continue;
        }
        [seenURLs addObject:absolute];

        [variants addObject:@{
            @"url" : url,
            @"width" : @(SPKDoubleValue(widthValue)),
            @"height" : @(SPKDoubleValue(heightValue)),
            @"bandwidth" : @(SPKIntegerValue(bandwidthValue))
        }];
    }

    [variants sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        double lhsArea = [lhs[@"width"] doubleValue] * [lhs[@"height"] doubleValue];
        double rhsArea = [rhs[@"width"] doubleValue] * [rhs[@"height"] doubleValue];

        if (lhsArea > rhsArea)
            return NSOrderedAscending;
        if (lhsArea < rhsArea)
            return NSOrderedDescending;

        NSInteger lhsBandwidth = [lhs[@"bandwidth"] integerValue];
        NSInteger rhsBandwidth = [rhs[@"bandwidth"] integerValue];
        if (lhsBandwidth > rhsBandwidth)
            return NSOrderedAscending;
        if (lhsBandwidth < rhsBandwidth)
            return NSOrderedDescending;

        return NSOrderedSame;
    }];

    return variants;
}

static NSURL *SPKHighestQualityURLFromVersions(NSArray *versions) {
    NSArray<NSDictionary *> *variants = SPKSortedMediaVariantsFromVersions(versions);
    if (variants.count == 0)
        return nil;

    id value = variants.firstObject[@"url"];
    return [value isKindOfClass:[NSURL class]] ? value : nil;
}

static NSURL *SPKURLFromVideoURLCollection(id collection) {
    if (!collection)
        return nil;

    NSArray *items = SPKArrayFromCollection(collection);

    if (!items) {
        return SPKURLFromStringOrURL(collection);
    }

    for (id item in items) {
        NSURL *url = nil;

        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)item;
            url = SPKURLFromStringOrURL(dict[@"url"] ?: dict[@"urlString"]);
        } else {
            url = SPKURLFromStringOrURL(item);
        }

        if (url)
            return url;
    }

    return nil;
}

static NSURL *SPKProfilePictureURLFromInfo(id info) {
    if (!info)
        return nil;

    NSURL *url = SPKURLFromStringOrURL(SPKObjectForSelector(info, @"url"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(info, @"urlString"));
    if (url)
        return url;

    if ([info isKindOfClass:[NSDictionary class]]) {
        NSDictionary *infoDictionary = (NSDictionary *)info;
        url = SPKURLFromStringOrURL(infoDictionary[@"url"] ?: infoDictionary[@"urlString"]);
        if (url)
            return url;
    }

    return nil;
}

static NSURL *SPKHDProfilePicURL(id user) {
    if (!user)
        return nil;

    NSURL *url = SPKProfilePictureURLFromInfo(SPKObjectForSelector(user, @"hdProfilePicUrlInfo"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"HDProfilePicURL"));
    if (url)
        return url;

    url = SPKProfilePictureURLFromInfo(SPKObjectForSelector(user, @"_private_hdProfilePicUrlInfo"));
    if (url)
        return url;

    url = SPKProfilePictureURLFromInfo(SPKObjectForSelector(user, @"HDProfilePicURLInfo"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"profile_pic_url_hd"));
    if (url)
        return url;

    return SPKURLFromStringOrURL(SPKKVCObject(user, @"profile_pic_url_hd"));
}

static NSURL *SPKThumbProfilePicURL(id user) {
    if (!user)
        return nil;

    NSURL *url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"derivedProfilePicURL"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"profilePicURLString"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"profilePicURL"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"_private_profilePicURLString"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"_private_profilePicUrl"));
    if (url)
        return url;

    url = SPKURLFromStringOrURL(SPKObjectForSelector(user, @"profile_pic_url"));
    if (url)
        return url;

    return SPKURLFromStringOrURL(SPKKVCObject(user, @"profile_pic_url"));
}

static BOOL SPKInstagramHostMatchesCanonical(NSString *host) {
    if (host.length == 0)
        return NO;
    NSString *lower = host.lowercaseString;
    return [lower isEqualToString:@"instagram.com"] || [lower isEqualToString:@"www.instagram.com"] || [lower isEqualToString:@"instagr.am"] || [lower hasSuffix:@".instagram.com"];
}

static BOOL SPKInstagramPathUsesSharePrefix(NSArray<NSString *> *segments) {
    if (segments.count < 2)
        return NO;
    NSString *candidate = segments[1].lowercaseString;
    return [candidate isEqualToString:@"p"] || [candidate isEqualToString:@"reel"] || [candidate isEqualToString:@"reels"] || [candidate isEqualToString:@"tv"];
}

static NSArray<NSString *> *SPKSanitizedInstagramPathSegments(NSArray<NSString *> *segments) {
    if (segments.count >= 3 && SPKInstagramPathUsesSharePrefix(segments)) {
        return [segments subarrayWithRange:NSMakeRange(1, segments.count - 1)];
    }
    return segments;
}

static NSArray<NSURLQueryItem *> *SPKSanitizedInstagramQueryItems(NSArray<NSURLQueryItem *> *items) {
    if (items.count == 0)
        return nil;

    static NSSet<NSString *> *blockedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedKeys = [NSSet setWithArray:@[
            @"igsh", @"igshid", @"ig_rid", @"ig_mid",
            @"utm_source", @"utm_medium", @"utm_campaign", @"utm_term", @"utm_content",
            @"fbclid"
        ]];
    });

    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        if (![blockedKeys containsObject:item.name.lowercaseString]) {
            [kept addObject:item];
        }
    }
    return kept.count > 0 ? kept : nil;
}

@interface SPKSettingsNavigationController : SPKChromeNavigationController
@end

@implementation SPKSettingsNavigationController

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.presentingViewController == nil) {
        [[SPKSettingsLockManager sharedManager] lockSettings];
    }
}

@end

static void SPKPresentSettingsAfterUnlock(UIViewController *presenter, dispatch_block_t presentation) {
    SPKSettingsLockManager *manager = [SPKSettingsLockManager sharedManager];
    if (manager.isLockEnabled && !manager.isUnlocked) {
        [SPKGalleryLockViewController presentUnlockForManager:manager
                                           fromViewController:presenter
                                                   completion:^(BOOL success) {
                                                       if (success && presentation)
                                                           presentation();
                                                   }];
        return;
    }
    if (presentation)
        presentation();
}

@implementation SPKUtils

// Master kill switch overlay: when "Disable All Settings" is on, runtime
// reads of feature prefs return the registered default instead of the user's
// stored value. The toggles themselves still display the saved state because
// the settings UI reads NSUserDefaults directly (boolForKey:), not these
// accessors.
//
// A handful of keys must bypass the overlay so the kill switch and the
// settings shortcut keep working. They're enumerated here.
static NSSet<NSString *> *SPKMasterDisableBypassKeys(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"tools_disable_all",
            @"tools_settings_shortcut",
            @"gallery_quick_access_tab",
            @"tools_open_settings_on_launch",
            @"app_first_run",
        ]];
    });
    return keys;
}

static BOOL SPKMasterDisableActive(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"tools_disable_all"];
}

#pragma mark - Per-account preference namespacing

// Read directly (never through the namespacing accessors) to avoid recursion;
// the toggle itself is global.
static BOOL SPKPrefPerAccountEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSPKPrefPerAccountSettings];
}

// Keys that must never be per-account: physically single (app icon), device/app
// wide (master kill switch, safe mode), appearance/Liquid Glass, download
// encoding params, and all gallery view/lock/folder prefs.
static BOOL SPKPrefIsGlobalKey(NSString *key) {
    static NSSet<NSString *> *globalExact;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        globalExact = [NSSet setWithArray:@[
            kSPKPrefPerAccountSettings,
            @"general_app_icon_identifier",
            @"tools_disable_all",
            // Notification delivery is install-wide, not per-account.
            @"tools_fix_duplicate_notifications",
            @"tools_notification_log",
            @"app_first_run",
            @"app_safe_startup",
            @"app_startup_profiling",
            @"interface_liquid_glass",
            @"interface_liquid_glass_tabbar_mode",
            @"interface_progressive_blur",
            @"downloads_adv_encoding",
            // Tab/launch layout is configured once at launch and can't re-apply
            // on a live account switch, so it stays global (maintainer's call).
            @"interface_nav_order",
            @"interface_swipe_tabs",
            @"interface_launch_tab",
            // The Settings quick-access long-press is attached to tab-bar buttons
            // as they're built during early launch — before the account session
            // resolves — so a per-account effective key resolves against the
            // wrong PK and the gesture sticks to whatever account owned the bar at
            // launch. Kept global so it's reliable and matches the (global)
            // gallery quick-access shortcut.
            @"tools_settings_shortcut",
            // Suppressing the TestFlight popup runs early in %ctor before the account
            // session resolves, and is inherently an application/install-wide setting.
            @"tools_hide_testflight_popup",
            // Main feed mode (For You / Following) is read during early feed
            // setup before the account resolves, so it stays global.
            @"feed_mode",
            // The feed playback strategy is created during early launch, before
            // the account session resolves (currentUserPK == nil), so a
            // per-account effective key would resolve against the wrong PK and
            // miss the value. Read the plain global key — no session dependency.
            @"feed_disable_autoplay",
            // Reels doom scroll and limits are application-wide behavioral controls,
            // and must resolve early/reliably regardless of account session state.
            @"reels_prevent_doom_scroll",
            @"reels_doom_scroll_limit",
            @"reels_disable_scrolling",
        ]];
    });
    if ([globalExact containsObject:key])
        return YES;
    if ([key hasPrefix:@"downloads_encoding_"])
        return YES;
    if ([key hasPrefix:@"gallery_"])
        return YES;
    // interface_hide_*_tab (tab layout) + interface_hide_ui_on_capture.
    if ([key hasPrefix:@"interface_hide_"])
        return YES;
    return NO;
}

BOOL SPKPerAccountModeActive(void) {
    return SPKPrefPerAccountEnabled() && [SPKAccountManager currentAccountPK].length > 0;
}

BOOL SPKPreferenceKeyIsGlobal(NSString *key) {
    return SPKPrefIsGlobalKey(key);
}

NSString *SPKEffectivePreferenceKey(NSString *key) {
    if (key.length == 0)
        return key;
    if (!SPKPrefPerAccountEnabled())
        return key;
    if (SPKPrefIsGlobalKey(key))
        return key;
    // Use the best-effort namespace PK: during the early-launch window the live
    // session isn't resolved yet (currentAccountPK == nil), so this falls back
    // to the last-active account from the roster. Without it, hooks that fire
    // early (e.g. feed autoplay strategy creation) read the global default
    // instead of the per-account value the user actually set.
    NSString *pk = [SPKAccountManager preferenceNamespacePK];
    if (pk.length == 0)
        return key; // no known account → use global
    return [NSString stringWithFormat:@"u_%@_%@", pk, key];
}

// Namespaced direct-defaults access for callers that read/write NSUserDefaults
// outside the SPKUtils getXPref accessors (action-button config, manual-seen
// list, etc.). Mirrors the accessor's per-account → global inheritance.
id SPKPreferenceObjectForKey(NSString *key) {
    if (key.length == 0)
        return nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *effectiveKey = SPKEffectivePreferenceKey(key);
    if (![effectiveKey isEqualToString:key]) {
        id perAccountValue = [defaults objectForKey:effectiveKey];
        if (perAccountValue != nil)
            return perAccountValue;
    }
    return [defaults objectForKey:key];
}

void SPKPreferenceSetObject(id value, NSString *key) {
    if (key.length == 0)
        return;
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:SPKEffectivePreferenceKey(key)];
}

static id SPKPrefValueWithMasterOverlay(NSString *key) {
    if (key.length == 0)
        return nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (SPKMasterDisableActive() && ![SPKMasterDisableBypassKeys() containsObject:key]) {
        return SPKCoreRegisteredDefaults()[key];
    }
    NSString *effectiveKey = SPKEffectivePreferenceKey(key);
    if (![effectiveKey isEqualToString:key]) {
        id perAccountValue = [defaults objectForKey:effectiveKey];
        // Inherit the global value (and its registered default) until this
        // account overrides the key.
        if (perAccountValue != nil)
            return perAccountValue;
    }
    return [defaults objectForKey:key];
}

+ (BOOL)getBoolPref:(NSString *)key {
    if (![key length])
        return NO;
    if (!SPKPrefIsAvailable(key))
        return NO;
    id value = SPKPrefValueWithMasterOverlay(key);
    if ([value respondsToSelector:@selector(boolValue)])
        return [value boolValue];
    return NO;
}
+ (double)getDoublePref:(NSString *)key {
    if (![key length])
        return 0;
    id value = SPKPrefValueWithMasterOverlay(key);
    if ([value respondsToSelector:@selector(doubleValue)])
        return [value doubleValue];
    return 0;
}
+ (NSString *)getStringPref:(NSString *)key {
    if (![key length])
        return @"";
    id value = SPKPrefValueWithMasterOverlay(key);
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

// MARK: Misc
+ (BOOL)tabOrderSetTo:(NSString *)ordering {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"interface_nav_order"] isEqualToString:ordering];
};

+ (NSString *)IGVersionString {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
};

+ (_Bool)spk_liquidGlassLauncherPrefKey:(NSString *)key orig:(_Bool)fallback {
    return [SPKUtils spk_isLiquidGlassEffectivelyEnabled] ? YES : fallback;
}

+ (BOOL)spk_isLiquidGlassEffectivelyEnabled {
    return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass] &&
           !SPKStabilityGuardIsSafeStartupMode();
}

// MARK: Session / user
+ (id)activeUserSession {
    @try {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                id session = nil;
                @try {
                    if ([window respondsToSelector:@selector(userSession)]) {
                        session = [window valueForKey:@"userSession"];
                    }
                } @catch (__unused NSException *e) {
                }
                if (session)
                    return session;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

+ (NSString *)pkFromIGUser:(id)user {
    if (!user)
        return nil;
    // Prefer the public accessor — robust even when the backing ivar is renamed
    // or absent (Swift-bridged classes). IGUser exposes `pk` as a readonly
    // property; the raw `_pk` ivar isn't reliable across IG versions.
    @try {
        if ([user respondsToSelector:@selector(pk)]) {
            id pk = ((id (*)(id, SEL))objc_msgSend)(user, @selector(pk));
            if ([pk isKindOfClass:[NSString class]] && [(NSString *)pk length])
                return pk;
            if ([pk respondsToSelector:@selector(stringValue)]) {
                NSString *s = [pk stringValue];
                if (s.length)
                    return s;
            }
            if (pk) {
                NSString *d = [pk description];
                if (d.length)
                    return d;
            }
        }
    } @catch (__unused NSException *e) {
    }

    // Fallback: read the _pk ivar directly.
    Ivar pkIvar = NULL;
    for (Class cls = [user class]; cls && !pkIvar; cls = class_getSuperclass(cls)) {
        pkIvar = class_getInstanceVariable(cls, "_pk");
    }
    if (!pkIvar)
        return nil;
    @try {
        id pk = object_getIvar(user, pkIvar);
        if ([pk isKindOfClass:[NSString class]] && [(NSString *)pk length])
            return pk;
        if (pk)
            return [pk description];
    } @catch (__unused NSException *e) {
    }
    return nil;
}

+ (NSString *)currentUserPK {
    id session = [self activeUserSession];
    if (!session)
        return nil;
    @try {
        id user = [session valueForKey:@"user"];
        return [self pkFromIGUser:user];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

+ (NSDictionary<NSString *, NSString *> *)currentUserIdentity {
    id session = [self activeUserSession];
    if (!session)
        return nil;
    id user = nil;
    @try {
        user = [session valueForKey:@"user"];
    } @catch (__unused NSException *e) {
    }
    if (!user)
        return nil;

    NSMutableDictionary<NSString *, NSString *> *info = [NSMutableDictionary dictionary];
    NSString *pk = [self pkFromIGUser:user];
    if (pk.length)
        info[@"pk"] = pk;

    id username = SPKObjectForSelector(user, @"username");
    if ([username isKindOfClass:[NSString class]] && [(NSString *)username length])
        info[@"username"] = username;

    id fullName = SPKObjectForSelector(user, @"fullName");
    if (![fullName isKindOfClass:[NSString class]] || ![(NSString *)fullName length])
        fullName = SPKObjectForSelector(user, @"full_name");
    if ([fullName isKindOfClass:[NSString class]] && [(NSString *)fullName length])
        info[@"full_name"] = fullName;

    NSURL *picURL = [self getBestProfilePictureURLForUser:user];
    if (picURL.absoluteString.length)
        info[@"profile_pic_url"] = picURL.absoluteString;

    return info.count ? info : nil;
}

+ (void)cleanCache {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSError *> *deletionErrors = [NSMutableArray array];

    // Temp folder
    // * disabled bc app crashed trying to delete certain files inside it
    // todo: remove the above disclaimer if this new code doesn't cause crashing
    NSArray *tempFolderContents = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in tempFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError)
            [deletionErrors addObject:cacheItemDeletionError];
    }

    // Analytics folder
    NSString *analyticsFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"];
    NSArray *analyticsFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:analyticsFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in analyticsFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError)
            [deletionErrors addObject:cacheItemDeletionError];
    }

    // Caches folder
    NSString *cachesFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Caches"];
    NSArray *cachesFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:cachesFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in cachesFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError)
            [deletionErrors addObject:cacheItemDeletionError];
    }

    NSURL *previewCacheURL = [[[SPKMediaCacheManager sharedManager] valueForKey:@"cacheRootURL"] copy];
    if (previewCacheURL) {
        NSError *previewCacheDeletionError = nil;
        [fileManager removeItemAtURL:previewCacheURL error:&previewCacheDeletionError];
        if (previewCacheDeletionError)
            [deletionErrors addObject:previewCacheDeletionError];
    }

    // Log errors
    if (deletionErrors.count > 1) {

        for (NSError *error in deletionErrors) {
            SPKLog(@"General", @"[Sparkle] File Deletion Error: %@", error);
        }
    }

    [SPKUtils markCacheClearedNow];
}

+ (unsigned long long)cleanCacheReturningFreedBytes {
    unsigned long long bytesBefore = [self cacheSizeBytes];
    [self cleanCache];
    unsigned long long bytesAfter = [self cacheSizeBytes];
    return bytesBefore > bytesAfter ? bytesBefore - bytesAfter : 0;
}

+ (unsigned long long)cacheSizeBytes {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *libraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSArray<NSURL *> *folders = @[
        [NSURL fileURLWithPath:NSTemporaryDirectory()
                   isDirectory:YES],
        [NSURL fileURLWithPath:[libraryFolder stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"]
                   isDirectory:YES],
        [NSURL fileURLWithPath:[libraryFolder stringByAppendingPathComponent:@"Caches"]
                   isDirectory:YES]
    ];
    NSArray<NSURLResourceKey> *resourceKeys = @[ NSURLIsRegularFileKey, NSURLFileSizeKey ];
    unsigned long long totalBytes = 0;

    for (NSURL *folderURL in folders) {
        NSArray<NSURL *> *folderContents = [fileManager contentsOfDirectoryAtURL:folderURL
                                                      includingPropertiesForKeys:resourceKeys
                                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                           error:nil];
        for (NSURL *itemURL in folderContents) {
            NSDictionary<NSURLResourceKey, id> *values = [itemURL resourceValuesForKeys:resourceKeys error:nil];
            if ([values[NSURLIsRegularFileKey] boolValue]) {
                totalBytes += [values[NSURLFileSizeKey] unsignedLongLongValue];
            }

            NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:itemURL
                                                           includingPropertiesForKeys:resourceKeys
                                                                              options:0
                                                                         errorHandler:nil];
            for (NSURL *fileURL in enumerator) {
                values = [fileURL resourceValuesForKeys:resourceKeys error:nil];
                if ([values[NSURLIsRegularFileKey] boolValue]) {
                    totalBytes += [values[NSURLFileSizeKey] unsignedLongLongValue];
                }
            }
        }
    }

    return totalBytes;
}

+ (NSString *)formattedCacheSize {
    return [NSByteCountFormatter stringFromByteCount:(long long)[self cacheSizeBytes]
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

+ (NSString *)spk_localizedTimeComponent {
    // `j` resolves to whichever hour cycle the locale/device prefers; if the
    // resolved template keeps the AM/PM designator ("a") we're on a 12-hour
    // clock, otherwise the device is set to 24-hour time.
    NSString *resolved = [NSDateFormatter dateFormatFromTemplate:@"jmm"
                                                         options:0
                                                          locale:[NSLocale currentLocale]];
    BOOL is24Hour = !resolved || [resolved rangeOfString:@"a"].location == NSNotFound;
    return is24Hour ? @"HH:mm" : @"h:mm a";
}

+ (NSString *)spk_localizedDateComponentIncludingYear:(BOOL)includeYear {
    NSString *template = includeYear ? @"yMMMd" : @"MMMd";
    NSString *resolved = [NSDateFormatter dateFormatFromTemplate:template
                                                         options:0
                                                          locale:[NSLocale currentLocale]];
    if (resolved.length)
        return resolved;
    return includeYear ? @"MMM d, yyyy" : @"MMM d";  // safe fallback
}

static double SPKTimestampFromValue(id value) {
    if (!value || [value isKindOfClass:[NSNull class]])
        return 0.0;
    if ([value isKindOfClass:[NSDate class]])
        return [(NSDate *)value timeIntervalSince1970];

    double raw = 0.0;
    if ([value respondsToSelector:@selector(doubleValue)]) {
        raw = [value doubleValue];
    }
    if (raw <= 0.0)
        return 0.0;
    if (raw > 1e15)
        raw /= 1000000.0;
    else if (raw > 1e12)
        raw /= 1000.0;
    return raw;
}

static NSDate *SPKDateFromTimestampValue(id value) {
    NSTimeInterval timestamp = SPKTimestampFromValue(value);
    if (timestamp <= 0.0)
        return nil;
    return [NSDate dateWithTimeIntervalSince1970:timestamp];
}

static id SPKFieldCacheValue(id target, NSString *key) {
    if (!target || key.length == 0)
        return nil;
    id fieldCache = SPKKVCObject(target, @"_fieldCache");
    if ([fieldCache isKindOfClass:[NSDictionary class]]) {
        return fieldCache[key];
    }
    return nil;
}

static NSDate *SPKRecursiveDateForKeys(id target, NSArray<NSString *> *keys, NSInteger depth) {
    if (!target || depth > 3)
        return nil;

    for (NSString *key in keys) {
        id value = SPKObjectForSelector(target, key);
        if (!value)
            value = SPKKVCObject(target, key);
        if (!value)
            value = SPKFieldCacheValue(target, key);
        NSDate *date = SPKDateFromTimestampValue(value);
        if (date)
            return date;
    }

    for (NSString *selectorName in @[ @"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post" ]) {
        id nested = SPKObjectForSelector(target, selectorName);
        if (!nested)
            nested = SPKKVCObject(target, selectorName);
        if (!nested || nested == target)
            continue;
        NSDate *date = SPKRecursiveDateForKeys(nested, keys, depth + 1);
        if (date)
            return date;
    }

    return nil;
}

+ (nullable NSDate *)postedDateFromMediaObject:(nullable id)media {
    if (!media)
        return nil;

    id backingMedia = SPKObjectForSelector(media, @"backingMedia");
    if (!backingMedia)
        backingMedia = SPKKVCObject(media, @"backingMedia");
    if (backingMedia && backingMedia != media)
        media = backingMedia;

    return SPKRecursiveDateForKeys(media, @[ @"taken_at", @"takenAt", @"takenAtDate", @"device_timestamp", @"deviceTimestamp", @"created_at", @"createdAt", @"upload_time", @"uploadTime", @"published_time", @"publishedTime" ], 0);
}

+ (nullable NSString *)spk_formattedDateHeader:(nullable NSDate *)date {
    if (!date)
        return nil;
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
    });
    fmt.dateFormat = [NSString stringWithFormat:@"%@ 'at' %@",
                      [SPKUtils spk_localizedDateComponentIncludingYear:YES],
                      [SPKUtils spk_localizedTimeComponent]];
    return [fmt stringFromDate:date];
}


+ (NSString *)cacheAutoClearMode {
    NSString *mode = [SPKUtils getStringPref:kSPKCacheAutoClearModeKey];
    return mode.length > 0 ? mode : @"never";
}

+ (BOOL)shouldAutomaticallyClearCacheNow {
    NSString *mode = [self cacheAutoClearMode];
    if ([mode isEqualToString:@"never"])
        return NO;
    if ([mode isEqualToString:@"always"])
        return YES;

    NSDate *lastClearedAt = [[NSUserDefaults standardUserDefaults] objectForKey:kSPKCacheLastClearedAtKey];
    if (![lastClearedAt isKindOfClass:[NSDate class]])
        return YES;

    NSTimeInterval interval = 0.0;
    if ([mode isEqualToString:@"daily"])
        interval = 24.0 * 60.0 * 60.0;
    else if ([mode isEqualToString:@"weekly"])
        interval = 7.0 * 24.0 * 60.0 * 60.0;
    else if ([mode isEqualToString:@"monthly"])
        interval = 30.0 * 24.0 * 60.0 * 60.0;
    else
        return NO;

    return [[NSDate date] timeIntervalSinceDate:lastClearedAt] >= interval;
}

+ (void)markCacheClearedNow {
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kSPKCacheLastClearedAtKey];
}

+ (void)evaluateAutomaticCacheClearIfNeeded {
    if (![self shouldAutomaticallyClearCacheNow])
        return;
    SPKLog(@"General", @"[Sparkle] Automatically clearing cache...");
    [self cleanCache];
}

// MARK: Display View Controllers
+ (void)showShareVC:(id)item {
    UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[ item ] applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect = CGRectMake(topMostController().view.bounds.size.width / 2.0, topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:true completion:nil];
}
+ (void)showSettingsVC:(UIWindow *)window {
    UIViewController *rootController = [window rootViewController];
    SPKPresentSettingsAfterUnlock(rootController, ^{
        SPKSettingsViewController *settingsViewController = [SPKSettingsViewController new];
        UINavigationController *navigationController = [[SPKSettingsNavigationController alloc] initWithRootViewController:settingsViewController];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [rootController presentViewController:navigationController animated:YES completion:nil];
    });
}

+ (void)showSettingsForTopicTitle:(NSString *)title {
    NSArray *rootSections = [SPKTweakSettings sections];
    SPKSetting *matchedRow = nil;
    for (NSDictionary *section in rootSections) {
        NSArray *rows = section[@"rows"];
        for (SPKSetting *row in rows) {
            if (![row isKindOfClass:[SPKSetting class]])
                continue;
            if ([row.title isEqualToString:title]) {
                matchedRow = row;
                break;
            }
        }
        if (matchedRow)
            break;
    }

    UIViewController *settingsViewController = nil;
    if (matchedRow) {
        if (matchedRow.navViewController) {
            settingsViewController = matchedRow.navViewController;
        } else if (matchedRow.navSections.count > 0) {
            settingsViewController = [[SPKSettingsViewController alloc] initWithTitle:title sections:matchedRow.navSections reduceMargin:NO];
            settingsViewController.title = title;
        }
    }

    if (!settingsViewController) {
        settingsViewController = [SPKSettingsViewController new];
    }

    UIViewController *presenter = topMostController();
    SPKPresentSettingsAfterUnlock(presenter, ^{
        UINavigationController *navigationController = [[SPKSettingsNavigationController alloc] initWithRootViewController:settingsViewController];
        navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
        UIUserInterfaceStyle interfaceStyle = presenter.view.window.traitCollection.userInterfaceStyle;
        if (interfaceStyle == UIUserInterfaceStyleUnspecified) {
            interfaceStyle = presenter.traitCollection.userInterfaceStyle;
        }
        if (interfaceStyle != UIUserInterfaceStyleUnspecified) {
            navigationController.overrideUserInterfaceStyle = interfaceStyle;
            settingsViewController.overrideUserInterfaceStyle = interfaceStyle;
        }
        UISheetPresentationController *sheet = navigationController.sheetPresentationController;
        sheet.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;

        [presenter presentViewController:navigationController animated:YES completion:nil];
    });
}

+ (void)presentViewControllerInSheet:(UIViewController *)vc {
    if (!vc)
        return;
    UIViewController *presenter = topMostController();
    SPKPresentSettingsAfterUnlock(presenter, ^{
        UINavigationController *navigationController = [[SPKSettingsNavigationController alloc] initWithRootViewController:vc];
        navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
        UIUserInterfaceStyle interfaceStyle = presenter.view.window.traitCollection.userInterfaceStyle;
        if (interfaceStyle == UIUserInterfaceStyleUnspecified) {
            interfaceStyle = presenter.traitCollection.userInterfaceStyle;
        }
        if (interfaceStyle != UIUserInterfaceStyleUnspecified) {
            navigationController.overrideUserInterfaceStyle = interfaceStyle;
            vc.overrideUserInterfaceStyle = interfaceStyle;
        }
        UISheetPresentationController *sheet = navigationController.sheetPresentationController;
        sheet.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;

        [presenter presentViewController:navigationController animated:YES completion:nil];
    });
}

// MARK: Colours
+ (UIColor *)SPKColor_InstagramBlue {
    return SPKInstagramPrimaryAccentColor();
}

+ (UIColor *)SPKColor_InstagramBackground {
    return SPKDynamicInstagramColor(255.0, 255.0, 255.0, 11.0, 16.0, 20.0);
}

+ (UIColor *)SPKColor_InstagramSecondaryBackground {
    return SPKDynamicInstagramColor(240.0, 241.0, 245.0, 42.0, 48.0, 55.0);
}

+ (UIColor *)SPKColor_InstagramTertiaryBackground {
    return SPKDynamicInstagramColor(232.0, 234.0, 238.0, 58.0, 64.0, 72.0);
}

+ (UIColor *)SPKColor_InstagramGroupedBackground {
    return [self SPKColor_InstagramBackground];
}

+ (UIColor *)SPKColor_InstagramPrimaryText {
    return SPKDynamicInstagramColor(15.0, 20.0, 25.0, 244.0, 247.0, 251.0);
}

+ (UIColor *)SPKColor_InstagramSecondaryText {
    return SPKDynamicInstagramColor(99.0, 108.0, 118.0, 177.0, 185.0, 194.0);
}

+ (UIColor *)SPKColor_InstagramTertiaryText {
    return SPKDynamicInstagramColor(130.0, 138.0, 147.0, 130.0, 138.0, 147.0);
}

+ (UIColor *)SPKColor_InstagramSeparator {
    return SPKDynamicInstagramColor(220.0, 223.0, 228.0, 52.0, 59.0, 67.0);
}

+ (UIColor *)SPKColor_InstagramFavorite {
    return [UIColor colorWithRed:255.0 / 255.0 green:48.0 / 255.0 blue:64.0 / 255.0 alpha:1.0];
}

+ (UIColor *)SPKColor_InstagramDestructive {
    return SPKInstagramDestructiveColor();
}

+ (UIColor *)SPKColor_InstagramPressedBackground {
    return SPKDynamicInstagramColor(232.0, 233.0, 238.0, 51.0, 60.0, 69.0);
}

+ (UIColor *)SPKColor_ListRowPressedOverlay {
    // Subtle text-tinted overlay used by the Sparkle Gallery list rows. Shared by
    // the other custom list UIs (deleted messages, profile analyzer, downloads
    // history) so their tap feedback matches the gallery rather than the heavier
    // settings-cell pressed background.
    return [[SPKUtils SPKColor_InstagramPrimaryText] colorWithAlphaComponent:0.06];
}

+ (UIColor *)SPKColor_SettingsSwitchOnTintForTraitCollection:(UITraitCollection *)traitCollection {
    BOOL isDark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return isDark ? UIColor.whiteColor : UIColor.blackColor;
}

+ (UIColor *)SPKColor_SettingsSwitchThumbTintForTraitCollection:(UITraitCollection *)traitCollection {
    BOOL isDark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return isDark ? UIColor.blackColor : UIColor.whiteColor;
}

// MARK: Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc {
    return [self errorWithDescription:errorDesc code:1];
}
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode {
    NSError *error = [NSError errorWithDomain:@"com.sparkle.sparkle" code:errorCode userInfo:@{NSLocalizedDescriptionKey : errorDesc}];
    return error;
}
+ (BOOL)openURL:(NSURL *)url {
    if (!url)
        return NO;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    return YES;
}

+ (BOOL)openURLThroughApplicationDelegate:(NSURL *)url {
    if (!url)
        return NO;
    UIApplication *application = [UIApplication sharedApplication];
    id<UIApplicationDelegate> delegate = application.delegate;
    if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
        [delegate application:application openURL:url options:@{}];
        return YES;
    }
    return NO;
}

+ (void)dismissPresentedViewControllers {
    UIViewController *rootVC = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    rootVC = window.rootViewController;
                    break;
                }
            }
        }
        if (rootVC)
            break;
    }
    if (!rootVC) {
        rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    if (!rootVC)
        return;

    Class galleryManagerClass = NSClassFromString(@"SPKGalleryManager");
    if (galleryManagerClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id manager = [galleryManagerClass performSelector:@selector(sharedManager)];
#pragma clang diagnostic pop
        if (manager) {
            BOOL isLockEnabled = NO;
            @try {
                isLockEnabled = [[manager valueForKey:@"isLockEnabled"] boolValue];
            } @catch (NSException *exception) {
            }
            if (isLockEnabled) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [manager performSelector:@selector(lockGallery)];
#pragma clang diagnostic pop
            }
        }
    }

    if (rootVC.presentedViewController) {
        [rootVC dismissViewControllerAnimated:YES completion:nil];
    }
}

+ (BOOL)openInstagramProfileForUsername:(NSString *)username {
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (encodedUsername.length == 0)
        return NO;

    [self dismissPresentedViewControllers];

    NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", encodedUsername]];
    if (appURL && [[UIApplication sharedApplication] canOpenURL:appURL]) {
        if ([self openURLThroughApplicationDelegate:appURL])
            return YES;
        return [self openURL:appURL];
    }

    NSURL *webURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", encodedUsername]];
    return [self openInstagramMediaURL:webURL];
}

+ (BOOL)openInstagramMediaURL:(NSURL *)url {
    if (!url)
        return NO;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    UIApplication *application = [UIApplication sharedApplication];
    id<UIApplicationDelegate> delegate = application.delegate;

    [self dismissPresentedViewControllers];

    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        activity.webpageURL = url;
        SEL continueSelector = @selector(application:continueUserActivity:restorationHandler:);
        if ([delegate respondsToSelector:continueSelector]) {
            BOOL handled = [delegate application:application
                            continueUserActivity:activity
                              restorationHandler:^(__unused NSArray<id<UIUserActivityRestoring>> *restorableObjects){
                              }];
            if (handled)
                return YES;
        }
        if ([self openURLThroughApplicationDelegate:url])
            return YES;
    } else if ([scheme isEqualToString:@"instagram"]) {
        if ([self openURLThroughApplicationDelegate:url])
            return YES;
    }

    return [self openURL:url];
}

// Returns a cleaned canonical Instagram URL, or `nil` when there is nothing to
// sanitize (the input isn't an http/https Instagram URL). Callers MUST treat
// nil as "leave the original untouched": `+URLWithString:` on iOS 17+ leniently
// percent-encodes arbitrary text (captions, etc.) into a URL, so returning that
// input back would mangle plain-text clipboard writes into %20/%E2%80%A2 noise.
+ (NSURL *)sanitizedInstagramShareURL:(NSURL *)url {
    if (!url)
        return nil;
    if (![url isKindOfClass:[NSURL class]])
        return nil;

    if (![url.scheme.lowercaseString isEqualToString:@"http"] && ![url.scheme.lowercaseString isEqualToString:@"https"]) {
        return nil;
    }
    if (!SPKInstagramHostMatchesCanonical(url.host)) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) {
        return nil;
    }

    NSArray<NSString *> *rawSegments = [components.path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *segments = [NSMutableArray array];
    for (NSString *segment in rawSegments) {
        if (segment.length > 0) {
            [segments addObject:segment];
        }
    }

    NSArray<NSString *> *sanitizedSegments = SPKSanitizedInstagramPathSegments(segments);
    NSString *path = sanitizedSegments.count > 0 ? [@"/" stringByAppendingString:[sanitizedSegments componentsJoinedByString:@"/"]] : @"/";
    if (![path hasSuffix:@"/"]) {
        path = [path stringByAppendingString:@"/"];
    }

    components.scheme = @"https";
    components.host = @"www.instagram.com";
    components.path = path;
    components.queryItems = SPKSanitizedInstagramQueryItems(components.queryItems);
    components.fragment = nil;

    return components.URL ?: url;
}

+ (NSString *)appendImgIndex:(NSInteger)imgIndex toURLString:(NSString *)urlString {
    if (urlString.length == 0 || imgIndex <= 0)
        return urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url)
        return urlString;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components)
        return urlString;

    NSMutableArray<NSURLQueryItem *> *queryItems = [components.queryItems mutableCopy] ?: [NSMutableArray array];
    for (NSURLQueryItem *item in [queryItems copy]) {
        if ([item.name isEqualToString:@"img_index"]) {
            [queryItems removeObject:item];
        }
    }
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"img_index" value:[NSString stringWithFormat:@"%ld", (long)imgIndex]]];
    components.queryItems = queryItems;
    return components.URL.absoluteString ?: urlString;
}

+ (NSString *)instagramShortcodeForMediaPK:(NSString *)mediaPK {
    if (mediaPK.length == 0)
        return nil;

    // Media pk may arrive as "<pk>" or "<pk>_<userpk>"; only the leading id matters.
    NSString *identifier = [mediaPK componentsSeparatedByString:@"_"].firstObject ?: mediaPK;
    if (identifier.length == 0)
        return nil;
    if ([identifier rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound)
        return nil;

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:identifier];
    if (![scanner scanUnsignedLongLong:&value] || !scanner.isAtEnd || value == 0)
        return nil;

    static NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSMutableString *shortcode = [NSMutableString string];
    while (value > 0) {
        NSUInteger index = (NSUInteger)(value % 64);
        unichar character = [alphabet characterAtIndex:index];
        [shortcode insertString:[NSString stringWithCharacters:&character length:1] atIndex:0];
        value /= 64;
    }
    return shortcode.length > 0 ? shortcode : nil;
}

+ (BOOL)openPhotosApp {
    NSURL *url = [NSURL URLWithString:@"photos-redirect://"];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        return [self openURL:url];
    }
    return NO;
}

// MARK: Media
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo {
    if (!photo)
        return nil;

    NSURL *photoUrl = SPKHighestQualityURLFromVersions(SPKImageVersionsFromPhoto(photo));
    if (photoUrl)
        return photoUrl;

    if ([photo respondsToSelector:@selector(imageURLForWidth:)]) {
        photoUrl = [photo imageURLForWidth:100000.00];
        if (photoUrl)
            return photoUrl;
    }

    photoUrl = SPKURLFromStringOrURL(SPKObjectForSelector(photo, @"thumbnailURL"));

    return photoUrl;
}
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media {
    if (!media)
        return nil;

    IGPhoto *photo = SPKObjectForSelector(media, @"photo");
    if (!photo)
        return nil;

    return [SPKUtils getPhotoUrl:photo];
}
+ (NSURL *)getBestProfilePictureURLForUser:(id)user {
    return SPKHDProfilePicURL(user) ?: SPKThumbProfilePicURL(user);
}
+ (NSURL *)getVideoUrl:(IGVideo *)video {
    if (!video)
        return nil;

    NSURL *videoURL = SPKHighestQualityURLFromVersions(SPKVideoVersionsFromVideo(video));
    if (videoURL)
        return videoURL;

    // The past (pre v398)
    if ([video respondsToSelector:@selector(sortedVideoURLsBySize)]) {
        id sorted = [video sortedVideoURLsBySize];
        videoURL = SPKURLFromVideoURLCollection(sorted);
        if (videoURL)
            return videoURL;
    }

    // The present (post v398)
    if ([video respondsToSelector:@selector(allVideoURLs)]) {
        videoURL = SPKURLFromVideoURLCollection([video allVideoURLs]);
        if (videoURL)
            return videoURL;
    }

    return nil;
}
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media)
        return nil;

    IGVideo *video = SPKObjectForSelector(media, @"video");
    if (!video)
        return nil;

    return [SPKUtils getVideoUrl:video];
}

// MARK: View Controller Helpers
+ (UIViewController *)viewControllerForView:(UIView *)view {
    NSString *viewDelegate = @"viewDelegate";
    if ([view respondsToSelector:NSSelectorFromString(viewDelegate)]) {
        return [view valueForKey:viewDelegate];
    }

    return nil;
}

+ (UIViewController *)viewControllerForAncestralView:(UIView *)view {
    NSString *_viewControllerForAncestor = @"_viewControllerForAncestor";
    if ([view respondsToSelector:NSSelectorFromString(_viewControllerForAncestor)]) {
        return [view valueForKey:_viewControllerForAncestor];
    }

    return nil;
}

+ (UIViewController *)nearestViewControllerForView:(UIView *)view {
    return [self viewControllerForView:view] ?: [self viewControllerForAncestralView:view];
}

// Functions

// MARK: Alerts
+ (BOOL)showConfirmation:(void (^)(void))okHandler title:(NSString *)title {
    return [self showConfirmation:okHandler cancelHandler:nil title:title message:nil];
};
+ (BOOL)showConfirmation:(void (^)(void))okHandler title:(NSString *)title message:(NSString *)message {
    return [self showConfirmation:okHandler cancelHandler:nil title:title message:message];
};
+ (BOOL)showConfirmation:(void (^)(void))okHandler cancelHandler:(void (^)(void))cancelHandler title:(NSString *)title {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:title message:nil];
};
+ (BOOL)showConfirmation:(void (^)(void))okHandler cancelHandler:(void (^)(void))cancelHandler title:(NSString *)title message:(NSString *)message {
    [SPKIGAlertPresenter presentAlertFromViewController:topMostController()
                                                  title:title ?: @"Confirm Action"
                                                message:message ?: @"Are you sure you want to continue?"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"Cancel"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:^{
                                                                                  if (cancelHandler)
                                                                                      cancelHandler();
                                                                              }],
                                                    [SPKIGAlertAction actionWithTitle:@"Confirm"
                                                                                style:SPKIGAlertActionStyleDefault
                                                                              handler:^{
                                                                                  if (okHandler)
                                                                                      okHandler();
                                                                              }],
                                                ]];
    return YES;
};
+ (BOOL)showConfirmation:(void (^)(void))okHandler {
    return [self showConfirmation:okHandler title:nil];
};
+ (BOOL)showConfirmation:(void (^)(void))okHandler cancelHandler:(void (^)(void))cancelHandler {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:nil];
}
+ (void)showRestartConfirmation {
    [SPKIGAlertPresenter presentAlertFromViewController:topMostController()
                                                  title:@"Restart Required"
                                                message:@"You must restart the app to apply this change"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"Later"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"Restart"
                                                                                style:SPKIGAlertActionStyleDefault
                                                                              handler:^{
                                                                                  exit(0);
                                                                              }],
                                                ]];
};

// MARK: Math
+ (NSUInteger)decimalPlacesInDouble:(double)value {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:15]; // Allow enough digits for double precision
    [formatter setMinimumFractionDigits:0];
    [formatter setDecimalSeparator:@"."]; // Force dot for internal logic, then respect locale for final display if needed

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    // Find decimal separator
    NSRange decimalRange = [stringValue rangeOfString:formatter.decimalSeparator];

    if (decimalRange.location == NSNotFound) {
        return 0;
    } else {
        return stringValue.length - (decimalRange.location + decimalRange.length);
    }
}

// Ivars
+ (NSNumber *)numericValueForObj:(id)obj selectorName:(NSString *)selectorName {
    return SPKNumericValueForSelector(obj, selectorName);
}

+ (id)getIvarForObj:(id)obj name:(const char *)name {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar)
        return nil;

    return object_getIvar(obj, ivar);
}
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar)
        return;

    object_setIvarWithStrongDefault(obj, ivar, value);
}

+ (NSString *)igImageNameForImage:(UIImage *)image {
    if (![image isKindOfClass:UIImage.class])
        return nil;
    // IG tags loaded images with their asset name on the ig_imageName property.
    SEL sel = NSSelectorFromString(@"ig_imageName");
    if (![image respondsToSelector:sel])
        return nil;
    @try {
        id name = [image valueForKey:@"ig_imageName"];
        return [name isKindOfClass:NSString.class] ? name : nil;
    }
    @catch (NSException *exception) {
        return nil;
    }
}

+ (BOOL)control:(UIControl *)control hasTapActionContaining:(NSString *)needle {
    if (![control isKindOfClass:UIControl.class] || needle.length == 0)
        return NO;
    @try {
        for (id target in [control allTargets]) {
            id realTarget = (target == [NSNull null]) ? nil : target;
            NSArray<NSString *> *actions = [control actionsForTarget:realTarget
                                                     forControlEvent:UIControlEventTouchUpInside];
            for (NSString *action in actions) {
                if ([action rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    return YES;
                }
            }
        }
    }
    @catch (NSException *exception) {
    }
    return NO;
}

@end
