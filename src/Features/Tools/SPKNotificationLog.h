#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class UNNotificationRequest;

NS_ASSUME_NONNULL_BEGIN

/// Diagnostic log for the notification hooks.
///
/// The double-banner this exists to diagnose is unreliable to reproduce, so
/// os_log grepping over a live device is a poor fit: the interesting event has
/// usually scrolled past by the time you notice the second banner. This keeps a
/// rolling on-disk record instead, readable in-app from
/// Tools -> Notification Log.
///
/// Off by default — it records notification titles and bodies, so it must never
/// collect anything on an install whose owner has not asked for it.
FOUNDATION_EXPORT NSString *const kSPKNotificationLogPrefKey;

/// YES when \c kSPKNotificationLogPrefKey is on, or the app was launched with
/// SPK_NOTIF set to something other than "0". Reads the preference live, so the
/// toggle applies without a relaunch.
FOUNDATION_EXPORT BOOL SPKNotificationLogIsEnabled(void);

/// Appends one line for a request the hook saw. \c verdict is the short outcome
/// tag ("suppressed" / "allowed"). No-op when logging is disabled. Safe to call
/// from any thread.
FOUNDATION_EXPORT void SPKNotificationLogRecord(NSString *verdict, UNNotificationRequest *_Nullable request);

/// Appends a free-form marker line. Used for the hook-installed and
/// app-lifecycle heartbeats, so an empty log can be read as "the hook was live
/// and saw nothing" rather than "the hook never installed".
FOUNDATION_EXPORT void SPKNotificationLogNote(NSString *message);

/// Dumps what is currently sitting in Notification Center.
///
/// This is the only view we get of duplicates that arrive while Instagram is not
/// running: no in-process hook can observe those, but both delivered copies
/// remain listed afterwards. Two entries for one message means two real
/// notifications were delivered, and their identifiers say which came from the
/// notification extension and which from a local add.
FOUNDATION_EXPORT void SPKNotificationLogDumpDelivered(NSString *reason);

/// YES while our own delivered-notification dump is in flight. The hooks that
/// log Instagram's calls use this to ignore the ones we made ourselves.
FOUNDATION_EXPORT BOOL SPKNotificationLogIsInternalQuery(void);

/// Logs the app group ids this process is actually entitled to and where each
/// one resolves on disk. Instagram's notification dedupe store lives in that
/// container, so the main app and the notification extension have to agree on
/// it; the group id is read from the entitlements because resigning rewrites it.
///
/// \c phase labels when the reading was taken. This matters: Sparkle.dylib is
/// listed before SPKSideloadFix.dylib, so our %ctor runs before the sideload
/// fix installs its container redirect, and a reading taken there shows the
/// unhooked paths rather than what Instagram actually sees.
FOUNDATION_EXPORT void SPKNotificationLogGroupContainers(NSString *phase);

@interface SPKNotificationLog : NSObject

/// Reader for the rolling log: monospaced text, newest entry last, with copy,
/// share and clear actions.
+ (UIViewController *)logViewController;

@end

NS_ASSUME_NONNULL_END
