#import "HKCore.h"

@interface HKAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@interface HKOrbView : UIView
@property (nonatomic) float level;          // 0…1, drives the pulse while listening
@property (nonatomic) NSInteger mode;       // 0 idle, 1 listening, 2 thinking, 3 speaking
@end

@interface HKMainViewController : UIViewController <HKVoiceDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
- (void)listenNow;                          // called when launched from the Siri button or hark://listen
@end

@interface HKSettingsViewController : UITableViewController <UITextFieldDelegate, UITextViewDelegate>
@end
