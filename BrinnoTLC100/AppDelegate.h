//
//  AppDelegate.h
//  BrinnoTLC100
//
//  Created by Samuel Stauffer on 4/29/13.
//  Copyright (c) 2013 Samuel Stauffer. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSPopUpButtonCell *volumeSelector;
@property (weak) IBOutlet NSDatePicker *datePicker;
@property (weak) IBOutlet NSTextField *intervalLabel;
@property (weak) IBOutlet NSSlider *intervalSlider;
@property (weak) IBOutlet NSButton *lowLightToggle;
@property (weak) IBOutlet NSPopUpButton *powerFrequencyPicker;

@end
