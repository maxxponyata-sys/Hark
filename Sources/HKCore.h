// Hark — a Claude voice assistant for iOS 10.
// Core: settings + keychain, device status, Claude client, voice in/out.

#import <UIKit/UIKit.h>

#define HK_VERSION @"1.0.0"
#define HK_SOURCE_URL @"https://github.com/maxxponyata-sys/Hark"

UIColor *HKAccent(void);

#pragma mark - Settings

@interface HKSettings : NSObject
+ (NSString *)apiKey;                    // stored in the keychain
+ (void)setAPIKey:(NSString *)key;
+ (NSString *)model;                     // claude-opus-5-5 by default
+ (void)setModel:(NSString *)model;
+ (NSArray<NSDictionary *> *)availableModels;   // @{id, name, note}
+ (NSString *)language;                  // BCP-47, e.g. "ru-RU"; device language by default
+ (void)setLanguage:(NSString *)language;
+ (BOOL)speakReplies;
+ (void)setSpeakReplies:(BOOL)on;
+ (BOOL)conversationMode;                // listen again after replying
+ (void)setConversationMode:(BOOL)on;
+ (BOOL)webSearch;
+ (void)setWebSearch:(BOOL)on;
+ (BOOL)shareLocation;
+ (void)setShareLocation:(BOOL)on;
+ (BOOL)shareCalendar;
+ (void)setShareCalendar:(BOOL)on;
+ (NSString *)customInstructions;
+ (void)setCustomInstructions:(NSString *)text;
@end

#pragma mark - Device status

@interface HKDeviceStatus : NSObject
+ (instancetype)shared;
- (void)requestPermissions;             // location / calendar / music, per settings
- (NSString *)snapshot;                 // human-readable status block for the model
- (NSDictionary *)approximateLocation;  // for web search: city / region / country / timezone
@end

#pragma mark - Claude

@interface HKClaude : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSUInteger turnCount;
- (void)reset;
// Sends one user turn; completion runs on the main queue with the reply text.
- (void)ask:(NSString *)text completion:(void (^)(NSString *reply, NSError *error))completion;
- (void)cancel;
@end

#pragma mark - Voice

@protocol HKVoiceDelegate <NSObject>
- (void)voiceDidHearPartial:(NSString *)text;
- (void)voiceDidFinishListening:(NSString *)text error:(NSError *)error;   // empty text = nothing said
- (void)voiceDidFinishSpeaking;
@optional
- (void)voiceLevel:(float)level;   // 0…1 microphone level while listening
@end

@interface HKVoice : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) id<HKVoiceDelegate> delegate;
@property (nonatomic, readonly) BOOL listening;
@property (nonatomic, readonly) BOOL speaking;
- (void)requestPermissions:(void (^)(BOOL granted, NSString *problem))completion;
- (void)startListening;
- (void)stopListening;                  // finishes with what was heard so far
- (void)speak:(NSString *)text;
- (void)stopSpeaking;
@end

#pragma mark - Networking

@interface HKNetwork : NSObject <NSURLSessionDelegate>
+ (instancetype)shared;
@property (nonatomic, readonly) NSURLSession *session;
@end
