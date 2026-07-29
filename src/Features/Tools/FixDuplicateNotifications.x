#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "SPKNotificationLog.h"

// Sideloaded Instagram delivers some notifications twice: the system shows the
// APNs push (through the bundled InstagramNotificationExtension), and IG's own
// code re-adds that same push as a *local* notification via
// -[UNUserNotificationCenter addNotificationRequest:withCompletionHandler:] —
// two banners for one event.
//
// Push-derived adds are identifiable from their content.userInfo: they carry
// IG's server-generated push id ("gid"), which IG's genuinely local
// notifications do not. Suppress those and let the system's own banner stand.
//
// Sparkle itself never posts a UNNotificationRequest (SPKNotify draws an in-app
// view), so nothing of ours can be caught by this.

static BOOL SPKNotificationRequestIsPushDerived(UNNotificationRequest *request) {
    NSDictionary *userInfo = request.content.userInfo;
    if (![userInfo isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    // "gid" alone. Requiring "ig" AND "gid" missed most duplicates: which keys
    // survive into the local copy varies with the notification type (DM vs like
    // vs follow) and with the IG version. Deliberately NOT also matching "aps",
    // even though that looks like the obvious push marker: the local re-add
    // carries no "aps" key at all, so an "aps" arm can only ever match
    // notifications this hook is not meant to touch.
    return userInfo[@"gid"] != nil;
}

%group SPKFixDuplicateNotificationsHooks

%hook UNUserNotificationCenter

- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *error))completionHandler {
    // Installed from %ctor, which runs ahead of the surface registry that
    // normally enforces the master kill switch, so honour it here.
    if ([SPKUtils getBoolPref:@"tools_disable_all"]) {
        %orig;
        return;
    }

    if (![SPKUtils getBoolPref:@"tools_fix_duplicate_notifications"]) {
        // Still worth recording: with the toggle off the log shows every request
        // unfiltered, which is how you tell whether a duplicate pair reaches this
        // method at all.
        SPKNotificationLogRecord(@"passthrough", request);
        %orig;
        return;
    }

    // Deliberately not gated on applicationState. The previous version only
    // suppressed while the app was foreground-active, which is the rarer case:
    // most duplicates arrive with the app backgrounded, where IG is woken by the
    // push and re-adds it just the same — the foreground gate is what let them
    // through. There is also no safe way to read applicationState here, since
    // this is called off the main thread.
    if (SPKNotificationRequestIsPushDerived(request)) {
        SPKNotificationLogRecord(@"suppressed", request);
        // Drop it, but still satisfy the API contract by completing without error.
        if (completionHandler)
            completionHandler(nil);
        return;
    }

    SPKNotificationLogRecord(@"allowed", request);
    %orig;
}

// Diagnostics only, both always call through. On a stock App Store build these
// two are what distinguish "no duplicate" from "duplicate cleaned up": IG calls
// getDelivered immediately after each add, so if it ever removes the redundant
// copy, that removal is the behaviour worth replicating here.
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray<NSString *> *)identifiers {
    SPKNotificationLogNote([NSString stringWithFormat:@"IG removed delivered: %@",
                                                      [identifiers componentsJoinedByString:@", "]]);
    %orig;
}

- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *))completionHandler {
    if (!SPKNotificationLogIsInternalQuery()) {
        SPKNotificationLogNote(@"IG queried delivered notifications");
    }
    %orig;
}

%end

%end

static void SPKInstallFixDuplicateNotificationsHooksNow(void) {
    // Install unconditionally and gate on the pref inside the hook so the toggle
    // takes effect live, without a restart.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKFixDuplicateNotificationsHooks);
    });
}

// At dylib load, not on the staged surface timer. Duplicates overwhelmingly
// arrive while Instagram is backgrounded or not running: the push wakes the
// process, and IG re-adds the notification during launch. The GeneralUI phase
// installs 0.25s after didFinishLaunching, which is comfortably after that
// re-add has already happened — so on the runs that matter the hook was not yet
// in place. Hooking one system class is cheap enough to do here, and the pref
// is still read per call, so this costs nothing when the feature is off.
%ctor {
    SPKInstallFixDuplicateNotificationsHooksNow();

    // Heartbeats, so an empty log is readable. Without them "the hook was live
    // and Instagram never called addNotificationRequest:" and "the hook never
    // installed" produce an identical empty screen. The class lookup confirms
    // UserNotifications was loaded by the time this ran.
    SPKNotificationLogNote(objc_getClass("UNUserNotificationCenter")
                               ? @"hook installed (ctor)"
                               : @"HOOK NOT INSTALLED: UNUserNotificationCenter missing at ctor");

    // IG dedupes the APNs fallback against the iris copy through a SQLite store
    // in the app group container: the main app marks, the notification extension
    // checks. That only works if both processes resolve the SAME container.
    //
    // Read the group ids out of the entitlements rather than assuming the
    // canonical name: resigning rewrites them, so a hardcoded lookup says
    // nothing about whether the install has app groups.
    SPKNotificationLogGroupContainers(@"ctor");

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
                        SPKNotificationLogNote(@"app foregrounded");
                        // Re-read once everything has loaded: this is the state
                        // Instagram actually runs against.
                        static dispatch_once_t groupsOnce;
                        dispatch_once(&groupsOnce, ^{
                            SPKNotificationLogGroupContainers(@"loaded");
                        });
                        // Catches anything that was delivered while we were not
                        // running to observe it.
                        SPKNotificationLogDumpDelivered(@"foreground");
                    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
                        SPKNotificationLogNote(@"app backgrounded");
                    }];
}

void SPKInstallFixDuplicateNotificationsHooksIfNeeded(void) {
    // Kept for the surface registry; the %ctor above has already run.
    SPKInstallFixDuplicateNotificationsHooksNow();
}
