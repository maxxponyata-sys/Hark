#import "HKCore.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

static const NSTimeInterval HKSilenceAfterSpeech = 1.4;   // stop this long after the last recognised word
static const NSTimeInterval HKNoSpeechTimeout = 7.0;      // give up if nothing is said
static const NSTimeInterval HKMaxListen = 30.0;

@interface HKVoice () <AVSpeechSynthesizerDelegate>
@end

@implementation HKVoice {
    AVAudioEngine *_engine;
    SFSpeechRecognizer *_recognizer;
    SFSpeechAudioBufferRecognitionRequest *_request;
    SFSpeechRecognitionTask *_task;
    NSTimer *_silenceTimer;
    NSTimer *_maxTimer;
    NSString *_heard;
    BOOL _finishing;
    BOOL _tapInstalled;
    AVSpeechSynthesizer *_synth;
    NSUInteger _pendingUtterances;
}

+ (instancetype)shared {
    static HKVoice *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _engine = [AVAudioEngine new];
        _synth = [AVSpeechSynthesizer new];
        _synth.delegate = self;
    }
    return self;
}

- (void)requestPermissions:(void (^)(BOOL, NSString *))completion {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                completion(NO, @"Hark needs Speech Recognition access. Turn it on in Settings → Privacy → Speech Recognition.");
                return;
            }
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(granted, granted ? nil : @"Hark needs the microphone. Turn it on in Settings → Privacy → Microphone.");
                });
            }];
        });
    }];
}

#pragma mark Listening

- (void)startListening {
    if (_listening) return;
    [self stopSpeaking];

    NSString *lang = [HKSettings language];
    _recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:lang]];
    if (!_recognizer) _recognizer = [SFSpeechRecognizer new];
    if (!_recognizer.isAvailable) {
        [self.delegate voiceDidFinishListening:@"" error:[NSError errorWithDomain:@"Hark" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition isn't available right now (it needs an internet connection)."}]];
        return;
    }

    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth error:&error];
    [session setMode:AVAudioSessionModeMeasurement error:NULL];
    [session setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) { [self.delegate voiceDidFinishListening:@"" error:error]; return; }

    _request = [SFSpeechAudioBufferRecognitionRequest new];
    _request.shouldReportPartialResults = YES;
    _request.taskHint = SFSpeechRecognitionTaskHintDictation;
    _heard = @"";
    _finishing = NO;

    AVAudioInputNode *input = _engine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (!input || format.sampleRate <= 0 || format.channelCount == 0) {
        [self.delegate voiceDidFinishListening:@"" error:[NSError errorWithDomain:@"Hark" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"The microphone isn't available."}]];
        return;
    }
    if (_tapInstalled) { [input removeTapOnBus:0]; _tapInstalled = NO; }
    SFSpeechAudioBufferRecognitionRequest *request = _request;
    __weak HKVoice *weakSelf = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [request appendAudioPCMBuffer:buffer];
        // Rough level meter for the UI.
        float *samples = buffer.floatChannelData ? buffer.floatChannelData[0] : NULL;
        if (!samples || buffer.frameLength == 0) return;
        float sum = 0;
        for (AVAudioFrameCount i = 0; i < buffer.frameLength; i++) sum += samples[i] * samples[i];
        float rms = sqrtf(sum / buffer.frameLength);
        float level = MIN(1.0f, MAX(0.0f, (20.0f * log10f(MAX(rms, 1e-6f)) + 50.0f) / 40.0f));
        dispatch_async(dispatch_get_main_queue(), ^{
            HKVoice *s = weakSelf;
            if (s.listening && [s.delegate respondsToSelector:@selector(voiceLevel:)]) [s.delegate voiceLevel:level];
        });
    }];
    _tapInstalled = YES;

    [_engine prepare];
    if (![_engine startAndReturnError:&error]) {
        [self cleanupAudio];
        [self.delegate voiceDidFinishListening:@"" error:error];
        return;
    }
    _listening = YES;

    _task = [_recognizer recognitionTaskWithRequest:_request resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            HKVoice *s = weakSelf;
            if (!s || !s->_listening) return;
            if (result) {
                s->_heard = result.bestTranscription.formattedString ?: @"";
                [s.delegate voiceDidHearPartial:s->_heard];
                [s armSilenceTimer:HKSilenceAfterSpeech];
                if (result.isFinal) { [s finishWithError:nil]; return; }
            }
            if (err) [s finishWithError:s->_heard.length ? nil : err];
        });
    }];
    [self armSilenceTimer:HKNoSpeechTimeout];
    _maxTimer = [NSTimer scheduledTimerWithTimeInterval:HKMaxListen target:self selector:@selector(stopListening) userInfo:nil repeats:NO];
}

- (void)armSilenceTimer:(NSTimeInterval)interval {
    [_silenceTimer invalidate];
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(stopListening) userInfo:nil repeats:NO];
}

- (void)stopListening {
    if (_listening) [self finishWithError:nil];
}

- (void)finishWithError:(NSError *)error {
    if (_finishing) return;
    _finishing = YES;
    _listening = NO;
    [_silenceTimer invalidate]; _silenceTimer = nil;
    [_maxTimer invalidate]; _maxTimer = nil;
    [_request endAudio];
    [_task cancel];
    _task = nil;
    _request = nil;
    [self cleanupAudio];
    NSString *text = [_heard stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    // "No speech detected" style errors aren't worth showing when the user simply said nothing.
    if (error && [error.domain isEqualToString:@"kAFAssistantErrorDomain"]) error = nil;
    [self.delegate voiceDidFinishListening:text error:error];
}

- (void)cleanupAudio {
    if (_engine.isRunning) [_engine stop];
    if (_tapInstalled) { [_engine.inputNode removeTapOnBus:0]; _tapInstalled = NO; }
    [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeDefault error:NULL];
}

#pragma mark Speaking

- (void)speak:(NSString *)text {
    if (!text.length) { [self.delegate voiceDidFinishSpeaking]; return; }
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth error:NULL];
    [session setActive:YES error:NULL];

    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    NSString *lang = [HKSettings language];
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:lang];
    if (!voice) voice = [AVSpeechSynthesisVoice voiceWithLanguage:[lang componentsSeparatedByString:@"-"].firstObject];
    // Prefer an enhanced-quality voice if one is downloaded.
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        if ([v.language isEqualToString:voice.language] && v.quality == AVSpeechSynthesisVoiceQualityEnhanced) { voice = v; break; }
    }
    u.voice = voice;
    u.rate = AVSpeechUtteranceDefaultSpeechRate;
    _speaking = YES;
    _pendingUtterances++;
    [_synth speakUtterance:u];
}

- (void)stopSpeaking {
    if (_synth.isSpeaking) [_synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance { [self utteranceEnded]; }
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance { [self utteranceEnded]; }

- (void)utteranceEnded {
    if (_pendingUtterances > 0) _pendingUtterances--;
    if (_pendingUtterances > 0) return;
    _speaking = NO;
    [self.delegate voiceDidFinishSpeaking];
}

@end
