//
//  AppDelegate.m
//  BrinnoTLC100
//
//  Created by Samuel Stauffer on 4/29/13.
//  Copyright (c) 2013 Samuel Stauffer. All rights reserved.
//

#import "AppDelegate.h"

@interface KeyValue : NSObject
@property (copy) NSString *key;
@property (strong) id value;
@end

@implementation KeyValue
- (id)initWithKey:(NSString *)key value:(id)value
{
    self = [super init];
    if (self) {
        _key = key;
        _value = value;
    }
    return self;
}
+ (id)key:(NSString *)key value:(id)value
{
    return [[self alloc] initWithKey:key value:value];
}
@end

typedef enum _powerFrequency {
    powerFrequencyNone,
    powerFrequency50Hz,
    powerFrequency60Hz
} PowerFrequency;

static const int registryTemplateLength = 30;
static const char *registryTemplate = "\xb6\xc3\x10\x00\x28\xe1\x2b\xfe\x7f\x00\x10\xb4\x00\x00\x00\x3c\x00\x02\x00\x00\x00\xb6\xc3\x04\x00\x29\x00\x98\x8f\x42";

#define MIN_INTERVAL_SECONDS 5
#define MAX_INTERVAL_SECONDS (12*60*60)
#define REGISTRY_INTERVAL_OFFSET 0x05
#define REGISTRY_LOW_LIGHT_OFFSET 0x09
#define REGISTRY_POWER_FREQUENCY_OFFSET 0x0d
#define REGISTRY_TIME_OFFSET 0x1a
#define REGISTRY_DATE_OFFSET 0x1c

@implementation AppDelegate
{
    NSArray *_removableVolumes;
    NSInteger _interval;
}

@synthesize volumeSelector = _volumeSelector;

/*
 Little-Endian
 0000-0004 - b6 c3 10 00 28
 0005-0006 - custom time interval in seconds (min 5 seconds, max values to 12 hours, then 0xffff for max 24 hours)
 0007-0008 - fe 7f
 0009-000a - low light on=0x0000, low light off=0x1000
 000b-000c - b4 00
 000d-000e - power frequency (0x0000 = none, 0x03e8 = 50 hz, 0x0341 = 60 hz) seems to be 50000/freq
 000f-0014 - 3c 00 02 00 00 00
 0015-0019 - b6 c3 04 00 29
 001a-001b - time (bits 0-4 seconds/2, 5-10 minutes, 11-15 hours) (hours << 11 | minutes << 5 | seconds >> 1)
 001c-001d - date (bits 0-4 day, 5-8 month, 9-15 years since 1980)
*/
 - (NSData *)createRegistryWithInterval:(NSUInteger)interval lowLight:(BOOL)lowLight powerFrequency:(PowerFrequency)powerFrequency date:(NSDate *)date
{
    char *registry = (char *)malloc(registryTemplateLength);
    memmove(registry, registryTemplate, registryTemplateLength);
    if (interval > MAX_INTERVAL_SECONDS) {
        interval = 0xffff;
    }
    *(unsigned short *)(registry+REGISTRY_INTERVAL_OFFSET) = CFSwapInt16HostToLittle(interval);
    if (lowLight) {
        *(registry+REGISTRY_LOW_LIGHT_OFFSET+1) = 0x00;
    } else {
        *(registry+REGISTRY_LOW_LIGHT_OFFSET+1) = 0x10;
    }
    unsigned short pf = 0x0000;
    switch (powerFrequency) {
        default:
            // Default to None
            break;
        case powerFrequency50Hz:
            pf = 0x03e8;
            break;
        case powerFrequency60Hz:
            pf = 0x0e41;
            break;
    }
    *(unsigned short *)(registry+REGISTRY_POWER_FREQUENCY_OFFSET) = CFSwapInt16HostToLittle(pf);

    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *weekdayComponents = [gregorian components:(NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate:date];

    *(unsigned short *)(registry+REGISTRY_TIME_OFFSET) = CFSwapInt16HostToLittle((weekdayComponents.hour << 11) | (weekdayComponents.minute << 5) | (weekdayComponents.second >> 1));
    *(unsigned short *)(registry+REGISTRY_DATE_OFFSET) = CFSwapInt16HostToLittle(((weekdayComponents.year - 1980) << 9) | (weekdayComponents.month << 5) | weekdayComponents.day);
    
    return [NSData dataWithBytesNoCopy:registry length:registryTemplateLength freeWhenDone:YES];
}

- (IBAction)clickOk:(id)sender {
    KeyValue *kv = nil;
    if (_removableVolumes.count > _volumeSelector.indexOfSelectedItem) {
        kv = [_removableVolumes objectAtIndex:_volumeSelector.indexOfSelectedItem];
    }
    if (!kv) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"No volume selected" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please insert the USB memory stick from the TLC100 and select the volume."];
        [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        return;
    }

    NSError *err;
    NSURL *url = kv.value;
    url = [url URLByAppendingPathComponent:@"DCIM/100TLC"];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&err]) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        return;
    }
    url = [url URLByAppendingPathComponent:@"registry.ldr"];
    NSData *data = [self createRegistryWithInterval:_interval lowLight:_lowLightToggle.state == NSOnState powerFrequency:(PowerFrequency)_powerFrequencyPicker.indexOfSelectedItem date:_datePicker.dateValue];
    if (![data writeToURL:url options:NSDataWritingAtomic error:&err]) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        return;
    }
}

- (IBAction)intervalSlide:(NSSlider *)slider {
    NSInteger ti = slider.integerValue;
    if (ti == slider.maxValue) {
        _intervalLabel.stringValue = @"24h";
        _interval = 0xffff;
    } else if (ti >= 119) {
        NSInteger hours = ti - 118;
        _intervalLabel.stringValue = [NSString stringWithFormat:@"%ldhours", hours];
        _interval = hours * 60 * 60;
    } else if (ti >= 60) {
        NSInteger minutes = ti - 59;
        _intervalLabel.stringValue = [NSString stringWithFormat:@"%ldminutes", minutes];
        _interval = minutes * 60;
    } else {
        _interval = ti % 60;
        _intervalLabel.stringValue = [NSString stringWithFormat:@"%ldseconds", _interval];
    }
}

- (void)setInterval:(NSUInteger)interval
{
    _interval = interval;
    if (interval > MAX_INTERVAL_SECONDS) {
        interval = 0xffff;
        _intervalLabel.stringValue = @"24h";
        _intervalSlider.integerValue = _intervalSlider.maxValue;
    } else {
        if (interval < MIN_INTERVAL_SECONDS) {
            interval = MIN_INTERVAL_SECONDS;
        }
        NSUInteger hours = (int)(interval/(60*60));
        NSUInteger minutes = (int)(interval/60) % 60;
        NSUInteger seconds = interval % 60;
        NSMutableArray *parts = [NSMutableArray arrayWithCapacity:3];
        if (hours > 0) {
            _intervalSlider.integerValue = hours + 118;
            [parts addObject:[NSString stringWithFormat:@"%ldh", hours]];
        }
        if (minutes > 0) {
            if (hours == 0) {
                _intervalSlider.integerValue = minutes + 59;
            }
            [parts addObject:[NSString stringWithFormat:@"%ldm", minutes]];
        }
        if (seconds > 0) {
            if (hours == 0 && minutes == 0) {
                _intervalSlider.integerValue = seconds;
            }
            [parts addObject:[NSString stringWithFormat:@"%lds", seconds]];
        }
        _intervalLabel.stringValue = [parts componentsJoinedByString:@" "];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self _updateVolumes];
    [self _monitorVolumes];

    _datePicker.dateValue = [NSDate date];
 
    [self setInterval:5];
}

- (void)_monitorVolumes
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector: @selector(volumesChanged:) name:NSWorkspaceDidMountNotification object: nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector: @selector(volumesChanged:) name:NSWorkspaceDidUnmountNotification object:nil];
}

- (void)volumesChanged:(NSNotification *)notification
{
    [self _updateVolumes];
}

- (void)_updateVolumes
{
    NSURL *currentURL = nil;
    if (_removableVolumes.count > 0) {
        currentURL = [(KeyValue*)_removableVolumes[_volumeSelector.indexOfSelectedItem] value];
    }
    _removableVolumes = [self _getRemovableVolumes];
    [_volumeSelector removeAllItems];
    NSInteger i = 0;
    NSInteger selectedIndex = 0;
    for(KeyValue *kv in _removableVolumes) {
        [_volumeSelector addItemWithTitle:kv.key];
        NSURL *url = kv.value;
        if (currentURL && [url isEqual:currentURL]) {
            selectedIndex = i;
        }
        i++;
    }
    [_volumeSelector selectItemAtIndex:selectedIndex];
}

- (NSArray *)_getRemovableVolumes
{
    NSArray *keys = [NSArray arrayWithObjects:NSURLVolumeNameKey, NSURLVolumeIsRemovableKey, nil];
    NSArray *urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys options:0];
    NSMutableArray *removable = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *url in urls) {
        NSError *error;
        NSNumber *isRemovable;
        NSString *volumeName;
        [url getResourceValue:&isRemovable forKey:NSURLVolumeIsRemovableKey error:&error];
        if ([isRemovable boolValue]) {
            [url getResourceValue:&volumeName forKey:NSURLVolumeNameKey error:&error];
            [removable addObject:[KeyValue key:volumeName value:url]];
        }
    }
    return removable;
}
@end
