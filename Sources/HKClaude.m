#import "HKCore.h"
#import <Security/Security.h>

#pragma mark - Networking (TLS roots for iOS 10)

static NSArray *HKAnchors(void) {
    static NSArray *anchors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *name in @[@"gtsr1", @"gtsr4"]) {
            NSData *d = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:name ofType:@"der"]];
            SecCertificateRef c = d ? SecCertificateCreateWithData(NULL, (__bridge CFDataRef)d) : NULL;
            if (c) [list addObject:(__bridge_transfer id)c];
        }
        anchors = list;
    });
    return anchors;
}

static BOOL HKTrustPasses(SecTrustRef trust) {
    SecTrustResultType r = kSecTrustResultInvalid;
    return SecTrustEvaluate(trust, &r) == errSecSuccess && (r == kSecTrustResultUnspecified || r == kSecTrustResultProceed);
}

@implementation HKNetwork

+ (instancetype)shared {
    static HKNetwork *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 120;
        cfg.URLCache = nil;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    }
    return self;
}

// api.anthropic.com chains to GlobalSign Root CA, which iOS 10 trusts; the bundled
// Google Trust Services roots are a fallback in case that cross-signature goes away.
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    BOOL ok = HKTrustPasses(trust);
    if (!ok && HKAnchors().count) {
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)HKAnchors());
        SecTrustSetAnchorCertificatesOnly(trust, false);
        ok = HKTrustPasses(trust);
    }
    if (ok) completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
    else completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}

@end

#pragma mark - Claude

static NSString *const HKAPIURL = @"https://api.anthropic.com/v1/messages";
static NSString *const HKAPIVersion = @"2026-10-21";
static NSString *const HKFallbackBeta = @"server-side-fallback-2026-07-01";

static NSError *HKError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"Hark" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation HKClaude {
    NSMutableArray *_messages;     // conversation, appended to only (assistant content kept verbatim)
    NSURLSessionDataTask *_task;
    NSUInteger _generation;
}

+ (instancetype)shared {
    static HKClaude *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) _messages = [NSMutableArray array];
    return self;
}

- (NSUInteger)turnCount { return _messages.count; }

- (void)reset {
    [self cancel];
    [_messages removeAllObjects];
}

- (void)cancel {
    _generation++;
    [_task cancel];
    _task = nil;
}

- (NSString *)systemPrompt {
    NSMutableString *s = [NSMutableString stringWithString:
        @"You are Hark, a voice assistant running on the user's iPhone or iPad (iOS 10). "
        @"Your replies are read aloud by text-to-speech, so write the way a person speaks: answer in the language the user speaks, "
        @"conversationally and briefly (usually one to three sentences; longer only when the user asks for detail). "
        @"Never use markdown, bullet lists, headings, emoji, tables, code or raw URLs; say numbers, units and symbols the way they are spoken.\n\n"
        @"Each user message starts with a <device_status> block captured at that moment: time, battery, network, storage, "
        @"brightness, volume, location, calendar and music, when available. Use it to answer questions about the device, the time "
        @"or the user's day, and to make answers relevant (for example local time and place). Don't recite it unless asked.\n\n"
        @"You can't operate the phone: you can't call, text, set alarms, open apps or change settings. If asked, say so in a "
        @"sentence and tell the user how to do it themselves. "];
    if ([HKSettings webSearch])
        [s appendString:@"Use web search for anything current or local: news, weather, prices, opening hours, sports results. Keep the spoken answer short and don't read out sources."];
    else
        [s appendString:@"You have no internet access; if a question needs current information, say that briefly."];
    NSString *custom = [[HKSettings customInstructions] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (custom.length) [s appendFormat:@"\n\nThe user's own instructions:\n%@", custom];
    return s;
}

- (NSDictionary *)requestBody {
    NSString *model = [HKSettings model];
    NSMutableDictionary *body = [@{
        @"model": model,
        @"max_tokens": @16000,
        @"system": [self systemPrompt],
        @"messages": _messages,
        @"output_config": @{@"effort": @"low"},   // voice: answer fast
    } mutableCopy];
    if ([HKSettings webSearch]) {
        BOOL haiku = [model hasPrefix:@"claude-haiku"];
        NSMutableDictionary *tool = [@{@"type": haiku ? @"web_search_20250305" : @"web_search_20260209",
                                       @"name": @"web_search", @"max_uses": @3} mutableCopy];
        NSMutableDictionary *loc = [[[HKDeviceStatus shared] approximateLocation] mutableCopy];
        if (loc.count) { loc[@"type"] = @"approximate"; tool[@"user_location"] = loc; }
        body[@"tools"] = @[tool];
    }
    if ([self usesFallbacks:model]) body[@"fallbacks"] = @"default";
    return body;
}

// Server-side refusal fallbacks exist for Opus 5.5 and Sonnet 5.5, not for Haiku 5.5.
- (BOOL)usesFallbacks:(NSString *)model { return ![model hasPrefix:@"claude-haiku"]; }

- (void)ask:(NSString *)text completion:(void (^)(NSString *, NSError *))completion {
    NSString *key = [HKSettings apiKey];
    if (!key.length) {
        completion(nil, HKError(401, @"Add your Anthropic API key in Settings first."));
        return;
    }
    [self cancel];
    NSString *status = [[HKDeviceStatus shared] snapshot];
    NSString *content = [NSString stringWithFormat:@"<device_status>\n%@\n</device_status>\n\n%@", status, text];
    [_messages addObject:@{@"role": @"user", @"content": @[@{@"type": @"text", @"text": content}]}];
    NSUInteger userIndex = _messages.count - 1;
    NSMutableString *reply = [NSMutableString string];
    [self sendWithKey:key generation:_generation continuations:0 reply:reply completion:^(NSString *answer, NSError *error) {
        if (error && self->_messages.count == userIndex + 1) {
            // The request failed before any reply: drop the unanswered question so the
            // conversation keeps alternating user/assistant turns.
            [self->_messages removeLastObject];
        }
        completion(answer, error);
    }];
}

- (void)sendWithKey:(NSString *)key generation:(NSUInteger)generation continuations:(NSUInteger)continuations
              reply:(NSMutableString *)reply completion:(void (^)(NSString *, NSError *))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:HKAPIURL]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 120;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:key forHTTPHeaderField:@"x-api-key"];
    [req setValue:HKAPIVersion forHTTPHeaderField:@"anthropic-version"];
    if ([self usesFallbacks:[HKSettings model]]) [req setValue:HKFallbackBeta forHTTPHeaderField:@"anthropic-beta"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:[self requestBody] options:0 error:NULL];

    __weak HKClaude *weakSelf = self;
    _task = [[HKNetwork shared].session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *netError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            HKClaude *s = weakSelf;
            if (!s || generation != s->_generation) return;   // cancelled or superseded
            s->_task = nil;
            if (netError) {
                NSString *msg = netError.code == NSURLErrorNotConnectedToInternet ? @"No internet connection." : netError.localizedDescription;
                completion(nil, HKError(netError.code, msg));
                return;
            }
            NSInteger code = [(NSHTTPURLResponse *)response statusCode];
            NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (![json isKindOfClass:[NSDictionary class]]) json = nil;
            if (code != 200 || !json) {
                NSDictionary *err = [json[@"error"] isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
                NSString *msg = [err[@"message"] isKindOfClass:[NSString class]] ? err[@"message"] : [NSString stringWithFormat:@"HTTP %ld", (long)code];
                if (code == 401) msg = @"The API key was rejected. Check it in Settings.";
                else if (code == 429) msg = @"Too many requests right now. Try again in a moment.";
                else if (code == 529 || code >= 500) msg = @"Claude is overloaded right now. Try again in a moment.";
                completion(nil, HKError(code, msg));
                return;
            }

            NSArray *content = [json[@"content"] isKindOfClass:[NSArray class]] ? json[@"content"] : @[];
            for (NSDictionary *block in content) {
                if ([block isKindOfClass:[NSDictionary class]] && [block[@"type"] isEqual:@"text"] && [block[@"text"] isKindOfClass:[NSString class]])
                    [reply appendString:block[@"text"]];
            }
            // Keep the assistant turn exactly as returned (thinking, search and fallback blocks included).
            [s->_messages addObject:@{@"role": @"assistant", @"content": content}];

            NSString *stop = [json[@"stop_reason"] description];
            if ([stop isEqualToString:@"pause_turn"] && continuations < 4) {
                // A long server-tool turn paused; send the conversation back to let it continue.
                [s sendWithKey:key generation:generation continuations:continuations + 1 reply:reply completion:completion];
                return;
            }
            if ([stop isEqualToString:@"refusal"]) {
                completion(reply.length ? reply : @"Sorry, I can't help with that.", nil);
                return;
            }
            NSString *answer = [reply stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            completion(answer.length ? answer : @"…", nil);
        });
    }];
    [_task resume];
}

@end
