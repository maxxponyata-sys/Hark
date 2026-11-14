#import "HKCore.h"
#import <Security/Security.h>

UIColor *HKAccent(void) { return [UIColor colorWithRed:0.85 green:0.47 blue:0.34 alpha:1.0]; }

#define HKDefaults [NSUserDefaults standardUserDefaults]

static NSString *const HKKeychainService = @"app.hark.anthropic";
static NSString *const HKKeychainAccount = @"api-key";

static NSMutableDictionary *HKKeychainQuery(void) {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: HKKeychainService,
              (__bridge id)kSecAttrAccount: HKKeychainAccount} mutableCopy];
}

@implementation HKSettings

+ (void)initialize {
    if (self != [HKSettings class]) return;
    [HKDefaults registerDefaults:@{@"speakReplies": @YES, @"conversationMode": @YES, @"webSearch": @YES,
                                   @"shareLocation": @YES, @"shareCalendar": @YES}];
}

+ (NSString *)apiKey {
    NSMutableDictionary *q = HKKeychainQuery();
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (void)setAPIKey:(NSString *)key {
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    SecItemDelete((__bridge CFDictionaryRef)HKKeychainQuery());
    if (!key.length) return;
    NSMutableDictionary *q = HKKeychainQuery();
    q[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)q, NULL);
}

+ (NSArray<NSDictionary *> *)availableModels {
    return @[
        @{@"id": @"claude-opus-5-5", @"name": @"Claude Opus 5.5", @"note": @"Smartest (default)"},
        @{@"id": @"claude-sonnet-5-5", @"name": @"Claude Sonnet 5.5", @"note": @"Faster, cheaper"},
        @{@"id": @"claude-haiku-5-5", @"name": @"Claude Haiku 5.5", @"note": @"Fastest, cheapest"},
    ];
}

+ (NSString *)model {
    NSString *m = [HKDefaults stringForKey:@"model"];
    return m.length ? m : @"claude-opus-5-5";
}
+ (void)setModel:(NSString *)model { [HKDefaults setObject:model forKey:@"model"]; }

+ (NSString *)language {
    NSString *l = [HKDefaults stringForKey:@"language"];
    if (l.length) return l;
    NSString *pref = [NSLocale preferredLanguages].firstObject ?: @"en-US";
    // "ru" or "ru-RU" → "ru-RU"; speech APIs want a region.
    NSArray *parts = [pref componentsSeparatedByString:@"-"];
    NSString *lang = parts.firstObject;
    NSString *region = parts.count > 1 ? parts.lastObject : [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    if ([lang isEqualToString:@"ru"] && region.length != 2) region = @"RU";
    if ([lang isEqualToString:@"en"] && region.length != 2) region = @"US";
    return region.length == 2 ? [NSString stringWithFormat:@"%@-%@", lang, region.uppercaseString] : lang;
}
+ (void)setLanguage:(NSString *)language {
    if (language.length) [HKDefaults setObject:language forKey:@"language"];
    else [HKDefaults removeObjectForKey:@"language"];
}

+ (BOOL)speakReplies { return [HKDefaults boolForKey:@"speakReplies"]; }
+ (void)setSpeakReplies:(BOOL)on { [HKDefaults setBool:on forKey:@"speakReplies"]; }
+ (BOOL)conversationMode { return [HKDefaults boolForKey:@"conversationMode"]; }
+ (void)setConversationMode:(BOOL)on { [HKDefaults setBool:on forKey:@"conversationMode"]; }
+ (BOOL)webSearch { return [HKDefaults boolForKey:@"webSearch"]; }
+ (void)setWebSearch:(BOOL)on { [HKDefaults setBool:on forKey:@"webSearch"]; }
+ (BOOL)shareLocation { return [HKDefaults boolForKey:@"shareLocation"]; }
+ (void)setShareLocation:(BOOL)on { [HKDefaults setBool:on forKey:@"shareLocation"]; }
+ (BOOL)shareCalendar { return [HKDefaults boolForKey:@"shareCalendar"]; }
+ (void)setShareCalendar:(BOOL)on { [HKDefaults setBool:on forKey:@"shareCalendar"]; }
+ (NSString *)customInstructions { return [HKDefaults stringForKey:@"customInstructions"] ?: @""; }
+ (void)setCustomInstructions:(NSString *)text { [HKDefaults setObject:text ?: @"" forKey:@"customInstructions"]; }

@end
