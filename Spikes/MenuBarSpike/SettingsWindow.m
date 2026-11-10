// 검증용 설정 창 — "메뉴바 관리" (FR-17 의 최소 구현). 제품 코드가 아닙니다.
//  - 앱 목록: 실행 중인 앱 + /Applications 에 설치된 앱
//  - 검색, 필터(실행 중 / 숨긴 앱 / 전체), 앱별 표시 스위치
//  - 스위치를 바꾸면 숨김 적용 중일 때 즉시 메뉴바에 반영

#import "SettingsWindow.h"

@interface AppRow : NSObject
@property NSString *bundleID, *name, *path;
@property NSImage *icon;
@property BOOL running, isSelf, outside;   // outside = /Applications 밖 (숨김 중 표시 불가)
@end
@implementation AppRow
@end

@interface SettingsController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (weak) id<SpikeSettingsHost> host;
@property NSWindow *window;
@property NSTableView *table;
@property NSSearchField *search;
@property NSSegmentedControl *filter;
@property NSTextField *statusLabel, *countLabel;
@property NSButton *autoBox, *toggleButton;
@property NSArray<AppRow *> *allApps, *shown;
@end

@implementation SettingsController

- (instancetype)initWithHost:(id<SpikeSettingsHost>)host {
    if ((self = [super init])) { _host = host; _allApps = @[]; _shown = @[]; }
    return self;
}

- (BOOL)isVisible { return self.window.isVisible; }

// ── 창 구성 ──
- (void)buildWindow {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 580, 560)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered defer:NO];
    w.title = @"설정 — 메뉴바 관리";
    w.releasedWhenClosed = NO;
    w.minSize = NSMakeSize(440, 360);
    [w center];

    self.search = [NSSearchField new];
    self.search.placeholderString = @"앱 이름 검색";
    self.search.delegate = self;
    self.search.target = self; self.search.action = @selector(filterChanged:);

    self.filter = [NSSegmentedControl segmentedControlWithLabels:@[@"실행 중", @"숨긴 앱", @"전체"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterChanged:)];
    self.filter.selectedSegment = 0;
    [self.filter setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *top = [NSStackView stackViewWithViews:@[self.search, self.filter]];
    top.spacing = 10;

    self.table = [NSTableView new];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"app"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [self.table addTableColumn:col];
    self.table.headerView = nil;
    self.table.rowHeight = 40;
    self.table.style = NSTableViewStyleInset;
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [scroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.countLabel = [NSTextField labelWithString:@""];
    self.countLabel.textColor = NSColor.secondaryLabelColor;
    NSView *spacer1 = [NSView new];
    NSStackView *statusRow = [NSStackView stackViewWithViews:@[self.statusLabel, spacer1, self.countLabel]];

    self.autoBox = [NSButton checkboxWithTitle:@"펼친 뒤 자동으로 다시 숨기기 (10초)" target:self action:@selector(autoChanged:)];
    self.toggleButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleClicked:)];
    NSView *spacer2 = [NSView new];
    NSStackView *bottom = [NSStackView stackViewWithViews:@[self.autoBox, spacer2, self.toggleButton]];

    NSTextField *hint = [NSTextField wrappingLabelWithString:@"스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 메뉴바 아이콘을 좌클릭하면 숨긴 앱이 펼쳐지고, 다시 누르면 숨습니다."];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView *root = [NSStackView stackViewWithViews:@[top, scroll, statusRow, bottom, hint]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [NSView new];
    [content addSubview:root];
    w.contentView = content;
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];
    for (NSView *v in @[top, scroll, statusRow, bottom, hint])
        [v.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

    self.window = w;
}

- (void)show {
    if (!self.window) [self buildWindow];
    [self reloadApps];
    [self refreshStatus];
    [NSApp activateIgnoringOtherApps:YES];     // 메뉴바 전용(LSUIElement) 앱은 직접 앞으로 가져와야 창이 보인다
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

// ── 앱 목록 수집 ──
- (void)addURL:(NSURL *)url running:(BOOL)running into:(NSMutableDictionary<NSString *, AppRow *> *)map {
    NSBundle *b = [NSBundle bundleWithURL:url];
    NSString *bid = b.bundleIdentifier;
    if (!bid) return;
    AppRow *r = map[bid];
    if (!r) {
        r = [AppRow new];
        r.bundleID = bid;
        r.path = url.path;
        NSString *n = [NSFileManager.defaultManager displayNameAtPath:url.path];
        r.name = [n hasSuffix:@".app"] ? [n stringByDeletingPathExtension] : n;
        r.icon = [NSWorkspace.sharedWorkspace iconForFile:url.path];
        r.icon.size = NSMakeSize(22, 22);
        r.isSelf = [bid isEqual:NSBundle.mainBundle.bundleIdentifier];
        r.outside = !([url.path hasPrefix:@"/Applications/"] || [url.path hasPrefix:@"/System/"]);
        map[bid] = r;
    }
    if (running) r.running = YES;
}

- (void)reloadApps {
    NSMutableDictionary<NSString *, AppRow *> *map = [NSMutableDictionary dictionary];
    NSFileManager *fm = NSFileManager.defaultManager;
    // 설치된 앱: /Applications 와 그 한 단계 아래 폴더
    for (NSString *name in [fm contentsOfDirectoryAtPath:@"/Applications" error:nil] ?: @[]) {
        NSString *p = [@"/Applications" stringByAppendingPathComponent:name];
        if ([name hasSuffix:@".app"]) { [self addURL:[NSURL fileURLWithPath:p] running:NO into:map]; continue; }
        BOOL dir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&dir] && dir && ![name hasPrefix:@"."])
            for (NSString *sub in [fm contentsOfDirectoryAtPath:p error:nil] ?: @[])
                if ([sub hasSuffix:@".app"]) [self addURL:[NSURL fileURLWithPath:[p stringByAppendingPathComponent:sub]] running:NO into:map];
    }
    // 실행 중인 앱 (시스템 백그라운드 에이전트와 헬퍼는 제외)
    for (NSRunningApplication *a in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *bid = a.bundleIdentifier; NSURL *url = a.bundleURL;
        if (!bid || !url || a.activationPolicy == NSApplicationActivationPolicyProhibited) continue;
        if ([bid hasPrefix:@"com.apple."] && a.activationPolicy != NSApplicationActivationPolicyRegular) continue;
        NSString *lower = bid.lowercaseString;
        if ([url.path containsString:@".app/Contents/"] && ([lower containsString:@"helper"] || [lower containsString:@"webkit"])) continue;
        [self addURL:url running:YES into:map];
    }
    self.allApps = [map.allValues sortedArrayUsingComparator:^NSComparisonResult(AppRow *x, AppRow *y) { return [x.name localizedCaseInsensitiveCompare:y.name]; }];
    [self applyFilter];
}

- (void)applyFilter {
    NSString *q = self.search.stringValue ?: @"";
    NSSet *hidden = self.host.hiddenIDs;
    NSInteger seg = self.filter.selectedSegment;
    NSMutableArray *out = [NSMutableArray array];
    for (AppRow *r in self.allApps) {
        BOOL ok;
        if (q.length) ok = [r.name localizedCaseInsensitiveContainsString:q] || [r.bundleID localizedCaseInsensitiveContainsString:q];   // 검색은 전체 대상
        else if (seg == 0) ok = r.running;
        else if (seg == 1) ok = [hidden containsObject:r.bundleID];
        else ok = YES;
        if (ok) [out addObject:r];
    }
    self.shown = out;
    [self.table reloadData];
    [self refreshStatus];
}

- (void)refreshStatus {
    if (!self.window) return;
    BOOL on = self.host.restricted;
    self.statusLabel.stringValue = on ? @"상태: 숨김 적용 중" : @"상태: 펼침 (전부 표시)";
    self.toggleButton.title = on ? @"지금 펼치기" : @"지금 숨기기";
    self.autoBox.state = self.host.autoRehide ? NSControlStateValueOn : NSControlStateValueOff;
    NSUInteger hiddenCount = 0;
    for (AppRow *r in self.allApps) if ([self.host.hiddenIDs containsObject:r.bundleID]) hiddenCount++;
    self.countLabel.stringValue = [NSString stringWithFormat:@"목록 %lu개 · 전체 %lu개 · 숨김 %lu개", (unsigned long)self.shown.count, (unsigned long)self.allApps.count, (unsigned long)hiddenCount];
}

// ── 입력 처리 ──
- (void)filterChanged:(id)sender { [self applyFilter]; }
- (void)controlTextDidChange:(NSNotification *)n { [self applyFilter]; }
- (void)autoChanged:(NSButton *)b { self.host.autoRehide = b.state == NSControlStateValueOn; }
- (void)toggleClicked:(id)sender { [self.host toggle]; [self refreshStatus]; }

- (void)rowToggled:(NSSwitch *)sw {
    NSInteger row = [self.table rowForView:sw];
    if (row < 0 || row >= (NSInteger)self.shown.count) return;
    AppRow *r = self.shown[row];
    NSMutableSet *hidden = [self.host.hiddenIDs mutableCopy] ?: [NSMutableSet set];
    if (sw.state == NSControlStateValueOn) [hidden removeObject:r.bundleID]; else [hidden addObject:r.bundleID];
    self.host.hiddenIDs = hidden;
    [self.host hiddenIDsDidChange];
    if (self.filter.selectedSegment == 1 && !self.search.stringValue.length) [self applyFilter]; else [self refreshStatus];
}

// 자동 검증용: 목록에서 해당 앱의 스위치를 실제로 누른 것과 같은 경로로 실행한다.
- (BOOL)debugClickSwitchForBundleID:(NSString *)bid {
    for (NSUInteger i = 0; i < self.shown.count; i++) {
        if (![self.shown[i].bundleID isEqual:bid]) continue;
        NSView *row = [self.table viewAtColumn:0 row:i makeIfNecessary:YES];
        for (NSView *v in row.subviews) if ([v isKindOfClass:NSSwitch.class] && ((NSSwitch *)v).enabled) { [(NSSwitch *)v performClick:nil]; return YES; }
    }
    return NO;
}

// ── 표 ──
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return self.shown.count; }

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    AppRow *r = self.shown[row];
    NSImageView *iv = [NSImageView imageViewWithImage:r.icon ?: [NSImage imageNamed:NSImageNameApplicationIcon]];
    [iv.widthAnchor constraintEqualToConstant:22].active = YES;
    [iv.heightAnchor constraintEqualToConstant:22].active = YES;

    NSTextField *name = [NSTextField labelWithString:r.name ?: r.bundleID];
    name.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *note = r.isSelf ? @"이 앱 — 항상 표시"
                   : r.outside ? @"응용 프로그램 폴더 밖 — 숨김 중에는 표시할 수 없음"
                   : r.running ? @"실행 중" : @"설치됨 · 실행 중 아님";
    NSTextField *sub = [NSTextField labelWithString:note];
    sub.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    sub.textColor = r.outside ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
    sub.lineBreakMode = NSLineBreakByTruncatingTail;
    NSStackView *text = [NSStackView stackViewWithViews:@[name, sub]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 0;
    [text setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [text setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSSwitch *sw = [NSSwitch new];
    sw.controlSize = NSControlSizeSmall;
    sw.target = self; sw.action = @selector(rowToggled:);
    BOOL hidden = [self.host.hiddenIDs containsObject:r.bundleID];
    sw.state = (r.isSelf || (!hidden && !r.outside)) ? NSControlStateValueOn : NSControlStateValueOff;
    sw.enabled = !(r.isSelf || r.outside);
    sw.accessibilityLabel = [NSString stringWithFormat:@"%@ 메뉴바에 표시", r.name];

    [sw setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *rowView = [NSStackView stackViewWithViews:@[iv, text, sw]];
    rowView.distribution = NSStackViewDistributionFill;   // 이름 영역이 늘어나 스위치가 오른쪽 끝에 붙는다
    rowView.spacing = 10;
    rowView.edgeInsets = NSEdgeInsetsMake(0, 6, 0, 8);
    return rowView;
}

@end
