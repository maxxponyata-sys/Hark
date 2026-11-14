#import "HKUI.h"

typedef NS_ENUM(NSInteger, HKSection) { HKSecAPI, HKSecVoice, HKSecContext, HKSecPersonal, HKSecSiri, HKSecAbout, HKSecCount };

@implementation HKSettingsViewController {
    UITextField *_keyField;
    UITextField *_langField;
    UITextView *_instructions;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    _keyField = [self field:@"sk-ant-…"];
    _keyField.secureTextEntry = YES;
    _keyField.text = [HKSettings apiKey];
    _langField = [self field:[HKSettings language]];
    _langField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"language"];
    _langField.textAlignment = NSTextAlignmentRight;
    _instructions = [UITextView new];
    _instructions.font = [UIFont systemFontOfSize:15];
    _instructions.text = [HKSettings customInstructions];
    _instructions.delegate = self;
    _instructions.backgroundColor = [UIColor clearColor];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [self saveFields];
}

- (UITextField *)field:(NSString *)placeholder {
    UITextField *f = [UITextField new];
    f.placeholder = placeholder;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    return f;
}

- (void)saveFields {
    [HKSettings setAPIKey:_keyField.text];
    [HKSettings setLanguage:[_langField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    [HKSettings setCustomInstructions:_instructions.text];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)textField { [self saveFields]; }
- (void)textViewDidEndEditing:(UITextView *)textView { [self saveFields]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return HKSecCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case HKSecAPI: return 3;
        case HKSecVoice: return 3;
        case HKSecContext: return 4;
        case HKSecPersonal: return 1;
        case HKSecSiri: return 0;
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Anthropic API", @"Voice", @"What Hark knows", @"Your instructions", @"Using Hark instead of Siri", @"About"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case HKSecAPI: return @"Requests go straight from this device to api.anthropic.com and are billed to your Anthropic account. The key is kept in the iOS keychain.";
        case HKSecVoice: return @"Language for speech recognition and the voice, like ru-RU or en-US. Leave empty to follow the device language. Conversation mode listens again after each reply.";
        case HKSecContext: return @"Every question is sent with a snapshot of the device: time, battery, network, storage, brightness, volume, the Music app and, if you allow, location and upcoming events.";
        case HKSecPersonal: return @"For example: \"Call me Max. Answer in Russian. Be a bit funny.\"";
        case HKSecSiri: return @"Without jailbreak: say \"Hey Siri, open Hark\", or put Hark in the Dock.\n\nWith jailbreak: install the HarkSiri tweak and holding the Home button opens Hark instead of Siri. Keep Siri turned on in Settings → Siri so the button still works.";
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == HKSecPersonal ? 110 : 44;
}

- (void)place:(UIView *)v in:(UITableViewCell *)cell left:(CGFloat)left {
    v.frame = CGRectMake(left, 0, cell.contentView.bounds.size.width - left - 12, cell.contentView.bounds.size.height);
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:v];
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action {
    UISwitch *s = [UISwitch new];
    s.on = on;
    s.onTintColor = HKAccent();
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (NSString *)modelName {
    for (NSDictionary *m in [HKSettings availableModels]) if ([m[@"id"] isEqual:[HKSettings model]]) return m[@"name"];
    return [HKSettings model];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSInteger s = indexPath.section, r = indexPath.row;
    if (s == HKSecAPI) {
        if (r == 0) { cell.selectionStyle = UITableViewCellSelectionStyleNone; [self place:_keyField in:cell left:16]; }
        else if (r == 1) { cell.textLabel.text = @"Model"; cell.detailTextLabel.text = [self modelName]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else { cell.textLabel.text = @"Get an API key"; cell.textLabel.textColor = HKAccent(); cell.detailTextLabel.text = @"console.anthropic.com"; }
    } else if (s == HKSecVoice) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (r == 0) { cell.textLabel.text = @"Language"; [self place:_langField in:cell left:120]; }
        else if (r == 1) { cell.textLabel.text = @"Speak replies"; cell.accessoryView = [self switchOn:[HKSettings speakReplies] action:@selector(speakChanged:)]; }
        else { cell.textLabel.text = @"Conversation mode"; cell.accessoryView = [self switchOn:[HKSettings conversationMode] action:@selector(conversationChanged:)]; }
    } else if (s == HKSecContext) {
        if (r == 3) { cell.textLabel.text = @"Show what Hark sees now"; cell.textLabel.textColor = HKAccent(); return cell; }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (r == 0) { cell.textLabel.text = @"Web search"; cell.accessoryView = [self switchOn:[HKSettings webSearch] action:@selector(webChanged:)]; }
        else if (r == 1) { cell.textLabel.text = @"Share location"; cell.accessoryView = [self switchOn:[HKSettings shareLocation] action:@selector(locationChanged:)]; }
        else { cell.textLabel.text = @"Share calendar"; cell.accessoryView = [self switchOn:[HKSettings shareCalendar] action:@selector(calendarChanged:)]; }
    } else if (s == HKSecPersonal) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [self place:_instructions in:cell left:10];
    } else {
        if (r == 0) { cell.textLabel.text = @"Version"; cell.detailTextLabel.text = HK_VERSION; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
        else { cell.textLabel.text = @"Source code"; cell.detailTextLabel.text = @"GitHub"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    }
    return cell;
}

- (void)speakChanged:(UISwitch *)s { [HKSettings setSpeakReplies:s.on]; }
- (void)conversationChanged:(UISwitch *)s { [HKSettings setConversationMode:s.on]; }
- (void)webChanged:(UISwitch *)s { [HKSettings setWebSearch:s.on]; }
- (void)locationChanged:(UISwitch *)s { [HKSettings setShareLocation:s.on]; if (s.on) [[HKDeviceStatus shared] requestPermissions]; }
- (void)calendarChanged:(UISwitch *)s { [HKSettings setShareCalendar:s.on]; if (s.on) [[HKDeviceStatus shared] requestPermissions]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.view endEditing:YES];
    NSInteger s = indexPath.section, r = indexPath.row;
    UIView *source = [tableView cellForRowAtIndexPath:indexPath];
    if (s == HKSecAPI && r == 1) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Model" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *m in [HKSettings availableModels]) {
            NSString *title = [NSString stringWithFormat:@"%@ — %@%@", m[@"name"], m[@"note"], [m[@"id"] isEqual:[HKSettings model]] ? @"  ✓" : @""];
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [HKSettings setModel:m[@"id"]];
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = source;
        sheet.popoverPresentationController.sourceRect = source.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
    } else if (s == HKSecAPI && r == 2) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://console.anthropic.com/settings/keys"] options:@{} completionHandler:nil];
    } else if (s == HKSecContext && r == 3) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sent with each question" message:[[HKDeviceStatus shared] snapshot] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (s == HKSecAbout && r == 1) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:HK_SOURCE_URL] options:@{} completionHandler:nil];
    }
}

@end
