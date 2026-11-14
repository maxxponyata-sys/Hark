#import "HKCore.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <EventKit/EventKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#include <sys/sysctl.h>
#include <netinet/in.h>

static NSString *HKMachine(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *buf = malloc(size + 1);
    sysctlbyname("hw.machine", buf, &size, NULL, 0);
    buf[size] = 0;
    NSString *s = [NSString stringWithUTF8String:buf];
    free(buf);
    return s ?: @"unknown";
}

static NSString *HKModelName(NSString *m) {
    NSDictionary *names = @{
        @"iPhone5,1": @"iPhone 5", @"iPhone5,2": @"iPhone 5", @"iPhone5,3": @"iPhone 5c", @"iPhone5,4": @"iPhone 5c",
        @"iPhone6,1": @"iPhone 5s", @"iPhone6,2": @"iPhone 5s", @"iPhone7,2": @"iPhone 6", @"iPhone7,1": @"iPhone 6 Plus",
        @"iPhone8,1": @"iPhone 6s", @"iPhone8,2": @"iPhone 6s Plus", @"iPhone8,4": @"iPhone SE",
        @"iPhone9,1": @"iPhone 7", @"iPhone9,3": @"iPhone 7", @"iPhone9,2": @"iPhone 7 Plus", @"iPhone9,4": @"iPhone 7 Plus",
        @"iPod7,1": @"iPod touch (6th generation)",
        @"iPad3,4": @"iPad (4th generation)", @"iPad3,5": @"iPad (4th generation)", @"iPad3,6": @"iPad (4th generation)",
        @"iPad4,1": @"iPad Air", @"iPad4,2": @"iPad Air", @"iPad4,3": @"iPad Air",
        @"iPad4,4": @"iPad mini 2", @"iPad4,5": @"iPad mini 2", @"iPad4,6": @"iPad mini 2",
        @"iPad4,7": @"iPad mini 3", @"iPad4,8": @"iPad mini 3", @"iPad4,9": @"iPad mini 3",
        @"iPad5,1": @"iPad mini 4", @"iPad5,2": @"iPad mini 4", @"iPad5,3": @"iPad Air 2", @"iPad5,4": @"iPad Air 2",
        @"iPad6,3": @"iPad Pro (9.7-inch)", @"iPad6,4": @"iPad Pro (9.7-inch)", @"iPad6,7": @"iPad Pro (12.9-inch)",
        @"iPad6,8": @"iPad Pro (12.9-inch)", @"iPad6,11": @"iPad (5th generation)", @"iPad6,12": @"iPad (5th generation)",
        @"iPad7,1": @"iPad Pro (12.9-inch, 2nd gen)", @"iPad7,2": @"iPad Pro (12.9-inch, 2nd gen)",
        @"iPad7,3": @"iPad Pro (10.5-inch)", @"iPad7,4": @"iPad Pro (10.5-inch)",
    };
    return names[m] ?: m;
}

static NSString *HKBytes(long long b) {
    return [NSByteCountFormatter stringFromByteCount:b countStyle:NSByteCountFormatterCountStyleFile];
}

@interface HKDeviceStatus () <CLLocationManagerDelegate>
@end

@implementation HKDeviceStatus {
    CLLocationManager *_location;
    CLLocation *_lastLocation;
    CLPlacemark *_placemark;
    CLGeocoder *_geocoder;
    EKEventStore *_events;
}

+ (instancetype)shared {
    static HKDeviceStatus *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        _geocoder = [CLGeocoder new];
        _events = [EKEventStore new];
    }
    return self;
}

- (void)requestPermissions {
    if ([HKSettings shareLocation]) {
        if (!_location) {
            _location = [CLLocationManager new];
            _location.delegate = self;
            _location.desiredAccuracy = kCLLocationAccuracyKilometer;
            _location.distanceFilter = 500;
        }
        CLAuthorizationStatus st = [CLLocationManager authorizationStatus];
        if (st == kCLAuthorizationStatusNotDetermined) [_location requestWhenInUseAuthorization];
        else if (st == kCLAuthorizationStatusAuthorizedWhenInUse || st == kCLAuthorizationStatusAuthorizedAlways) [_location requestLocation];
    }
    if ([HKSettings shareCalendar] && [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] == EKAuthorizationStatusNotDetermined) {
        [_events requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {}];
    }
    if ([MPMediaLibrary authorizationStatus] == MPMediaLibraryAuthorizationStatusNotDetermined) {
        [MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus status) {}];
    }
}

#pragma mark Location

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) [manager requestLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    BOOL moved = !_lastLocation || [loc distanceFromLocation:_lastLocation] > 1000;
    _lastLocation = loc;
    if (moved || !_placemark) {
        __weak HKDeviceStatus *weakSelf = self;
        [_geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            HKDeviceStatus *s = weakSelf;
            if (s && placemarks.firstObject) s->_placemark = placemarks.firstObject;
        }];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {}

- (NSDictionary *)approximateLocation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"timezone"] = [NSTimeZone localTimeZone].name;
    if ([HKSettings shareLocation] && _placemark) {
        if (_placemark.locality) d[@"city"] = _placemark.locality;
        if (_placemark.administrativeArea) d[@"region"] = _placemark.administrativeArea;
        if (_placemark.ISOcountryCode) d[@"country"] = _placemark.ISOcountryCode;
    } else {
        NSString *cc = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
        if (cc.length == 2) d[@"country"] = cc;
    }
    return d;
}

#pragma mark Network

- (NSString *)networkDescription {
    struct sockaddr_in zero;
    memset(&zero, 0, sizeof(zero));
    zero.sin_len = sizeof(zero);
    zero.sin_family = AF_INET;
    SCNetworkReachabilityRef r = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zero);
    SCNetworkReachabilityFlags flags = 0;
    BOOL ok = r && SCNetworkReachabilityGetFlags(r, &flags);
    if (r) CFRelease(r);
    if (!ok || !(flags & kSCNetworkReachabilityFlagsReachable)) return @"offline";
    if (flags & kSCNetworkReachabilityFlagsIsWWAN) {
        NSString *tech = [CTTelephonyNetworkInfo new].currentRadioAccessTechnology ?: @"";
        tech = [tech stringByReplacingOccurrencesOfString:@"CTRadioAccessTechnology" withString:@""];
        return tech.length ? [NSString stringWithFormat:@"cellular (%@)", tech] : @"cellular";
    }
    NSString *ssid = nil;
    NSArray *ifs = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
    for (NSString *name in ifs) {
        NSDictionary *info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)name);
        if (info[@"SSID"]) { ssid = info[@"SSID"]; break; }
    }
    return ssid ? [NSString stringWithFormat:@"Wi-Fi \"%@\"", ssid] : @"Wi-Fi";
}

#pragma mark Snapshot

- (NSString *)snapshot {
    NSMutableArray *lines = [NSMutableArray array];
    void (^add)(NSString *, NSString *) = ^(NSString *k, NSString *v) { if (v.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", k, v]]; };

    NSDate *now = [NSDate date];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"EEEE, d MMMM yyyy, HH:mm";
    add(@"Local time", [NSString stringWithFormat:@"%@ (%@)", [df stringFromDate:now], [NSTimeZone localTimeZone].name]);

    UIDevice *dev = [UIDevice currentDevice];
    NSString *machine = HKMachine();
    add(@"Device", [NSString stringWithFormat:@"%@ (%@), %@ %@, named \"%@\"", HKModelName(machine), machine, dev.systemName, dev.systemVersion, dev.name]);

    float level = dev.batteryLevel;
    NSString *state = @[@"unknown", @"on battery", @"charging", @"fully charged"][MIN((NSUInteger)dev.batteryState, 3u)];
    NSString *battery = level >= 0 ? [NSString stringWithFormat:@"%d%%, %@", (int)lroundf(level * 100), state] : state;
    if ([NSProcessInfo processInfo].lowPowerModeEnabled) battery = [battery stringByAppendingString:@", Low Power Mode on"];
    add(@"Battery", battery);

    NSString *network = [self networkDescription];
    NSString *carrier = [CTTelephonyNetworkInfo new].subscriberCellularProvider.carrierName;
    if (carrier.length) network = [network stringByAppendingFormat:@"; carrier %@", carrier];
    add(@"Network", network);

    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    if (fs) add(@"Storage", [NSString stringWithFormat:@"%@ free of %@", HKBytes([fs[NSFileSystemFreeSize] longLongValue]), HKBytes([fs[NSFileSystemSize] longLongValue])]);
    add(@"RAM", HKBytes((long long)[NSProcessInfo processInfo].physicalMemory));
    NSTimeInterval up = [NSProcessInfo processInfo].systemUptime;
    add(@"Uptime", [NSString stringWithFormat:@"%dd %dh %dm", (int)(up / 86400), (int)fmod(up / 3600, 24), (int)fmod(up / 60, 60)]);

    add(@"Screen brightness", [NSString stringWithFormat:@"%d%%", (int)lroundf([UIScreen mainScreen].brightness * 100)]);
    AVAudioSession *audio = [AVAudioSession sharedInstance];
    NSMutableArray *outputs = [NSMutableArray array];
    for (AVAudioSessionPortDescription *p in audio.currentRoute.outputs) [outputs addObject:p.portName ?: p.portType];
    add(@"Volume", [NSString stringWithFormat:@"%d%%, output: %@", (int)lroundf(audio.outputVolume * 100), [outputs componentsJoinedByString:@", "] ?: @"speaker"]);

    add(@"Language", [NSString stringWithFormat:@"%@ (region %@)", [NSLocale preferredLanguages].firstObject ?: @"?", [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: @"?"]);

    if ([HKSettings shareLocation] && _lastLocation) {
        NSMutableArray *place = [NSMutableArray array];
        if (_placemark.thoroughfare) [place addObject:_placemark.thoroughfare];
        if (_placemark.locality) [place addObject:_placemark.locality];
        if (_placemark.administrativeArea) [place addObject:_placemark.administrativeArea];
        if (_placemark.country) [place addObject:_placemark.country];
        add(@"Location", [NSString stringWithFormat:@"%@ (%.4f, %.4f, ±%dm)", [place componentsJoinedByString:@", "] ?: @"",
                          _lastLocation.coordinate.latitude, _lastLocation.coordinate.longitude, (int)_lastLocation.horizontalAccuracy]);
    }

    if ([MPMediaLibrary authorizationStatus] == MPMediaLibraryAuthorizationStatusAuthorized) {
        MPMediaItem *item = [MPMusicPlayerController systemMusicPlayer].nowPlayingItem;
        if (item.title) add(@"Music app", [NSString stringWithFormat:@"%@ — %@ (%@)", item.artist ?: @"?", item.title,
                                           [MPMusicPlayerController systemMusicPlayer].playbackState == MPMusicPlaybackStatePlaying ? @"playing" : @"paused"]);
    }

    if ([HKSettings shareCalendar] && [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] == EKAuthorizationStatusAuthorized) {
        NSDate *end = [now dateByAddingTimeInterval:36 * 3600];
        NSPredicate *pred = [_events predicateForEventsWithStartDate:now endDate:end calendars:nil];
        NSArray *events = [[_events eventsMatchingPredicate:pred] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
        NSDateFormatter *tf = [NSDateFormatter new];
        tf.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        tf.dateFormat = @"EEE HH:mm";
        NSMutableArray *list = [NSMutableArray array];
        for (EKEvent *e in events) {
            if (list.count >= 5) break;
            [list addObject:[NSString stringWithFormat:@"%@ %@%@", e.allDay ? @"all day" : [tf stringFromDate:e.startDate], e.title ?: @"(untitled)",
                             e.location.length ? [NSString stringWithFormat:@" @ %@", e.location] : @""]];
        }
        add(@"Calendar (next 36h)", list.count ? [list componentsJoinedByString:@"; "] : @"nothing scheduled");
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end
