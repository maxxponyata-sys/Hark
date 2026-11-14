#import "HKUI.h"

@implementation HKAppDelegate {
    HKMainViewController *_main;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _main = [HKMainViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:_main];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = HKAccent();
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = HKAccent();
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    // Opening Hark (from the home screen, "Hey Siri, open Hark", or the Siri button tweak) starts listening.
    [_main listenNow];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
    if ([url.scheme isEqualToString:@"hark"]) {
        UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
        [nav popToRootViewControllerAnimated:NO];
        [_main listenNow];
        return YES;
    }
    return NO;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    if (nav.topViewController == _main) [_main listenNow];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HKAppDelegate class]));
    }
}
