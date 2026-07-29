#import "SPKNotificationCenter.h"
#import "../../AssetUtils.h"
#import "../../Settings/SPKPreferences.h"
#import "../../Utils.h"
#import "../AutoSave/SPKAutoSaveFilter.h"
#import "../Instants/SPKInstantsAutoSave.h"
#import "../Messages/SPKDirectAutoSave.h"
#import "../Messages/SPKDirectSeenContext.h"
#import "../Stories/SPKStoryAutoSave.h"
#import "../Stories/SPKStoryContext.h"

// Every auto-save list-change notification offers the same "tap to open the list"
// affordance, so they live in one table rather than a branch per surface. Returns nil
// when there's nothing to offer -- unknown identifier, or the user is already looking
// at an auto-save list.
static UIViewController *SPKAutoSaveListViewControllerForRuleIdentifier(NSString *identifier) {
    if (identifier.length == 0 || SPKAutoSaveFilterListUIVisible())
        return nil;
    if ([identifier isEqualToString:kSPKNotificationStoryAutoSaveUserRule])
        return SPKStoryAutoSaveListViewController();
    if ([identifier isEqualToString:kSPKNotificationDirectAutoSaveThreadRule])
        return SPKDirectAutoSaveListViewController();
    if ([identifier isEqualToString:kSPKNotificationInstantsAutoSaveUserRule])
        return SPKInstantsAutoSaveListViewController();
    return nil;
}

#define SPK_NOTIF_CONST(name, value) NSString *const name = @value
SPK_NOTIF_CONST(kSPKNotificationDownloadLibrary, "download_library");
SPK_NOTIF_CONST(kSPKNotificationDownloadShare, "download_share");
SPK_NOTIF_CONST(kSPKNotificationCopyDownloadLink, "copy_download_link");
SPK_NOTIF_CONST(kSPKNotificationCopyMedia, "copy_media");
SPK_NOTIF_CONST(kSPKNotificationDownloadGallery, "download_gallery");
SPK_NOTIF_CONST(kSPKNotificationDownloadAllLibrary, "download_all_library");
SPK_NOTIF_CONST(kSPKNotificationDownloadAllShare, "download_all_share");
SPK_NOTIF_CONST(kSPKNotificationDownloadAllGallery, "download_all_gallery");
SPK_NOTIF_CONST(kSPKNotificationDownloadAllClipboard, "download_all_clipboard");
SPK_NOTIF_CONST(kSPKNotificationDownloadAllLinks, "download_all_links");
SPK_NOTIF_CONST(kSPKNotificationDownloadQueueFinished, "download_queue_finished");
SPK_NOTIF_CONST(kSPKNotificationQueuedDownloadFailed, "queued_download_failed");
SPK_NOTIF_CONST(kSPKNotificationExpand, "expand");
SPK_NOTIF_CONST(kSPKNotificationViewThumbnail, "view_thumbnail");
SPK_NOTIF_CONST(kSPKNotificationCopyCaption, "copy_caption");
SPK_NOTIF_CONST(kSPKNotificationOpenTopicSettings, "open_topic_settings");
SPK_NOTIF_CONST(kSPKNotificationRepost, "repost");

SPK_NOTIF_CONST(kSPKNotificationDownloadAudio, "download_audio");
SPK_NOTIF_CONST(kSPKNotificationDownloadAudioShare, "download_audio_share");
SPK_NOTIF_CONST(kSPKNotificationDownloadAudioGallery, "download_audio_gallery");
SPK_NOTIF_CONST(kSPKNotificationPlayAudio, "play_audio");
SPK_NOTIF_CONST(kSPKNotificationCopyAudioURL, "copy_audio_url");

SPK_NOTIF_CONST(kSPKNotificationStoryMarkSeen, "story_mark_seen");
SPK_NOTIF_CONST(kSPKNotificationStorySeenUserRule, "toggle_story_seen_user_rule");
SPK_NOTIF_CONST(kSPKNotificationStoryMentionsSheet, "story_mentions_sheet");
SPK_NOTIF_CONST(kSPKNotificationStoryAutoSave, "story_auto_save");
SPK_NOTIF_CONST(kSPKNotificationStoryAutoSaveUserRule, "toggle_story_auto_save_user_rule");
SPK_NOTIF_CONST(kSPKNotificationAutoSaveSummary, "auto_save_summary");
SPK_NOTIF_CONST(kSPKNotificationAutoSavePending, "auto_save_pending");
SPK_NOTIF_CONST(kSPKNotificationDirectVisualMarkSeen, "direct_visual_mark_seen");
SPK_NOTIF_CONST(kSPKNotificationThreadMessagesMarkSeen, "thread_messages_mark_seen");
SPK_NOTIF_CONST(kSPKNotificationDirectThreadSeenRule, "direct_thread_seen_rule");
SPK_NOTIF_CONST(kSPKNotificationDirectAutoSave, "direct_auto_save");
SPK_NOTIF_CONST(kSPKNotificationDirectAutoSaveThreadRule, "toggle_direct_auto_save_thread_rule");
SPK_NOTIF_CONST(kSPKNotificationUnsentMessage, "unsent_message");
SPK_NOTIF_CONST(kSPKNotificationUnsentReaction, "unsent_reaction");
SPK_NOTIF_CONST(kSPKNotificationInstantsCaptureBlocked, "instants_capture_blocked");
SPK_NOTIF_CONST(kSPKNotificationInstantsAutoSave, "instants_auto_save");
SPK_NOTIF_CONST(kSPKNotificationInstantsAutoSaveUserRule, "toggle_instants_auto_save_user_rule");

SPK_NOTIF_CONST(kSPKNotificationProfileCopyInfo, "profile_copy_info");
SPK_NOTIF_CONST(kSPKNotificationProfileAnalyzerComplete, "profile_analyzer_complete");
SPK_NOTIF_CONST(kSPKNotificationProfileStorySeenUserRule, "toggle_profile_story_seen_user_rule");
SPK_NOTIF_CONST(kSPKNotificationProfileMessagesSeenUserRule, "toggle_profile_messages_seen_user_rule");

SPK_NOTIF_CONST(kSPKNotificationMediaPreviewSavePhotos, "media_preview_save_photos");
SPK_NOTIF_CONST(kSPKNotificationMediaPreviewSaveGallery, "media_preview_save_gallery");
SPK_NOTIF_CONST(kSPKNotificationMediaPreviewShare, "media_preview_share");
SPK_NOTIF_CONST(kSPKNotificationMediaPreviewCopy, "media_preview_copy");
SPK_NOTIF_CONST(kSPKNotificationMediaPreviewDeleteGallery, "media_preview_delete_gallery");
SPK_NOTIF_CONST(kSPKNotificationMediaPreviewOpenGallery, "media_preview_open_gallery");

SPK_NOTIF_CONST(kSPKNotificationGalleryOpenOriginal, "gallery_open_original");
SPK_NOTIF_CONST(kSPKNotificationGalleryOpenProfile, "gallery_open_profile");
SPK_NOTIF_CONST(kSPKNotificationGalleryDeleteFile, "gallery_delete_file");
SPK_NOTIF_CONST(kSPKNotificationGalleryDeleteSelected, "gallery_delete_selected");
SPK_NOTIF_CONST(kSPKNotificationGalleryBulkDelete, "gallery_bulk_delete");
SPK_NOTIF_CONST(kSPKNotificationGalleryImport, "gallery_import");

SPK_NOTIF_CONST(kSPKNotificationSettingsExport, "settings_export");
SPK_NOTIF_CONST(kSPKNotificationSettingsImport, "settings_import");
SPK_NOTIF_CONST(kSPKNotificationSettingsClearCache, "settings_clear_cache");
SPK_NOTIF_CONST(kSPKNotificationCopyDescription, "copy_description");
SPK_NOTIF_CONST(kSPKNotificationCopyNoteText, "copy_note_text");
SPK_NOTIF_CONST(kSPKNotificationShareLongPressCopyLink, "share_long_press_copy_link");
SPK_NOTIF_CONST(kSPKNotificationCopyComment, "copy_comment");
SPK_NOTIF_CONST(kSPKNotificationCopyGIFLink, "copy_gif_link");
SPK_NOTIF_CONST(kSPKNotificationMediaEncodingLogs, "media_encoding_logs");
SPK_NOTIF_CONST(kSPKNotificationFlexUnavailable, "flex_unavailable");
SPK_NOTIF_CONST(kSPKNotificationNotificationLog, "notification_log");
#undef SPK_NOTIF_CONST

NSString *const kSPKNotificationPillDurationKey = @"notifs_pill_duration";
NSString *const kSPKNotificationPillGlowEnabledKey = @"notifs_pill_glow";
NSString *const kSPKNotificationPillLiquidGlassEnabledKey = @"notifs_pill_liquid_glass";
NSString *const kSPKNotificationProgressSubtitleStyleKey = @"notifs_progress_subtitle_style";
NSString *const kSPKNotificationPillPositionKey = @"notifs_pill_position";

static CGFloat const kSPKNotificationStackSpacing = 8.0;
static CGFloat const kSPKNotificationTopMargin = 8.0;
// Bottom pills clear the safe-area bottom, but IG stacks a tab bar / composer /
// toolbar above it that the safe area doesn't cover. Lift bottom pills further so
// they float clear of that chrome instead of overlapping it.
static CGFloat const kSPKNotificationBottomMargin = 60.0;
static NSTimeInterval const kSPKNotificationInsertDuration = 0.55;
static NSTimeInterval const kSPKNotificationDefaultPillDuration = 1.5;
static NSTimeInterval const kSPKNotificationMinPillDuration = 0.5;
static NSTimeInterval const kSPKNotificationMaxPillDuration = 5.0;
static NSUInteger const kSPKNotificationMaxQueuedToasts = 3;

@interface SPKNotificationSlot : NSObject
@property (nonatomic, strong) SPKNotificationPillView *pill;
@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) BOOL progress;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation SPKNotificationSlot
@end

@interface SPKNotificationOverlayRootViewController : UIViewController
@end

@implementation SPKNotificationOverlayRootViewController
- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.clearColor;
    self.view = view;
}
@end

@interface SPKNotificationPassthroughWindow : UIWindow
@end

@implementation SPKNotificationPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view)
        return nil;
    return hit;
}
// Tapping a pill must not make this overlay the key window — otherwise anything
// a pill's tap handler presents (e.g. the deleted-messages log sheet) attaches
// to this window and gets torn down with it when the pill dismisses. Pills still
// receive touches; key status isn't required for that.
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

static NSDictionary *SPKNotificationItem(NSString *identifier, NSString *title, NSString *iconName) {
    return @{@"identifier" : identifier ?: @"", @"title" : title ?: @"", @"iconName" : iconName ?: @"info"};
}

NSString *SPKNotificationDefaultsKey(NSString *identifier) {
    return SPKPrefNotificationKey(identifier);
}

NSString *SPKNotificationHapticDefaultsKey(NSString *identifier) {
    return SPKPrefNotificationHapticKey(identifier);
}

NSArray<NSDictionary *> *SPKNotificationPreferenceSections(void) {
    return @[
        @{@"title" : @"Action Buttons",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationDownloadLibrary, @"Save to Photos", @"download"),
              SPKNotificationItem(kSPKNotificationDownloadShare, @"Share", @"share"),
              SPKNotificationItem(kSPKNotificationCopyDownloadLink, @"Copy Download URL", @"link"),
              SPKNotificationItem(kSPKNotificationCopyMedia, @"Copy Media", @"copy"),
              SPKNotificationItem(kSPKNotificationDownloadGallery, @"Save to Gallery", @"sparkle_gallery"),
              SPKNotificationItem(kSPKNotificationDownloadAllLibrary, @"Save All to Photos", @"download"),
              SPKNotificationItem(kSPKNotificationDownloadAllShare, @"Share All", @"share"),
              SPKNotificationItem(kSPKNotificationDownloadAllGallery, @"Save All to Gallery", @"sparkle_gallery"),
              SPKNotificationItem(kSPKNotificationDownloadAllClipboard, @"Copy All Media", @"copy"),
              SPKNotificationItem(kSPKNotificationDownloadAllLinks, @"Copy Download URLs", @"link"),
              SPKNotificationItem(kSPKNotificationExpand, @"Expand", @"expand"),
              SPKNotificationItem(kSPKNotificationViewThumbnail, @"View Thumbnail", @"photo_gallery"),
              SPKNotificationItem(kSPKNotificationCopyCaption, @"Copy Caption", @"caption"),
              SPKNotificationItem(kSPKNotificationOpenTopicSettings, @"Open Topic Settings", @"settings"),
              SPKNotificationItem(kSPKNotificationRepost, @"Repost", @"repost"),
              SPKNotificationItem(kSPKNotificationDownloadAudio, @"Save Audio to Files", @"audio_download"),
              SPKNotificationItem(kSPKNotificationDownloadAudioShare, @"Share Audio", @"share"),
              SPKNotificationItem(kSPKNotificationDownloadAudioGallery, @"Save Audio to Gallery", @"sparkle_gallery"),
              SPKNotificationItem(kSPKNotificationPlayAudio, @"Play Audio", @"play"),
              SPKNotificationItem(kSPKNotificationCopyAudioURL, @"Copy Audio Download URL", @"link"),
          ]},
        // Every auto-save toast lives here rather than under its surface: they're
        // configured together, and the summary/pending pair isn't per-surface at all.
        @{@"title" : @"Auto-Save",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationStoryAutoSave, @"Story Auto-Save Started", @"story"),
              SPKNotificationItem(kSPKNotificationDirectAutoSave, @"DM Auto-Save Started", @"messages"),
              SPKNotificationItem(kSPKNotificationInstantsAutoSave, @"Instants Auto-Save Started", @"instants"),
              SPKNotificationItem(kSPKNotificationAutoSavePending, @"Auto-Save Still Working", @"history"),
              SPKNotificationItem(kSPKNotificationAutoSaveSummary, @"Auto-Save Summary", @"download"),
              SPKNotificationItem(kSPKNotificationStoryAutoSaveUserRule, @"Story Auto-Save List Changes", @"story"),
              SPKNotificationItem(kSPKNotificationDirectAutoSaveThreadRule, @"DM Auto-Save List Changes", @"messages"),
              SPKNotificationItem(kSPKNotificationInstantsAutoSaveUserRule, @"Instants Auto-Save List Changes", @"instants"),
          ]},
        @{@"title" : @"Stories",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationStoryMarkSeen, @"Mark Story as Seen", @"story"),
              SPKNotificationItem(kSPKNotificationStorySeenUserRule, @"Story Seen List Changes", @"eye"),
              SPKNotificationItem(kSPKNotificationStoryMentionsSheet, @"Open Story Mentions", @"mention"),
          ]},
        @{@"title" : @"Messages",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationDirectVisualMarkSeen, @"Mark Visual Message as Seen", @"view_twice"),
              SPKNotificationItem(kSPKNotificationThreadMessagesMarkSeen, @"Mark Messages as Seen", @"messages"),
              SPKNotificationItem(kSPKNotificationDirectThreadSeenRule, @"Chat Seen List Changes", @"eye"),
              SPKNotificationItem(kSPKNotificationUnsentMessage, @"Unsent Message", @"undo"),
              SPKNotificationItem(kSPKNotificationUnsentReaction, @"Removed Reaction", @"reactions"),
          ]},
        @{@"title" : @"Instants",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationInstantsCaptureBlocked, @"Instant Capture Blocked", @"lock"),
          ]},
        @{@"title" : @"Profile",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationProfileCopyInfo, @"Copy Profile Info", @"copy"),
              SPKNotificationItem(kSPKNotificationProfileAnalyzerComplete, @"Profile Analyzer Complete", @"profile_analyzer"),
              SPKNotificationItem(kSPKNotificationProfileStorySeenUserRule, @"Story Seen List Changes", @"eye"),
              SPKNotificationItem(kSPKNotificationProfileMessagesSeenUserRule, @"Chat Seen List Changes", @"eye"),
          ]},
        @{@"title" : @"Comments",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationCopyComment, @"Copy Comment", @"copy"),
              SPKNotificationItem(kSPKNotificationCopyGIFLink, @"Copy Media Link", @"link"),
          ]},
        @{@"title" : @"Media",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationMediaPreviewSavePhotos, @"Save to Photos", @"download"),
              SPKNotificationItem(kSPKNotificationMediaPreviewSaveGallery, @"Save to Gallery", @"sparkle_gallery"),
              SPKNotificationItem(kSPKNotificationMediaPreviewShare, @"Share", @"share"),
              SPKNotificationItem(kSPKNotificationMediaPreviewCopy, @"Copy Media", @"copy"),
              SPKNotificationItem(kSPKNotificationMediaPreviewDeleteGallery, @"Delete Media", @"trash"),
              SPKNotificationItem(kSPKNotificationMediaPreviewOpenGallery, @"Open Media", @"media"),
              SPKNotificationItem(kSPKNotificationMediaEncodingLogs, @"Encoding Logs", @"logs"),
          ]},
        @{@"title" : @"Gallery",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationGalleryOpenOriginal, @"Open Original Post", @"external_link"),
              SPKNotificationItem(kSPKNotificationGalleryOpenProfile, @"Open Profile", @"user_circle"),
              SPKNotificationItem(kSPKNotificationGalleryDeleteFile, @"Delete File", @"media"),
              SPKNotificationItem(kSPKNotificationGalleryDeleteSelected, @"Delete Selected Files", @"circle_check"),
              SPKNotificationItem(kSPKNotificationGalleryBulkDelete, @"Bulk Delete", @"trash"),
              SPKNotificationItem(kSPKNotificationGalleryImport, @"Import Media", @"media"),
          ]},
        @{@"title" : @"Settings & Tools",
          @"items" : @[
              SPKNotificationItem(kSPKNotificationSettingsExport, @"Export Settings", @"arrow_up"),
              SPKNotificationItem(kSPKNotificationSettingsImport, @"Import Settings", @"arrow_down"),
              SPKNotificationItem(kSPKNotificationSettingsClearCache, @"Clear Cache", @"trash"),
              SPKNotificationItem(kSPKNotificationCopyDescription, @"Copy Description", @"copy"),
              SPKNotificationItem(kSPKNotificationCopyNoteText, @"Copy Note Text", @"copy"),
              SPKNotificationItem(kSPKNotificationShareLongPressCopyLink, @"Hold Send to Copy Link", @"link"),
              SPKNotificationItem(kSPKNotificationFlexUnavailable, @"FLEX Unavailable", @"warning"),
              SPKNotificationItem(kSPKNotificationNotificationLog, @"Notification Log", @"logs"),
          ]},
    ];
}

static BOOL SPKNotificationIdentifierIsRegistered(NSString *identifier) {
    if (identifier.length == 0)
        return NO;
    static NSSet<NSString *> *registeredIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
        for (NSDictionary *section in SPKNotificationPreferenceSections()) {
            for (NSDictionary *item in section[@"items"] ?: @[]) {
                NSString *itemIdentifier = item[@"identifier"];
                if (itemIdentifier.length > 0) {
                    [identifiers addObject:itemIdentifier];
                }
            }
        }
        registeredIdentifiers = [identifiers copy];
    });
    return [registeredIdentifiers containsObject:identifier];
}

NSDictionary<NSString *, id> *SPKNotificationDefaultPreferences(void) {
    NSMutableDictionary *defaults = [@{
        kSPKNotificationPillGlowEnabledKey : @YES,
        kSPKNotificationPillLiquidGlassEnabledKey : @NO,
        kSPKNotificationPillDurationKey : @(kSPKNotificationDefaultPillDuration),
        kSPKNotificationProgressSubtitleStyleKey : @"both",
        kSPKNotificationPillPositionKey : @"top",
    } mutableCopy];
    for (NSDictionary *section in SPKNotificationPreferenceSections()) {
        for (NSDictionary *item in section[@"items"] ?: @[]) {
            defaults[SPKNotificationDefaultsKey(item[@"identifier"])] = @YES;
            defaults[SPKNotificationHapticDefaultsKey(item[@"identifier"])] = @YES;
        }
    }
    return defaults;
}

BOOL SPKNotificationIsEnabled(NSString *identifier) {
    if (!SPKNotificationIdentifierIsRegistered(identifier))
        return NO;
    // Via SPKUtils so per-account toggles resolve (see SPKNotificationPillDuration).
    return [SPKUtils getBoolPref:SPKNotificationDefaultsKey(identifier)];
}

NSTimeInterval SPKNotificationPillDuration(void) {
    // Read through SPKUtils so the per-account effective key resolves — the
    // settings UI writes via SPKEffectivePreferenceKey, so a raw read here would
    // always miss it and fall back to the default when per-account prefs are on.
    NSTimeInterval duration = [SPKUtils getDoublePref:kSPKNotificationPillDurationKey];
    if (duration <= 0.0)
        duration = kSPKNotificationDefaultPillDuration;
    return MIN(kSPKNotificationMaxPillDuration, MAX(kSPKNotificationMinPillDuration, duration));
}

void SPKNotificationTriggerHaptic(NSString *identifier, SPKNotificationTone tone) {
    if (!SPKNotificationIdentifierIsRegistered(identifier))
        return;
    if ([SPKUtils getBoolPref:@"general_disable_haptics"])
        return;
    if (![SPKUtils getBoolPref:SPKNotificationHapticDefaultsKey(identifier)])
        return;

    dispatch_block_t trigger = ^{
        switch (tone) {
        case SPKNotificationToneSuccess: {
            UINotificationFeedbackGenerator *haptic = [[UINotificationFeedbackGenerator alloc] init];
            [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
            break;
        }
        case SPKNotificationToneError: {
            UINotificationFeedbackGenerator *haptic = [[UINotificationFeedbackGenerator alloc] init];
            [haptic notificationOccurred:UINotificationFeedbackTypeError];
            break;
        }
        case SPKNotificationToneInfo:
        default: {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [haptic impactOccurred];
            break;
        }
        }
    };

    if (NSThread.isMainThread)
        trigger();
    else
        dispatch_async(dispatch_get_main_queue(), trigger);
}

SPKNotificationTone SPKNotificationToneForIconResource(NSString *iconResource) {
    if ([iconResource isEqualToString:@"error_filled"] ||
        [iconResource isEqualToString:@"error_circle_filled"])
        return SPKNotificationToneError;
    if ([iconResource isEqualToString:@"circle_check_filled"] ||
        [iconResource isEqualToString:@"copy_filled"]) {
        return SPKNotificationToneSuccess;
    }
    return SPKNotificationToneInfo;
}

static NSString *SPKNotificationIconResourceForTone(NSString *iconResource, SPKNotificationTone tone) {
    switch (tone) {
    case SPKNotificationToneSuccess:
        return @"circle_check_filled";
    case SPKNotificationToneError:
        return @"error_filled";
    case SPKNotificationToneInfo:
    default:
        return iconResource.length ? iconResource : @"info_filled";
    }
}

@interface SPKNotificationCenter ()
@property (nonatomic, strong) NSMutableArray<SPKNotificationSlot *> *visible;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *queue;
@property (nonatomic, strong) SPKNotificationPassthroughWindow *overlayWindow;
@property (nonatomic, strong) SPKNotificationOverlayRootViewController *overlayRoot;
// The pill shown for preparatory work that runs before the real flow starts (e.g.
// the 4K candidate fetch). Weak: it's owned by its slot, and whoever adopts it as a
// real progress pill clears this so it's no longer dismissed out from under them.
@property (nonatomic, weak) SPKNotificationPillView *transientProgressPill;
- (void)notifyIdentifier:(NSString *)identifier
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
            iconResource:(NSString *)iconResource
                    tone:(SPKNotificationTone)tone
           triggerHaptic:(BOOL)triggerHaptic
                   onTap:(void (^)(void))onTap;
@end

// Whether any Sparkle settings UI is on screen — the manual-seen manage lists are
// SPKSettingsViewController subclasses, so this is YES both when that list is open
// and anywhere else in Settings. Used to suppress the "tap to open list" pill
// affordance when the user is already there.
static BOOL SPKNotifTreeHasClass(UIViewController *vc, Class cls, NSMutableSet *seen) {
    if (!vc || [seen containsObject:vc])
        return NO;
    [seen addObject:vc];
    if ([vc isKindOfClass:cls])
        return YES;
    if (SPKNotifTreeHasClass(vc.presentedViewController, cls, seen))
        return YES;
    if ([vc isKindOfClass:UINavigationController.class]) {
        for (UIViewController *child in ((UINavigationController *)vc).viewControllers) {
            if (SPKNotifTreeHasClass(child, cls, seen))
                return YES;
        }
    }
    for (UIViewController *child in vc.childViewControllers) {
        if (SPKNotifTreeHasClass(child, cls, seen))
            return YES;
    }
    return NO;
}

static BOOL SPKManualSeenSettingsUIVisible(void) {
    Class cls = NSClassFromString(@"SPKSettingsViewController");
    if (!cls)
        return NO;
    NSMutableSet *seen = [NSMutableSet set];
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.hidden)
            continue;
        if (SPKNotifTreeHasClass(window.rootViewController, cls, seen))
            return YES;
    }
    return NO;
}

@implementation SPKNotificationCenter

+ (instancetype)shared {
    static SPKNotificationCenter *center;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        center = [SPKNotificationCenter new];
    });
    return center;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
    _visible = [NSMutableArray array];
    _queue = [NSMutableArray array];
    return self;
}

- (UIWindow *)primaryWindow {
    UIViewController *topController = topMostController();
    if (topController.view.window && !topController.view.window.hidden)
        return topController.view.window;
    if (UIApplication.sharedApplication.keyWindow && !UIApplication.sharedApplication.keyWindow.hidden)
        return UIApplication.sharedApplication.keyWindow;
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.alpha > 0.01 && window.windowLevel <= UIWindowLevelAlert)
            return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

- (UIWindowScene *)windowScene {
    UIWindow *window = [self primaryWindow];
    if ([window.windowScene isKindOfClass:UIWindowScene.class])
        return window.windowScene;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class])
            return (UIWindowScene *)scene;
    }
    return nil;
}

- (UIView *)hostView {
    UIWindowScene *scene = [self windowScene];
    if (!scene)
        return [self primaryWindow] ?: topMostController().view;
    if (!self.overlayWindow || self.overlayWindow.windowScene != scene) {
        self.overlayRoot = [SPKNotificationOverlayRootViewController new];
        self.overlayWindow = [[SPKNotificationPassthroughWindow alloc] initWithWindowScene:scene];
        self.overlayWindow.rootViewController = self.overlayRoot;
        self.overlayWindow.backgroundColor = UIColor.clearColor;
        self.overlayWindow.opaque = NO;
        self.overlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
        self.overlayWindow.frame = scene.coordinateSpace.bounds;
    }
    self.overlayRoot.view.frame = self.overlayWindow.bounds;
    self.overlayWindow.hidden = NO;
    return self.overlayRoot.view;
}

- (void)cleanupIfEmpty {
    if (self.visible.count > 0 || self.queue.count > 0)
        return;
    self.overlayWindow.hidden = YES;
    self.overlayWindow.rootViewController = nil;
    self.overlayWindow = nil;
    self.overlayRoot = nil;
}

- (void)onMain:(dispatch_block_t)block {
    if (!block)
        return;
    if (NSThread.isMainThread)
        block();
    else
        dispatch_async(dispatch_get_main_queue(), block);
}

- (CGFloat)offsetForIndex:(NSUInteger)index {
    BOOL isBottom = [[SPKUtils getStringPref:kSPKNotificationPillPositionKey] isEqualToString:@"bottom"];
    CGFloat offset = isBottom ? kSPKNotificationBottomMargin : kSPKNotificationTopMargin;
    for (NSUInteger i = 0; i < index && i < self.visible.count; i++) {
        SPKNotificationPillView *pill = self.visible[i].pill;
        CGFloat height = CGRectGetHeight(pill.bounds);
        if (height < 1.0)
            height = 52.0;
        offset += height + kSPKNotificationStackSpacing;
    }
    return offset;
}

- (void)relayoutAnimated:(BOOL)animated {
    UIView *host = self.overlayRoot.view;
    BOOL isBottom = [[SPKUtils getStringPref:kSPKNotificationPillPositionKey] isEqualToString:@"bottom"];
    for (NSUInteger i = 0; i < self.visible.count; i++) {
        CGFloat offset = [self offsetForIndex:i];
        self.visible[i].topConstraint.constant = isBottom ? -offset : offset;
    }
    void (^layout)(void) = ^{
        [host layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:layout completion:nil];
    } else {
        layout();
    }
}

- (void)insertPill:(SPKNotificationPillView *)pill identifier:(NSString *)identifier progress:(BOOL)progress {
    UIView *host = [self hostView];
    [host addSubview:pill];
    BOOL isBottom = [[SPKUtils getStringPref:kSPKNotificationPillPositionKey] isEqualToString:@"bottom"];
    NSLayoutConstraint *anchor;
    if (isBottom) {
        anchor = [pill.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:90.0];
    } else {
        anchor = [pill.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:-90.0];
    }
    [pill setPresentationTopConstraint:anchor];
    [NSLayoutConstraint activateConstraints:@[
        anchor,
        [pill.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
    ]];

    SPKNotificationSlot *slot = [SPKNotificationSlot new];
    slot.pill = pill;
    slot.topConstraint = anchor;
    slot.identifier = identifier ?: @"";
    slot.progress = progress;
    [self.visible addObject:slot];

    __weak typeof(self) weakSelf = self;
    __weak SPKNotificationSlot *weakSlot = slot;
    pill.onDidDismiss = ^{
        __strong typeof(weakSelf) self = weakSelf;
        SPKNotificationSlot *strongSlot = weakSlot;
        if (!self || !strongSlot)
            return;
        [strongSlot.timer invalidate];
        [self.visible removeObject:strongSlot];
        [self relayoutAnimated:YES];
        [self drainQueue];
        [self cleanupIfEmpty];
    };

    [host layoutIfNeeded];
    pill.alpha = 0.0;
    CGFloat entranceY = isBottom ? 24.0 : -24.0;
    pill.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, entranceY), CGAffineTransformMakeScale(0.88, 0.88));
    anchor.constant = isBottom ? -[self offsetForIndex:self.visible.count - 1] : [self offsetForIndex:self.visible.count - 1];
    [UIView animateWithDuration:kSPKNotificationInsertDuration
                          delay:0
         usingSpringWithDamping:0.78
          initialSpringVelocity:0.85
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         pill.alpha = 1.0;
                         pill.transform = CGAffineTransformIdentity;
                         [self relayoutAnimated:NO];
                     }
                     completion:nil];

    if (!progress) {
        slot.timer = [NSTimer scheduledTimerWithTimeInterval:SPKNotificationPillDuration()
                                                     repeats:NO
                                                       block:^(__unused NSTimer *timer) {
                                                           SPKNotificationSlot *strongSlot = weakSlot;
                                                           if (strongSlot.pill.superview)
                                                               [strongSlot.pill dismiss];
                                                       }];
    }
}

- (void)drainQueue {
    while (self.queue.count > 0) {
        NSUInteger visibleToasts = 0;
        for (SPKNotificationSlot *slot in self.visible) {
            if (!slot.progress)
                visibleToasts++;
        }
        if (visibleToasts >= kSPKNotificationMaxQueuedToasts)
            return;
        NSDictionary *next = self.queue.firstObject;
        [self.queue removeObjectAtIndex:0];
        [self notifyIdentifier:next[@"identifier"]
                         title:next[@"title"]
                      subtitle:next[@"subtitle"]
                  iconResource:next[@"icon"]
                          tone:[next[@"tone"] unsignedIntegerValue]
                 triggerHaptic:NO
                         onTap:next[@"onTap"]];
    }
}

- (void)notifyIdentifier:(NSString *)identifier
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
            iconResource:(NSString *)iconResource
                    tone:(SPKNotificationTone)tone {
    [self notifyIdentifier:identifier title:title subtitle:subtitle iconResource:iconResource tone:tone triggerHaptic:YES onTap:nil];
}

- (void)notifyIdentifier:(NSString *)identifier
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
            iconResource:(NSString *)iconResource
                    tone:(SPKNotificationTone)tone
           triggerHaptic:(BOOL)triggerHaptic
                   onTap:(void (^)(void))onTap {
    if (triggerHaptic) {
        SPKNotificationTriggerHaptic(identifier, tone);
    }
    if (!SPKNotificationIsEnabled(identifier))
        return;
    [self onMain:^{
        NSUInteger visibleToasts = 0;
        for (SPKNotificationSlot *slot in self.visible) {
            if (!slot.progress)
                visibleToasts++;
        }
        if (visibleToasts >= kSPKNotificationMaxQueuedToasts) {
            NSMutableDictionary *queued = [@{
                @"identifier" : identifier ?: @"",
                @"title" : title ?: @"",
                @"subtitle" : subtitle ?: @"",
                @"icon" : SPKNotificationIconResourceForTone(iconResource, tone) ?: @"",
                @"tone" : @(tone),
            } mutableCopy];
            if (onTap)
                queued[@"onTap"] = [onTap copy];
            [self.queue addObject:queued];
            return;
        }
        // When the user is already in the manage list (or anywhere in Settings),
        // don't advertise/enable "tap to open" — there's nothing to open.
        BOOL suppressSeenListTap = SPKManualSeenSettingsUIVisible();
        NSString *resolvedSubtitle = subtitle;
        if (tone == SPKNotificationToneSuccess && !suppressSeenListTap) {
            if ([identifier isEqualToString:kSPKNotificationStorySeenUserRule] ||
                [identifier isEqualToString:kSPKNotificationProfileStorySeenUserRule]) {
                BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"stories_manual_seen"];
                resolvedSubtitle = [NSString stringWithFormat:@"Tap to open %@", manualSeenEnabled ? @"excluded list" : @"included list"];
            } else if ([identifier isEqualToString:kSPKNotificationDirectThreadSeenRule] ||
                       [identifier isEqualToString:kSPKNotificationProfileMessagesSeenUserRule]) {
                BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
                resolvedSubtitle = [NSString stringWithFormat:@"Tap to open %@", manualSeenEnabled ? @"excluded list" : @"included list"];
            } else if (SPKAutoSaveListViewControllerForRuleIdentifier(identifier)) {
                resolvedSubtitle = @"Tap to open auto-save list";
            }
        }

        NSString *resolvedIconResource = SPKNotificationIconResourceForTone(iconResource, tone);
        UIImage *icon = resolvedIconResource.length
                            ? [SPKAssetUtils instagramIconNamed:resolvedIconResource pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                            : nil;
        SPKNotificationPillView *pill = [SPKNotificationPillView toastPillWithTitle:title subtitle:resolvedSubtitle icon:icon tone:tone];

        if (tone == SPKNotificationToneSuccess && !suppressSeenListTap) {
            if ([identifier isEqualToString:kSPKNotificationStorySeenUserRule] ||
                [identifier isEqualToString:kSPKNotificationProfileStorySeenUserRule]) {
                pill.onTapWhenCompleted = ^{
                    [SPKUtils presentViewControllerInSheet:SPKStoryManualSeenListViewController()];
                };
            } else if ([identifier isEqualToString:kSPKNotificationDirectThreadSeenRule] ||
                       [identifier isEqualToString:kSPKNotificationProfileMessagesSeenUserRule]) {
                pill.onTapWhenCompleted = ^{
                    [SPKUtils presentViewControllerInSheet:SPKDirectManualSeenListViewController()];
                };
            } else if (SPKAutoSaveListViewControllerForRuleIdentifier(identifier)) {
                pill.onTapWhenCompleted = ^{
                    // Re-resolved on tap rather than captured: by then the user may have
                    // switched Filter Mode, and the list screen reads its mode at init.
                    UIViewController *list = SPKAutoSaveListViewControllerForRuleIdentifier(identifier);
                    if (list)
                        [SPKUtils presentViewControllerInSheet:list];
                };
            }
        }
        // An explicit tap handler takes precedence over the identifier-based ones.
        if (onTap)
            pill.onTapWhenCompleted = onTap;

        [self insertPill:pill identifier:identifier progress:NO];
    }];
}

- (SPKNotificationPillView *)beginProgressForIdentifier:(NSString *)identifier
                                                  title:(NSString *)title
                                               onCancel:(void (^)(void))onCancel {
    if (!SPKNotificationIsEnabled(identifier))
        return nil;
    return [self beginUnmanagedProgressWithTitle:title onCancel:onCancel];
}

- (SPKNotificationPillView *)beginUnmanagedProgressWithTitle:(NSString *)title
                                                    onCancel:(void (^)(void))onCancel {
    return [self beginUnmanagedProgressWithTitle:title onCancel:onCancel transient:NO];
}

- (SPKNotificationPillView *)beginTransientProgressWithTitle:(NSString *)title
                                                    onCancel:(void (^)(void))onCancel {
    return [self beginUnmanagedProgressWithTitle:title onCancel:onCancel transient:YES];
}

- (void)dismissTransientProgressPill {
    dispatch_block_t dismiss = ^{
        SPKNotificationPillView *pill = self.transientProgressPill;
        self.transientProgressPill = nil;
        if (pill && pill.superview)
            [pill dismiss];
    };
    if (NSThread.isMainThread)
        dismiss();
    else
        dispatch_async(dispatch_get_main_queue(), dismiss);
}

- (SPKNotificationPillView *)beginUnmanagedProgressWithTitle:(NSString *)title
                                                    onCancel:(void (^)(void))onCancel
                                                   transient:(BOOL)transient {
    __block SPKNotificationPillView *pill = nil;
    dispatch_block_t create = ^{
        for (SPKNotificationSlot *slot in self.visible) {
            if (slot.progress && slot.pill && slot.pill.superview) {
                pill = slot.pill;
                if (title.length > 0) {
                    [pill updateProgressTitle:title subtitle:nil];
                }
                if (onCancel) {
                    pill.onCancel = onCancel;
                }
                // Reusing a live progress pill means a real flow now owns it (either
                // it was already real, or a transient pill just morphed into one), so
                // it must no longer be dismissed as transient.
                self.transientProgressPill = nil;
                return;
            }
        }
        pill = [SPKNotificationPillView progressPill];
        [pill updateProgressTitle:title ?: @"Downloading..." subtitle:nil];
        pill.onCancel = onCancel;
        __weak SPKNotificationPillView *weakPillRef = pill;
        pill.onTonePresented = ^(SPKNotificationTone tone) {
            if (![SPKUtils getBoolPref:@"general_disable_haptics"]) {
                UINotificationFeedbackGenerator *haptic = [[UINotificationFeedbackGenerator alloc] init];
                if (tone == SPKNotificationToneError)
                    [haptic notificationOccurred:UINotificationFeedbackTypeError];
                else if (tone == SPKNotificationToneSuccess)
                    [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
                else
                    [haptic notificationOccurred:UINotificationFeedbackTypeWarning];
            }
            // Auto-dismiss progress pills in terminal state after the configured duration.
            NSTimeInterval duration = SPKNotificationPillDuration();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SPKNotificationPillView *p = weakPillRef;
                if (p && p.superview)
                    [p dismiss];
            });
        };
        self.transientProgressPill = transient ? pill : nil;
        // Prep work is a single request with nothing to report: spin instead of
        // sitting at 0%. The download that adopts this pill flips it back.
        if (transient)
            [pill setProgressIndeterminate:YES];
        [self insertPill:pill identifier:@"download_queue_aggregate" progress:YES];
    };
    if (NSThread.isMainThread)
        create();
    else
        dispatch_sync(dispatch_get_main_queue(), create);
    return pill;
}

@end

void SPKNotify(NSString *identifier,
               NSString *title,
               NSString *subtitle,
               NSString *iconResource,
               SPKNotificationTone tone) {
    [[SPKNotificationCenter shared] notifyIdentifier:identifier title:title subtitle:subtitle iconResource:iconResource tone:tone];
}

void SPKNotifyTappable(NSString *identifier,
                       NSString *title,
                       NSString *subtitle,
                       NSString *iconResource,
                       SPKNotificationTone tone,
                       void (^onTap)(void)) {
    [[SPKNotificationCenter shared] notifyIdentifier:identifier title:title subtitle:subtitle iconResource:iconResource tone:tone triggerHaptic:YES onTap:onTap];
}

SPKNotificationPillView *SPKNotifyProgress(NSString *identifier, NSString *title, void (^onCancel)(void)) {
    return [[SPKNotificationCenter shared] beginProgressForIdentifier:identifier title:title onCancel:onCancel];
}
