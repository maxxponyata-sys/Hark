// HarkSiri — holding the Home button opens Hark instead of Siri (iOS 10).
//
// iOS 10 SpringBoard routes the Siri button through SBAssistantController's
// handleSiriButtonDownEventFromSource:activationEvent: / handleSiriButtonUpEventFromSource:.
// We take the press when Hark is installed and the device is unlocked; otherwise
// (Hark missing, lock screen, Siri already on screen, or disabled in the prefs
// file) the press goes to Siri as usual.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SBAssistantController : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isAssistantVisible;
- (BOOL)handleSiriButtonDownEventFromSource:(NSInteger)source activationEvent:(NSInteger)event;
- (void)handleSiriButtonUpEventFromSource:(NSInteger)source;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

@interface SpringBoard : UIApplication
- (void)applicationOpenURL:(NSURL *)url;
@end

static NSString *const HSPrefsPath = @"/var/mobile/Library/Preferences/app.hark.siri.plist";
static BOOL HSTookDown = NO;

static NSURL *HSListenURL(void) { return [NSURL URLWithString:@"hark://listen"]; }

static BOOL HSDeviceLocked(void) {
    Class cls = objc_getClass("SBLockScreenManager");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return NO;
    SBLockScreenManager *mgr = [cls sharedInstance];
    return [mgr respondsToSelector:@selector(isUILocked)] && [mgr isUILocked];
}

static BOOL HSShouldTakeOver(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:HSPrefsPath];
    if (prefs[@"enabled"] && ![prefs[@"enabled"] boolValue]) return NO;
    Class cls = objc_getClass("SBAssistantController");
    if ([cls respondsToSelector:@selector(isAssistantVisible)] && [cls isAssistantVisible]) return NO;
    if (HSDeviceLocked()) return NO;
    return [[UIApplication sharedApplication] canOpenURL:HSListenURL()];
}

static void HSOpenHark(void) {
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(applicationOpenURL:)]) [sb applicationOpenURL:HSListenURL()];
    else [sb openURL:HSListenURL() options:@{} completionHandler:nil];
}

%hook SBAssistantController

- (BOOL)handleSiriButtonDownEventFromSource:(NSInteger)source activationEvent:(NSInteger)event {
    if (HSShouldTakeOver()) {
        HSTookDown = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ HSOpenHark(); });
        return YES;
    }
    HSTookDown = NO;
    return %orig;
}

- (void)handleSiriButtonUpEventFromSource:(NSInteger)source {
    if (HSTookDown) { HSTookDown = NO; return; }
    %orig;
}

%end

%ctor {
    // Only hook on iOS versions that have the iOS 10 selector; elsewhere leave Siri alone.
    Class cls = objc_getClass("SBAssistantController");
    if (cls && [cls instancesRespondToSelector:@selector(handleSiriButtonDownEventFromSource:activationEvent:)]
            && [cls instancesRespondToSelector:@selector(handleSiriButtonUpEventFromSource:)]) {
        %init;
    }
}
