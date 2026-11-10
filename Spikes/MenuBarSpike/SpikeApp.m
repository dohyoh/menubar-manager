// M0 기술 검증용 일회성 앱. 제품 코드가 아닙니다.
// 답하려는 질문: docs/plan/roadmap.md 의 S1~S8, docs/architecture/platform-notes.md
//
// 동작
//  - 메뉴바 아이콘 좌클릭: 숨김 적용/해제 토글 (펼치기/숨기기)
//  - 메뉴바 아이콘 우클릭: "숨기기" 스위치 + 설정 + 정보 + 종료
//  - 메뉴 > 정보: 주요 기능 설명 창 (InfoWindow.m)
//  - 메뉴 > 설정…: "메뉴바 관리" 창 (SettingsWindow.m) — 앱 검색·필터·표시 스위치
//  - <dir>/cmd 파일에 명령을 쓰면 실행하고 <dir>/app.log 에 결과를 남김 (자동 검증용)

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "SettingsWindow.h"
#import "InfoWindow.h"

static NSString *gDir;

static void Log(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [f stringFromDate:NSDate.date], s];
    NSString *path = [gDir stringByAppendingPathComponent:@"app.log"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) { [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil]; h = [NSFileHandle fileHandleForWritingAtPath:path]; }
    [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, SpikeSettingsHost>
@property NSStatusItem *item;
@property NSMenu *menu;
@property NSSwitch *hideSwitch;        // 우클릭 메뉴의 "숨기기" 스위치
@property id assertion;            // MBAssessmentModeAssertion
@property (nonatomic) BOOL restricted;
@property (nonatomic) BOOL autoRehide;
@property (nonatomic, copy) NSSet<NSString *> *hiddenIDs;   // 숨길 번들 ID
@property BOOL includeSelf;
@property SettingsController *settings;
@property InfoController *info;
@property NSTimer *rehideTimer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY);
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud registerDefaults:@{@"hiddenIDs": @[@"com.crowdcafe.windowmagnet"], @"autoRehide": @YES}];
    self.hiddenIDs = [NSSet setWithArray:[ud arrayForKey:@"hiddenIDs"] ?: @[]];
    _autoRehide = [ud boolForKey:@"autoRehide"];
    self.includeSelf = YES;
    self.settings = [[SettingsController alloc] initWithHost:self];
    // 새 앱이 실행되면 허용 목록을 다시 적용한다 (허용 목록은 기본이 "차단")
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(appsChanged:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(appsChanged:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];

    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.item.autosaveName = @"MenuBarSpikeMain";
    self.item.button.image = [NSImage imageWithSystemSymbolName:@"square.lefthalf.filled" accessibilityDescription:@"MenuBarSpike"];
    self.item.button.target = self;
    self.item.button.action = @selector(clicked:);
    [self.item.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];

    self.menu = [NSMenu new]; self.menu.delegate = self;
    [self.menu addItem:[self makeHideSwitchItem]];
    [self.menu addItem:NSMenuItem.separatorItem];
    [self.menu addItemWithTitle:@"설정…" action:@selector(openSettings) keyEquivalent:@","].target = self;
    [self.menu addItemWithTitle:@"정보" action:@selector(openInfo) keyEquivalent:@""].target = self;
    [self.menu addItem:NSMenuItem.separatorItem];
    [self.menu addItemWithTitle:@"종료" action:@selector(quit) keyEquivalent:@"q"].target = self;

    [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(poll) userInfo:nil repeats:YES];
    Log(@"launched bundleID=%@ pid=%d ax=%d postEvent=%d", NSBundle.mainBundle.bundleIdentifier, getpid(), AXIsProcessTrusted(), CGPreflightPostEventAccess());
}

- (void)applicationWillTerminate:(NSNotification *)n { [self unrestrict]; Log(@"terminate"); }

// ── 클릭 처리 ──
- (void)clicked:(id)sender {
    NSEvent *e = NSApp.currentEvent;
    BOOL right = e.type == NSEventTypeRightMouseUp || (e.modifierFlags & NSEventModifierFlagControl);
    Log(@"CLICK type=%lu right=%d", (unsigned long)e.type, right);
    if (right) { self.item.menu = self.menu; [self.item.button performClick:nil]; self.item.menu = nil; }
    else [self toggle];
}
- (void)menuWillOpen:(NSMenu *)m {
    self.hideSwitch.state = self.restricted ? NSControlStateValueOn : NSControlStateValueOff;
    Log(@"MENU willOpen");
}
- (void)menuDidClose:(NSMenu *)m { Log(@"MENU didClose"); }
// 우클릭 메뉴의 "숨기기" 항목: 글자 + 스위치. 켜면 숨김 적용, 끄면 전부 표시를 유지한다.
- (NSMenuItem *)makeHideSwitchItem {
    NSTextField *label = [NSTextField labelWithString:@"숨기기"];
    label.font = [NSFont menuFontOfSize:0];
    self.hideSwitch = [NSSwitch new];
    self.hideSwitch.controlSize = NSControlSizeSmall;
    self.hideSwitch.target = self; self.hideSwitch.action = @selector(hideSwitchChanged:);
    self.hideSwitch.accessibilityLabel = @"숨기기";
    NSView *spacer = [NSView new];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, spacer, self.hideSwitch]];
    row.distribution = NSStackViewDistributionFill;
    row.edgeInsets = NSEdgeInsetsMake(4, 14, 4, 12);
    row.frame = NSMakeRect(0, 0, 220, 30);
    row.autoresizingMask = NSViewWidthSizable;
    NSMenuItem *item = [NSMenuItem new];
    item.view = row;
    return item;
}
// 스위치로 끈 경우는 사용자가 "숨기지 말라"고 한 것이므로 자동으로 다시 숨기지 않는다 (좌클릭 펼치기와 다름).
- (void)hideSwitchChanged:(NSSwitch *)sw {
    BOOL on = sw.state == NSControlStateValueOn;
    Log(@"MENU switch -> %d", on);
    if (on) [self restrict]; else [self unrestrict];
}
// 자동 검증용: 메뉴를 열고 (clickSwitch 면 2초 뒤 스위치를 누르고) 잠시 뒤 닫는다. (메뉴가 열려 있는 동안에도 돌도록 common mode 타이머 사용)
- (void)menuTest:(BOOL)clickSwitch {
    if (clickSwitch) {
        NSTimer *click = [NSTimer timerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *t) { [self.hideSwitch performClick:nil]; }];
        [NSRunLoop.currentRunLoop addTimer:click forMode:NSRunLoopCommonModes];
    }
    NSTimer *close = [NSTimer timerWithTimeInterval:clickSwitch ? 4.5 : 2.5 repeats:NO block:^(NSTimer *t) { [self.menu cancelTracking]; }];
    [NSRunLoop.currentRunLoop addTimer:close forMode:NSRunLoopCommonModes];
    self.item.menu = self.menu; [self.item.button performClick:nil]; self.item.menu = nil;
}
- (void)setAutoRehide:(BOOL)v {
    _autoRehide = v;
    [NSUserDefaults.standardUserDefaults setBool:v forKey:@"autoRehide"];
    if (!v) { [self.rehideTimer invalidate]; self.rehideTimer = nil; }
    [self.settings refreshStatus];
    Log(@"autoRehide=%d", v);
}
- (void)openSettings { Log(@"openSettings"); [self.settings show]; Log(@"settings window visible=%d", self.settings.isVisible); }
- (void)openInfo { if (!self.info) self.info = [InfoController new]; [self.info show]; Log(@"openInfo visible=%d", self.info.isVisible); }
- (void)quit { [NSApp terminate:nil]; }

// 좌클릭: 펼치기 ↔ 숨기기. 펼친 뒤에는 (옵션이 켜져 있으면) 10초 후 자동으로 다시 숨긴다.
- (void)toggle {
    if (self.restricted) {
        [self unrestrict];
        if (self.autoRehide) self.rehideTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(rehideFired) userInfo:nil repeats:NO];
    } else [self restrict];
}
- (void)rehideFired { Log(@"auto rehide"); self.rehideTimer = nil; if (!self.restricted) [self restrict]; }

// 설정 창에서 숨길 앱이 바뀜 → 저장, 숨김 적용 중이면 즉시 교체
- (void)hiddenIDsDidChange {
    [NSUserDefaults.standardUserDefaults setObject:self.hiddenIDs.allObjects forKey:@"hiddenIDs"];
    Log(@"hiddenIDs changed -> [%@]", [self.hiddenIDs.allObjects componentsJoinedByString:@","]);
    if (self.restricted) [self restrict];
}
- (void)appsChanged:(NSNotification *)n {
    if (self.restricted) [self restrict];
    if (self.settings.isVisible) [self.settings reloadApps];
}

// ── 숨김 (허용 목록) ──
- (void)restrict {
    Class Cfg = NSClassFromString(@"MBAssessmentModeConfiguration"), Asr = NSClassFromString(@"MBAssessmentModeAssertion");
    if (!Cfg || !Asr) { Log(@"UNSUPPORTED: private classes missing"); return; }
    [self.rehideTimer invalidate]; self.rehideTimer = nil;
    // /Applications 밖에서 실행하면 숨김 중 자기 아이콘도 사라진다 → 숨김을 켜지 않는다 (ADR-0010)
    if (self.includeSelf && ![NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"]) {
        Log(@"REFUSED: not installed in /Applications (%@)", NSBundle.mainBundle.bundlePath);
        NSAlert *al = [NSAlert new]; al.messageText = @"응용 프로그램 폴더에서 실행해 주세요";
        al.informativeText = @"다른 위치에서 실행하면 숨김을 켰을 때 이 앱의 아이콘도 함께 사라집니다. ./build.sh install 로 설치한 뒤 실행하세요.";
        [NSApp activateIgnoringOtherApps:YES]; [al runModal];
        return;
    }
    NSMutableArray *sys = [NSMutableArray array]; for (int i = 0; i < 256; i++) [sys addObject:@(i)];
    NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSet];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
        if (app.bundleIdentifier && ![self.hiddenIDs containsObject:app.bundleIdentifier]) [ids addObject:app.bundleIdentifier];
    NSString *me = NSBundle.mainBundle.bundleIdentifier;
    if (self.includeSelf) [ids addObject:me]; else [ids removeObject:me];
    id cfg = ((id (*)(id, SEL, id, id))objc_msgSend)([Cfg alloc], NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"), sys, ids.array);
    // 같은 객체로 다시 activate 하면 이전 제한이 해제되지 않고 누적된다(검증됨).
    // → 새 assertion 을 먼저 켜고, 완료되면 이전 것을 해제한다 (끊김 없이 교체).
    id previous = self.assertion;
    id next = [[Asr alloc] init];
    self.assertion = next;
    void (^done)(void *) = ^(void *err) {
        Log(@"restrict completion err=%p", err);
        if (previous) ((void (*)(id, SEL))objc_msgSend)(previous, NSSelectorFromString(@"invalidate"));
    };
    ((void (*)(id, SEL, id, id))objc_msgSend)(next, NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), cfg, (id)done);
    self.restricted = YES; self.item.button.image = [NSImage imageWithSystemSymbolName:@"square.righthalf.filled" accessibilityDescription:@"MenuBarSpike"];
    Log(@"restrict hidden=[%@] includeSelf=%d allowed=%lu replacing=%d", [self.hiddenIDs.allObjects componentsJoinedByString:@","], self.includeSelf, (unsigned long)ids.count, previous != nil);
    [self.settings refreshStatus];
}
- (void)unrestrict {
    if (self.assertion) { ((void (*)(id, SEL))objc_msgSend)(self.assertion, NSSelectorFromString(@"invalidate")); self.assertion = nil; }
    self.restricted = NO; self.item.button.image = [NSImage imageWithSystemSymbolName:@"square.lefthalf.filled" accessibilityDescription:@"MenuBarSpike"];
    [self.rehideTimer invalidate]; self.rehideTimer = nil;
    Log(@"unrestrict");
    [self.settings refreshStatus];
}

// ── 접근성: 아이템 열거 ──
static id AXAttr(AXUIElementRef e, NSString *name) { CFTypeRef v = NULL; return AXUIElementCopyAttributeValue(e, (__bridge CFStringRef)name, &v) == kAXErrorSuccess ? CFBridgingRelease(v) : nil; }
- (void)axlist {
    Log(@"AXLIST trusted=%d", AXIsProcessTrusted());
    if (!AXIsProcessTrusted()) return;
    int total = 0;
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        AXUIElementRef e = AXUIElementCreateApplication(app.processIdentifier);
        AXUIElementSetMessagingTimeout(e, 0.3);
        id bar = AXAttr(e, @"AXExtrasMenuBar");
        if (bar) {
            NSArray *kids = AXAttr((__bridge AXUIElementRef)bar, @"AXChildren");
            for (id k in kids) {
                AXUIElementRef ke = (__bridge AXUIElementRef)k;
                CGPoint p = CGPointZero; CGSize s = CGSizeZero;
                id pv = AXAttr(ke, @"AXPosition"), sv = AXAttr(ke, @"AXSize");
                if (pv) AXValueGetValue((__bridge AXValueRef)pv, kAXValueTypeCGPoint, &p);
                if (sv) AXValueGetValue((__bridge AXValueRef)sv, kAXValueTypeCGSize, &s);
                Log(@"AXITEM app=%@ pid=%d x=%.0f y=%.0f w=%.0f h=%.0f title=%@ desc=%@ id=%@", app.bundleIdentifier ?: app.localizedName, app.processIdentifier, p.x, p.y, s.width, s.height,
                    AXAttr(ke, @"AXTitle") ?: @"-", AXAttr(ke, @"AXDescription") ?: @"-", AXAttr(ke, @"AXIdentifier") ?: @"-");
                total++;
            }
        }
        CFRelease(e);
    }
    Log(@"AXLIST done total=%d", total);
}

// ── 이벤트 합성 ──
- (void)post:(CGEventType)t at:(CGPoint)p button:(CGMouseButton)b flags:(CGEventFlags)f {
    CGEventRef ev = CGEventCreateMouseEvent(NULL, t, p, b); CGEventSetFlags(ev, f); CGEventPost(kCGHIDEventTap, ev); CFRelease(ev);
}
- (void)clickAt:(CGPoint)p right:(BOOL)right {
    CGEventRef cur = CGEventCreate(NULL); CGPoint saved = CGEventGetLocation(cur); CFRelease(cur);
    [self post:kCGEventMouseMoved at:p button:kCGMouseButtonLeft flags:0]; usleep(60000);
    [self post:right ? kCGEventRightMouseDown : kCGEventLeftMouseDown at:p button:right ? kCGMouseButtonRight : kCGMouseButtonLeft flags:0]; usleep(60000);
    [self post:right ? kCGEventRightMouseUp : kCGEventLeftMouseUp at:p button:right ? kCGMouseButtonRight : kCGMouseButtonLeft flags:0]; usleep(60000);
    CGWarpMouseCursorPosition(saved);
    Log(@"posted %@ click at %.0f,%.0f", right ? @"right" : @"left", p.x, p.y);
}
- (void)cmdDragFrom:(CGPoint)a to:(CGPoint)b {
    CGEventRef cur = CGEventCreate(NULL); CGPoint saved = CGEventGetLocation(cur); CFRelease(cur);
    CGEventFlags f = kCGEventFlagMaskCommand;
    [self post:kCGEventMouseMoved at:a button:kCGMouseButtonLeft flags:f]; usleep(80000);
    [self post:kCGEventLeftMouseDown at:a button:kCGMouseButtonLeft flags:f]; usleep(120000);
    int steps = 12;
    for (int i = 1; i <= steps; i++) {
        CGPoint p = CGPointMake(a.x + (b.x - a.x) * i / steps, a.y + (b.y - a.y) * i / steps);
        [self post:kCGEventLeftMouseDragged at:p button:kCGMouseButtonLeft flags:f]; usleep(30000);
    }
    usleep(150000);
    [self post:kCGEventLeftMouseUp at:b button:kCGMouseButtonLeft flags:f]; usleep(80000);
    CGWarpMouseCursorPosition(saved);
    Log(@"posted cmd-drag %.0f,%.0f -> %.0f,%.0f", a.x, a.y, b.x, b.y);
}

// ── 명령 처리 ──
- (void)poll {
    NSString *path = [gDir stringByAppendingPathComponent:@"cmd"];
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!raw) return;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *p = [[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] componentsSeparatedByString:@" "];
        NSString *c = p[0]; if (!c.length) continue;
        Log(@"CMD %@", line);
        if ([c isEqual:@"restrict"]) { if (p.count > 1) self.hiddenIDs = [NSSet setWithArray:[p[1] componentsSeparatedByString:@","]]; [self restrict]; }
        else if ([c isEqual:@"settings"]) [self openSettings];
        else if ([c isEqual:@"menutest"]) [self menuTest:YES];
        else if ([c isEqual:@"menushot"]) [self menuTest:NO];
        else if ([c isEqual:@"info"]) [self openInfo];
        else if ([c isEqual:@"switch"]) Log(@"switch %@ clicked=%d", p[1], [self.settings debugClickSwitchForBundleID:p[1]]);
        else if ([c isEqual:@"unrestrict"]) [self unrestrict];
        else if ([c isEqual:@"self"]) self.includeSelf = [p[1] boolValue];
        else if ([c isEqual:@"toggle"]) [self toggle];
        else if ([c isEqual:@"axlist"]) [self axlist];
        else if ([c isEqual:@"axprompt"]) Log(@"axprompt trusted=%d", AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @YES}));
        else if ([c isEqual:@"click"]) [self clickAt:CGPointMake(p[1].doubleValue, p[2].doubleValue) right:[p[3] isEqual:@"right"]];
        else if ([c isEqual:@"drag"]) [self cmdDragFrom:CGPointMake(p[1].doubleValue, p[3].doubleValue) to:CGPointMake(p[2].doubleValue, p[3].doubleValue)];
        else if ([c isEqual:@"selfinfo"]) {
            NSWindow *w = self.item.button.window;
            Log(@"SELF buttonWindow=%@ screen=%@ visible=%d occlusionVisible=%d itemVisible=%d", NSStringFromRect(w.frame), w.screen.localizedName, w.isVisible, (w.occlusionState & NSWindowOcclusionStateVisible) != 0, self.item.isVisible);
        }
        else if ([c isEqual:@"quit"]) [self quit];
        else Log(@"unknown command");
    }
}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        gDir = [NSUserDefaults.standardUserDefaults stringForKey:@"dir"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MenuBarSpike"];
        [NSFileManager.defaultManager createDirectoryAtPath:gDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *d = [AppDelegate new]; app.delegate = d;
        [app run];
    }
    return 0;
}
