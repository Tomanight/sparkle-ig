#import "SPKNotificationLog.h"

#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <stdatomic.h>

#import "../../AssetUtils.h"
#import "../../Shared/UI/SPKMediaChrome.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../Utils.h"

// Private MobileCoreServices class, declared locally so the diagnostic can read
// the real entitlements instead of assuming the canonical app group name.
@interface LSBundleProxy : NSObject
+ (instancetype)bundleProxyForCurrentProcess;
@property (nonatomic, readonly) NSDictionary *entitlements;
@property (nonatomic, readonly) NSDictionary *groupContainerURLs;
@end

NSString *const kSPKNotificationLogPrefKey = @"tools_notification_log";

static NSString *const kSPKNotificationLogDirectoryName = @"SparkleNotificationLogs";
static NSString *const kSPKNotificationLogFileName = @"notifications.log";

// Enough to hold a busy evening of notifications while staying trivially
// readable in a text view. Trimmed from the front when exceeded, so the tail --
// the part you just reproduced -- always survives.
static const unsigned long long kSPKNotificationLogMaxBytes = 256 * 1024;

BOOL SPKNotificationLogIsEnabled(void) {
    // Deliberately a preference and not an environment variable or a DEV-build
    // check. Push notifications only arrive on an ordinary sideload install
    // signed for the account receiving them -- which is launched from the home
    // screen (so no environment reaches it) and is not a DEV build. Gating on
    // either would leave the log unreachable in the only environment that can
    // reproduce the duplicate banner.
    //
    // Read live rather than cached: the toggle has to take effect without a
    // relaunch, since relaunching is itself part of reproducing the bug.
    if ([SPKUtils getBoolPref:kSPKNotificationLogPrefKey]) {
        return YES;
    }
    // Still honoured, for a build launched over pymobiledevice3 --env.
    static BOOL environmentEnabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *value = getenv("SPK_NOTIF");
        environmentEnabled = (value != NULL && strcmp(value, "0") != 0);
    });
    return environmentEnabled;
}

static dispatch_queue_t SPKNotificationLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.sparkle.notification-log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString *SPKNotificationLogDirectoryPath(void) {
    NSArray<NSURL *> *cacheURLs = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
                                                                         inDomains:NSUserDomainMask];
    NSURL *baseURL = cacheURLs.firstObject ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *logsURL = [baseURL URLByAppendingPathComponent:kSPKNotificationLogDirectoryName isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:logsURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    return logsURL.path;
}

static NSString *SPKNotificationLogFilePath(void) {
    return [SPKNotificationLogDirectoryPath() stringByAppendingPathComponent:kSPKNotificationLogFileName];
}

static NSString *SPKNotificationLogTimestamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:[NSDate date]];
}

/// Seconds between the payload's own "ts" (when Instagram's server created the
/// notification) and now. Quantifies delivery lag without guessing at whose
/// fault it is: a large value here means the notification was already old when
/// it reached the device.
static NSString *SPKNotificationLogAge(NSDictionary *userInfo, NSDate *reference) {
    id raw = userInfo[@"ts"];
    if (![raw respondsToSelector:@selector(doubleValue)]) {
        return @"-";
    }
    double ts = [raw doubleValue];
    if (ts <= 0) {
        return @"-";
    }
    // IG has used both seconds and microseconds here across versions; normalise
    // anything implausibly large down until it lands in a sane epoch range.
    while (ts > 4e10) {
        ts /= 1000.0;
    }
    NSTimeInterval age = [(reference ?: [NSDate date]) timeIntervalSince1970] - ts;
    if (age < -60.0 || age > 86400.0) {
        return @"-";
    }
    return [NSString stringWithFormat:@"%.1fs", age];
}

/// Keeps long message bodies from swamping the line while leaving enough to
/// recognise the same message arriving twice.
static NSString *SPKNotificationLogTruncate(NSString *value, NSUInteger limit) {
    if (value.length == 0) {
        return @"-";
    }
    NSString *flattened = [[value stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\r"
                                  withString:@" "];
    if (flattened.length <= limit) {
        return flattened;
    }
    return [[flattened substringToIndex:limit] stringByAppendingString:@"..."];
}

static void SPKNotificationLogTrimIfNeeded(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attributes fileSize];
    if (size <= kSPKNotificationLogMaxBytes) {
        return;
    }

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (content.length == 0) {
        return;
    }
    // Drop the oldest half, then resync to a line boundary so the file never
    // starts mid-entry.
    NSString *tail = [content substringFromIndex:content.length / 2];
    NSRange newline = [tail rangeOfString:@"\n"];
    if (newline.location != NSNotFound && newline.location + 1 < tail.length) {
        tail = [tail substringFromIndex:newline.location + 1];
    }
    [[@"--- older entries trimmed ---\n" stringByAppendingString:tail] writeToFile:path
                                                                       atomically:YES
                                                                         encoding:NSUTF8StringEncoding
                                                                            error:nil];
}

static void SPKNotificationLogAppend(NSString *line) {
    dispatch_async(SPKNotificationLogQueue(), ^{
        NSString *path = SPKNotificationLogFilePath();
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
        SPKNotificationLogTrimIfNeeded(path);
    });
}

void SPKNotificationLogNote(NSString *message) {
    if (!SPKNotificationLogIsEnabled() || message.length == 0) {
        return;
    }
    SPKNotificationLogAppend([NSString stringWithFormat:@"%@  --- %@\n", SPKNotificationLogTimestamp(), message]);
}

void SPKNotificationLogGroupContainers(NSString *phase) {
    if (!SPKNotificationLogIsEnabled()) {
        return;
    }

    LSBundleProxy *proxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
    NSDictionary *entitlements = proxy.entitlements;
    NSArray *groups = [entitlements isKindOfClass:[NSDictionary class]]
                          ? entitlements[@"com.apple.security.application-groups"]
                          : nil;

    if (![groups isKindOfClass:[NSArray class]] || groups.count == 0) {
        SPKNotificationLogNote([NSString stringWithFormat:@"app groups [%@]: none in entitlements", phase]);
        return;
    }

    NSDictionary *containerURLs = proxy.groupContainerURLs;
    // Instagram asks for this literal id; if the redirect is live it resolves to
    // a path nested under one of the entitled containers instead of nil.
    NSURL *igGroup = [[NSFileManager defaultManager]
        containerURLForSecurityApplicationGroupIdentifier:@"group.com.burbn.instagram"];
    NSMutableString *out = [NSMutableString stringWithFormat:@"app groups [%@] (%lu):"
                                                             @"\n              group.com.burbn.instagram (what IG asks for)"
                                                             @"\n                 resolved=%@%@",
                                                            phase, (unsigned long)groups.count,
                                                            igGroup.path ?: @"<nil>",
                                                            igGroup ? @"" : @"   <-- redirect not active yet"];

    // Instagram's notification dedupe store lives in here. If the main app is
    // marking notifications, a sqlite file shows up; an empty container means
    // nothing is writing and the extension has nothing to check against.
    if (igGroup) {
        NSArray<NSString *> *contents =
            [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:igGroup.path error:nil];
        NSArray<NSString *> *stores = [contents filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"SELF CONTAINS[c] 'sqlite' OR SELF CONTAINS[c] 'dedup' OR SELF ENDSWITH[c] '.db'"]];
        [out appendFormat:@"\n                 contents=%lu entries%@", (unsigned long)contents.count,
                          stores.count > 0
                              ? [NSString stringWithFormat:@", stores: %@", [stores componentsJoinedByString:@", "]]
                              : @"  (no dedupe store present)"];
    }

    for (id group in groups) {
        if (![group isKindOfClass:[NSString class]]) {
            continue;
        }
        NSURL *resolved = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
        NSURL *fromProxy = [containerURLs isKindOfClass:[NSDictionary class]] ? containerURLs[group] : nil;
        [out appendFormat:@"\n              %@\n                 resolved=%@", group, resolved.path ?: @"<nil>"];
        // A path under Documents/ is the sideload fix's per-process fallback:
        // the app and the extension get different directories, so the mark and
        // the check never meet.
        if ([resolved.path containsString:@"/Documents/"]) {
            [out appendString:@"   <-- PER-PROCESS FALLBACK, dedupe cannot work"];
        }
        if (fromProxy && ![fromProxy.path isEqualToString:resolved.path]) {
            [out appendFormat:@"\n                 entitled=%@", fromProxy.path];
        }
        // If another process (the notification extension) picked a different
        // root, the redirect would have created group.com.burbn.instagram inside
        // that container too. Finding a second copy -- especially one holding a
        // dedupe database -- is proof the app and the extension are not sharing.
        if (fromProxy) {
            NSString *nested = [fromProxy.path stringByAppendingPathComponent:@"group.com.burbn.instagram"];
            // Skip the container the main app itself redirects into: that is the
            // directory we already listed above, not a second copy.
            BOOL isOwnContainer = igGroup.path && [nested isEqualToString:igGroup.path];
            if (!isOwnContainer && [[NSFileManager defaultManager] fileExistsAtPath:nested]) {
                NSArray<NSString *> *nestedContents =
                    [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:nested error:nil];
                BOOL hasDedupe = [nestedContents indexOfObjectPassingTest:^BOOL(NSString *p, NSUInteger i, BOOL *stop) {
                    return [p containsString:@"IGNotificationDeduplication"];
                }] != NSNotFound;
                [out appendFormat:@"\n                 ALSO HAS group.com.burbn.instagram: %lu entries%@",
                                  (unsigned long)nestedContents.count,
                                  hasDedupe ? @"  <-- SPLIT: holds a dedupe database" : @""];
            }
        }
    }
    SPKNotificationLogNote(out);
}

static atomic_int spk_internalQueryDepth = 0;

BOOL SPKNotificationLogIsInternalQuery(void) {
    return atomic_load(&spk_internalQueryDepth) > 0;
}

void SPKNotificationLogDumpDelivered(NSString *reason) {
    if (!SPKNotificationLogIsEnabled()) {
        return;
    }
    atomic_fetch_add(&spk_internalQueryDepth, 1);
    [[UNUserNotificationCenter currentNotificationCenter]
        getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
            atomic_fetch_sub(&spk_internalQueryDepth, 1);
            if (notifications.count == 0) {
                SPKNotificationLogNote([NSString stringWithFormat:@"delivered dump (%@): none in Notification Center", reason]);
                return;
            }
            NSMutableString *dump = [NSMutableString stringWithFormat:@"%@  --- delivered dump (%@): %lu in Notification Center\n",
                                                                     SPKNotificationLogTimestamp(), reason,
                                                                     (unsigned long)notifications.count];
            for (UNNotification *notification in notifications) {
                UNNotificationRequest *request = notification.request;
                NSDictionary *userInfo = [request.content.userInfo isKindOfClass:[NSDictionary class]]
                                             ? request.content.userInfo
                                             : @{};
                // trigger tells us the origin: UNPushNotificationTrigger means the
                // system delivered it from APNs (the extension's copy), anything
                // else means it was added locally by the app.
                NSString *trigger = notification.request.trigger
                                        ? NSStringFromClass([notification.request.trigger class])
                                        : @"none(local)";
                // "u" is the recipient account. Two notifications sharing a gid but
                // differing in u are one message fanned out to two logged-in
                // accounts -- expected, and must never be treated as duplicates.
                [dump appendFormat:@"              id=%@  trigger=%@  gid=%@  u=%@  pt=%@  age=%@\n"
                                   @"                 title=%@  sub=%@  body=%@\n"
                                   @"                 keys=[%@]\n",
                                   request.identifier ?: @"-", trigger,
                                   userInfo[@"gid"] ?: @"-", userInfo[@"u"] ?: @"-",
                                   userInfo[@"pt"] ?: @"-",
                                   // Measured against the delivery date, not now, so it
                                   // is the real server-to-device lag and does not grow
                                   // with however long the notification sat unread.
                                   SPKNotificationLogAge(userInfo, notification.date),
                                   SPKNotificationLogTruncate(request.content.title, 40),
                                   SPKNotificationLogTruncate(request.content.subtitle, 40),
                                   SPKNotificationLogTruncate(request.content.body, 60),
                                   [[userInfo.allKeys valueForKey:@"description"] componentsJoinedByString:@","]];
            }
            SPKNotificationLogAppend(dump);
        }];
}

void SPKNotificationLogRecord(NSString *verdict, UNNotificationRequest *request) {
    if (!SPKNotificationLogIsEnabled()) {
        return;
    }

    // Read everything off the request here: the block below runs later, and a
    // UNNotificationRequest handed to us by IG is not ours to keep hold of.
    NSString *identifier = request.identifier ?: @"-";
    UNNotificationContent *content = request.content;
    NSDictionary *userInfo = [content.userInfo isKindOfClass:[NSDictionary class]] ? content.userInfo : @{};
    NSString *keys = [[userInfo.allKeys valueForKey:@"description"] componentsJoinedByString:@","];
    NSString *title = SPKNotificationLogTruncate(content.title, 40);
    NSString *body = SPKNotificationLogTruncate(content.body, 80);
    NSString *thread = content.threadIdentifier.length > 0 ? content.threadIdentifier : @"-";
    NSString *category = content.categoryIdentifier.length > 0 ? content.categoryIdentifier : @"-";
    NSString *gid = [userInfo[@"gid"] isKindOfClass:[NSString class]] ? userInfo[@"gid"] : (userInfo[@"gid"] ? @"<non-string>" : @"-");
    // Padded by hand: a width flag on %@ ("%-12@") is silently ignored by
    // NSString formatting, so the verdict column would not line up.
    NSString *paddedVerdict = [(verdict.length > 0 ? verdict : @"?") stringByPaddingToLength:12
                                                                                 withString:@" "
                                                                            startingAtIndex:0];
    NSString *user = [userInfo[@"u"] description] ?: @"-";
    NSString *age = SPKNotificationLogAge(userInfo, nil);
    // "pt" is the transport Instagram's server chose. "iris" means it came over
    // the realtime socket, which is the fast path and the one worth keeping.
    NSString *transport = [userInfo[@"pt"] description] ?: @"-";
    NSString *line = [NSString stringWithFormat:@"%@  %@  id=%@  gid=%@  u=%@  pt=%@  age=%@  aps=%@  cat=%@  thread=%@\n"
                                                 @"            title=%@\n"
                                                 @"            body=%@\n"
                                                 @"            keys=[%@]\n",
                                                SPKNotificationLogTimestamp(),
                                                paddedVerdict,
                                                identifier,
                                                gid,
                                                user,
                                                transport,
                                                age,
                                                userInfo[@"aps"] ? @"yes" : @"no",
                                                category,
                                                thread,
                                                title,
                                                body,
                                                keys];

    SPKNotificationLogAppend(line);
}

#pragma mark - Viewer

@interface _SPKNotificationLogViewController : UIViewController
@end

@implementation _SPKNotificationLogViewController {
    UITextView *_textView;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
    self.title = @"Notification Log";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    _textView.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    _textView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _textView.textContainerInset = UIEdgeInsetsMake(16.0, 14.0, 16.0, 14.0);
    _textView.layer.cornerRadius = 14.0;
    [self.view addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0]
    ]];

    UIBarButtonItem *shareItem = SPKMediaChromeTopBarButtonItem(@"share", self, @selector(shareTapped));
    shareItem.accessibilityLabel = @"Share";
    UIBarButtonItem *copyItem = SPKMediaChromeTopBarButtonItem(@"copy", self, @selector(copyTapped));
    copyItem.accessibilityLabel = @"Copy";
    UIBarButtonItem *dumpItem = SPKMediaChromeTopBarButtonItem(@"download", self, @selector(dumpTapped));
    dumpItem.accessibilityLabel = @"Dump delivered";
    UIBarButtonItem *clearItem = SPKMediaChromeTopBarButtonItem(@"trash", self, @selector(clearTapped));
    clearItem.accessibilityLabel = @"Clear";
    clearItem.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ clearItem, copyItem, shareItem, dumpItem ]);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadContent];
}

- (void)reloadContent {
    NSString *content = [NSString stringWithContentsOfFile:SPKNotificationLogFilePath()
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (content.length > 0) {
        _textView.text = content;
        // Newest entries are appended, so open at the bottom.
        [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length - 1, 1)];
        return;
    }

    _textView.text = SPKNotificationLogIsEnabled()
                         ? @"Recording. Nothing captured yet.\n\nLeave Instagram, have someone message you, then come back here."
                         : @"Notification logging is off.\n\nTurn on Log Notification Activity in Tools to record what the notification hooks see. It applies right away, no relaunch needed.";
}

- (void)copyTapped {
    NSString *content = [NSString stringWithContentsOfFile:SPKNotificationLogFilePath()
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (content.length == 0) {
        SPKNotify(kSPKNotificationNotificationLog, @"Nothing to copy", nil, @"error_filled", SPKNotificationToneError);
        return;
    }
    [UIPasteboard generalPasteboard].string = content;
    SPKNotify(kSPKNotificationNotificationLog, @"Log copied", nil, @"circle_check_filled", SPKNotificationToneSuccess);
}

- (void)shareTapped {
    NSString *path = SPKNotificationLogFilePath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [SPKUtils showShareVC:[NSURL fileURLWithPath:path]];
        return;
    }
    SPKNotify(kSPKNotificationNotificationLog, @"No log yet", nil, @"info_filled", SPKNotificationToneInfo);
}

- (void)dumpTapped {
    if (!SPKNotificationLogIsEnabled()) {
        SPKNotify(kSPKNotificationNotificationLog, @"Logging is off", nil, @"error_filled", SPKNotificationToneError);
        return;
    }
    SPKNotificationLogDumpDelivered(@"manual");
    // The dump is written asynchronously off a completion handler, so give it a
    // moment before re-reading rather than showing a stale view.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self reloadContent];
    });
    SPKNotify(kSPKNotificationNotificationLog, @"Dumped delivered notifications", nil, @"circle_check_filled",
              SPKNotificationToneSuccess);
}

- (void)clearTapped {
    [[NSFileManager defaultManager] removeItemAtPath:SPKNotificationLogFilePath() error:nil];
    [self reloadContent];
    SPKNotify(kSPKNotificationNotificationLog, @"Log cleared", nil, @"circle_check_filled", SPKNotificationToneSuccess);
}

@end

@implementation SPKNotificationLog

+ (UIViewController *)logViewController {
    return [[_SPKNotificationLogViewController alloc] init];
}

@end
