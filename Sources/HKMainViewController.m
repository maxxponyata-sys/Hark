#import "HKUI.h"

typedef NS_ENUM(NSInteger, HKState) { HKStateIdle, HKStateListening, HKStateThinking, HKStateSpeaking };

#pragma mark - Orb

@implementation HKOrbView {
    CAShapeLayer *_core;
    CAShapeLayer *_ring;
    CADisplayLink *_link;
    CGFloat _phase;
    CGFloat _smoothed;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _ring = [CAShapeLayer layer];
        _ring.fillColor = [HKAccent() colorWithAlphaComponent:0.18].CGColor;
        [self.layer addSublayer:_ring];
        _core = [CAShapeLayer layer];
        _core.fillColor = HKAccent().CGColor;
        _core.shadowColor = HKAccent().CGColor;
        _core.shadowOpacity = 0.6;
        _core.shadowRadius = 18;
        _core.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_core];
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        _link.preferredFramesPerSecond = 30;
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.accessibilityLabel = @"Talk";
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.isAccessibilityElement = YES;
    }
    return self;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    _link.paused = newWindow == nil;
}

- (void)removeFromSuperview {
    [_link invalidate];
    [super removeFromSuperview];
}

- (void)tick {
    _phase += 0.08;
    CGFloat target = 0;
    if (_mode == 1) target = _level;
    else if (_mode == 2) target = 0.35 + 0.25 * sin(_phase * 2.2);
    else if (_mode == 3) target = 0.3 + 0.3 * fabs(sin(_phase * 3.1)) * fabs(cos(_phase * 1.3));
    else target = 0.06 + 0.04 * sin(_phase);
    _smoothed += (target - _smoothed) * 0.25;

    CGRect b = self.bounds;
    CGPoint c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    CGFloat base = MIN(b.size.width, b.size.height) * 0.30;
    CGFloat core = base * (1.0 + _smoothed * 0.18);
    CGFloat ring = base * (1.15 + _smoothed * 0.55);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _core.path = [UIBezierPath bezierPathWithArcCenter:c radius:core startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
    _ring.path = [UIBezierPath bezierPathWithArcCenter:c radius:ring startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
    _core.fillColor = (_mode == 2 ? [HKAccent() colorWithAlphaComponent:0.75] : HKAccent()).CGColor;
    [CATransaction commit];
}

@end

#pragma mark - Bubble cell

@interface HKBubbleCell : UITableViewCell
+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;
- (void)setText:(NSString *)text fromUser:(BOOL)user;
@end

@implementation HKBubbleCell {
    UIView *_bubble;
    UILabel *_label;
    BOOL _user;
}

static const CGFloat HKBubblePad = 12, HKBubbleMargin = 14, HKBubbleMaxRatio = 0.8;

+ (UIFont *)font { return [UIFont systemFontOfSize:16]; }

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    CGFloat maxW = floor(width * HKBubbleMaxRatio) - HKBubblePad * 2;
    CGRect r = [text boundingRectWithSize:CGSizeMake(maxW, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{NSFontAttributeName: [self font]} context:nil];
    return ceil(r.size.height) + HKBubblePad * 2 + 8;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [UIView new];
        _bubble.layer.cornerRadius = 16;
        [self.contentView addSubview:_bubble];
        _label = [UILabel new];
        _label.font = [HKBubbleCell font];
        _label.numberOfLines = 0;
        [_bubble addSubview:_label];
    }
    return self;
}

- (void)setText:(NSString *)text fromUser:(BOOL)user {
    _user = user;
    _label.text = text;
    _label.textColor = user ? [UIColor whiteColor] : [UIColor colorWithWhite:0.93 alpha:1];
    _bubble.backgroundColor = user ? HKAccent() : [UIColor colorWithWhite:0.17 alpha:1];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat maxW = floor(w * HKBubbleMaxRatio) - HKBubblePad * 2;
    CGSize s = [_label sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
    s.width = MIN(ceil(s.width), maxW);
    s.height = ceil(s.height);
    CGFloat bw = s.width + HKBubblePad * 2, bh = s.height + HKBubblePad * 2;
    CGFloat x = _user ? w - bw - HKBubbleMargin : HKBubbleMargin;
    _bubble.frame = CGRectMake(x, 4, bw, bh);
    _label.frame = CGRectMake(HKBubblePad, HKBubblePad, s.width, s.height);
}

@end

#pragma mark - Main screen

@implementation HKMainViewController {
    UITableView *_table;
    HKOrbView *_orb;
    UILabel *_status;
    UILabel *_live;              // what the recogniser hears, live
    UIView *_inputBar;
    UITextField *_field;
    NSMutableArray<NSDictionary *> *_items;   // @{user: @YES/@NO, text}
    HKState _state;
    BOOL _followUp;              // listening right after a spoken reply
    BOOL _autoListenAfterSpeech;
    BOOL _permissionsAsked;
    BOOL _pendingListen;
    CGFloat _keyboardHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hark";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1];
    _items = [NSMutableArray array];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newChat)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Settings" style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_table registerClass:[HKBubbleCell class] forCellReuseIdentifier:@"b"];
    [self.view addSubview:_table];

    _live = [UILabel new];
    _live.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    _live.font = [UIFont systemFontOfSize:20 weight:UIFontWeightLight];
    _live.numberOfLines = 3;
    _live.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_live];

    _orb = [[HKOrbView alloc] initWithFrame:CGRectZero];
    [_orb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(orbTapped)]];
    [self.view addSubview:_orb];

    _status = [UILabel new];
    _status.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    _status.font = [UIFont systemFontOfSize:14];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 2;
    [self.view addSubview:_status];

    _inputBar = [UIView new];
    _inputBar.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
    _field = [UITextField new];
    _field.textColor = [UIColor whiteColor];
    _field.keyboardAppearance = UIKeyboardAppearanceDark;
    _field.returnKeyType = UIReturnKeySend;
    _field.delegate = self;
    _field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Type a question…"
        attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.45 alpha:1]}];
    [_inputBar addSubview:_field];
    [self.view addSubview:_inputBar];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];

    [HKVoice shared].delegate = self;
    [self setState:HKStateIdle message:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [HKVoice shared].delegate = self;
    if (![HKSettings apiKey].length) {
        [self setState:HKStateIdle message:@"Add your Anthropic API key in Settings to start."];
        return;
    }
    [self ensurePermissionsThen:^{
        if (self->_pendingListen) { self->_pendingListen = NO; [self startListening]; }
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = self.topLayoutGuide.length;
    CGFloat inputH = 50;
    CGFloat bottom = b.size.height - MAX(_keyboardHeight, 0);
    _inputBar.frame = CGRectMake(0, bottom - inputH, b.size.width, inputH);
    _field.frame = CGRectMake(16, 8, b.size.width - 32, inputH - 16);

    BOOL typing = _keyboardHeight > 0;
    CGFloat orbSize = typing ? 0 : MIN(170, b.size.width * 0.45);
    CGFloat statusH = typing ? 0 : 40;
    CGFloat orbY = bottom - inputH - statusH - orbSize - 6;
    _orb.hidden = typing;
    _status.hidden = typing;
    _orb.frame = CGRectMake((b.size.width - orbSize) / 2, orbY, orbSize, orbSize);
    _status.frame = CGRectMake(20, orbY + orbSize, b.size.width - 40, statusH);

    BOOL showLive = _state == HKStateListening && _live.text.length;
    CGFloat liveH = showLive ? 80 : 0;
    _live.hidden = !showLive;
    _live.frame = CGRectMake(24, orbY - liveH, b.size.width - 48, liveH);
    _table.frame = CGRectMake(0, top, b.size.width, MAX(0, (typing ? bottom - inputH : orbY - liveH) - top));
}

#pragma mark State

- (void)setState:(HKState)state message:(NSString *)message {
    _state = state;
    _orb.mode = state;
    if (state != HKStateListening) _orb.level = 0;
    NSString *defaults[] = {@"Tap to talk", @"Listening…", @"Thinking…", @"Speaking — tap to interrupt"};
    _status.text = message ?: defaults[state];
    if (state != HKStateListening) _live.text = nil;
    [self.view setNeedsLayout];
}

- (void)ensurePermissionsThen:(void (^)(void))then {
    if (_permissionsAsked) { then(); return; }
    _permissionsAsked = YES;
    [[HKDeviceStatus shared] requestPermissions];
    [[HKVoice shared] requestPermissions:^(BOOL granted, NSString *problem) {
        if (!granted) { [self setState:HKStateIdle message:problem]; return; }
        then();
    }];
}

- (void)listenNow {
    if (!self.isViewLoaded || !self.view.window || !_permissionsAsked) { _pendingListen = YES; return; }
    if (_state == HKStateListening) return;
    [self cancelEverything];
    [self startListening];
}

- (void)startListening {
    if (![HKSettings apiKey].length) { [self openSettings]; return; }
    [_field resignFirstResponder];
    _live.text = nil;
    [self setState:HKStateListening message:nil];
    [[HKVoice shared] startListening];
}

- (void)cancelEverything {
    _autoListenAfterSpeech = NO;
    _followUp = NO;
    [[HKClaude shared] cancel];
    if ([HKVoice shared].listening) { [HKVoice shared].delegate = nil; [[HKVoice shared] stopListening]; [HKVoice shared].delegate = self; }
    if ([HKVoice shared].speaking) [[HKVoice shared] stopSpeaking];
}

- (void)orbTapped {
    switch (_state) {
        case HKStateIdle: {
            [self ensurePermissionsThen:^{ [self startListening]; }];
            break;
        }
        case HKStateListening: {
            _followUp = NO;
            [[HKVoice shared] stopListening];
            break;
        }
        case HKStateThinking: {
            [[HKClaude shared] cancel];
            [self setState:HKStateIdle message:@"Cancelled"];
            break;
        }
        case HKStateSpeaking: {
            _autoListenAfterSpeech = NO;
            [[HKVoice shared] stopSpeaking];
            [self startListening];
            break;
        }
    }
}

- (void)newChat {
    [self cancelEverything];
    [[HKClaude shared] reset];
    [_items removeAllObjects];
    [_table reloadData];
    [self setState:HKStateIdle message:@"New conversation"];
}

- (void)openSettings {
    [self cancelEverything];
    [self setState:HKStateIdle message:nil];
    HKSettingsViewController *vc = [[HKSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)appWillResignActive {
    [self cancelEverything];
    [self setState:HKStateIdle message:nil];
}

#pragma mark Asking

- (void)addItem:(NSString *)text user:(BOOL)user {
    [_items addObject:@{@"user": @(user), @"text": text}];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:_items.count - 1 inSection:0];
    [_table reloadData];
    [_table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}

- (void)ask:(NSString *)question {
    [self addItem:question user:YES];
    [self setState:HKStateThinking message:nil];
    [[HKClaude shared] ask:question completion:^(NSString *reply, NSError *error) {
        if (error) {
            [self setState:HKStateIdle message:error.localizedDescription];
            return;
        }
        [self addItem:reply user:NO];
        if ([HKSettings speakReplies]) {
            self->_autoListenAfterSpeech = [HKSettings conversationMode];
            [self setState:HKStateSpeaking message:nil];
            [[HKVoice shared] speak:reply];
        } else {
            [self setState:HKStateIdle message:nil];
        }
    }];
}

#pragma mark HKVoiceDelegate

- (void)voiceDidHearPartial:(NSString *)text {
    _live.text = text;
    [self.view setNeedsLayout];
}

- (void)voiceLevel:(float)level { _orb.level = level; }

- (void)voiceDidFinishListening:(NSString *)text error:(NSError *)error {
    BOOL wasFollowUp = _followUp;
    _followUp = NO;
    if (text.length) { [self ask:text]; return; }
    if (error) [self setState:HKStateIdle message:error.localizedDescription];
    else [self setState:HKStateIdle message:wasFollowUp ? nil : @"I didn't catch that. Tap to try again."];
}

- (void)voiceDidFinishSpeaking {
    if (_state != HKStateSpeaking) return;
    if (_autoListenAfterSpeech && [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        _autoListenAfterSpeech = NO;
        _followUp = YES;
        [self startListening];
    } else {
        [self setState:HKStateIdle message:nil];
    }
}

#pragma mark Typing

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *q = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return NO;
    textField.text = @"";
    [textField resignFirstResponder];
    [self cancelEverything];
    [self ask:q];
    return NO;
}

- (void)keyboardChanged:(NSNotification *)n {
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inView = [self.view convertRect:end fromView:nil];
    _keyboardHeight = MAX(0, self.view.bounds.size.height - inView.origin.y);
    double duration = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _items.count; }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [HKBubbleCell heightForText:_items[indexPath.row][@"text"] width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    HKBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"b" forIndexPath:indexPath];
    NSDictionary *item = _items[indexPath.row];
    [cell setText:item[@"text"] fromUser:[item[@"user"] boolValue]];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return action == @selector(copy:);
}
- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) [UIPasteboard generalPasteboard].string = _items[indexPath.row][@"text"];
}

@end
