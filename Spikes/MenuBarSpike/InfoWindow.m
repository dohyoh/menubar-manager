// 검증용 "정보" 창 — 주요 기능의 간략한 설명 (FR-20 의 최소 구현). 제품 코드가 아닙니다.

#import "InfoWindow.h"

@interface InfoController ()
@property NSWindow *window;
@end

@implementation InfoController

- (BOOL)isVisible { return self.window.isVisible; }

static const CGFloat kTextWidth = 380;

// 한 항목: 아이콘 + 제목 + 설명
- (NSView *)rowWithSymbol:(NSString *)symbol title:(NSString *)title body:(NSString *)body {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil] ?: [NSImage imageNamed:NSImageNameInfo];
    NSImageView *iv = [NSImageView imageViewWithImage:img];
    iv.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular];
    iv.contentTintColor = NSColor.controlAccentColor;
    [iv.widthAnchor constraintEqualToConstant:28].active = YES;
    [iv.heightAnchor constraintEqualToConstant:24].active = YES;

    NSTextField *t = [NSTextField labelWithString:title];
    t.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
    NSTextField *b = [NSTextField wrappingLabelWithString:body];
    b.textColor = NSColor.secondaryLabelColor;
    b.selectable = NO;
    b.preferredMaxLayoutWidth = kTextWidth;
    [b.widthAnchor constraintEqualToConstant:kTextWidth].active = YES;

    NSStackView *text = [NSStackView stackViewWithViews:@[t, b]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 2;

    NSStackView *row = [NSStackView stackViewWithViews:@[iv, text]];
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 10;
    return row;
}

- (void)buildWindow {
    NSTextField *head = [NSTextField labelWithString:@"MenuBarSpike 사용법"];
    head.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    NSString *ver = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"-";
    NSTextField *sub = [NSTextField labelWithString:[NSString stringWithFormat:@"메뉴바 관리 검증용 앱 · 버전 %@", ver]];
    sub.textColor = NSColor.secondaryLabelColor;
    sub.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSArray<NSView *> *rows = @[
        [self rowWithSymbol:@"cursorarrow.click" title:@"숨긴 앱 펼치기 / 숨기기"
                       body:@"메뉴바의 이 앱 아이콘을 좌클릭합니다. 한 번 누르면 숨긴 앱이 모두 나타나고, 다시 누르면 숨습니다."],
        [self rowWithSymbol:@"switch.2" title:@"숨기기 켜고 끄기"
                       body:@"아이콘을 우클릭한 뒤 \"숨기기\" 스위치를 사용합니다. 끄면 다시 켤 때까지 모든 아이콘을 표시합니다."],
        [self rowWithSymbol:@"checklist" title:@"숨길 앱 고르기"
                       body:@"우클릭 > 설정…에서 앱별 스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 앱이 많으면 검색과 필터로 찾습니다."],
        [self rowWithSymbol:@"timer" title:@"자동으로 다시 숨기기"
                       body:@"설정 창에서 켜 두면, 좌클릭으로 펼친 뒤 10초가 지나면 자동으로 다시 숨깁니다."],
        [self rowWithSymbol:@"arrow.left.arrow.right" title:@"메뉴바 아이콘 옮기기"
                       body:@"⌘(Command) 키를 누른 채 메뉴바의 아이콘을 좌우로 드래그하면 순서가 바뀝니다. 숨긴 앱은 먼저 펼친 다음 같은 방법으로 옮깁니다."],
        [self rowWithSymbol:@"exclamationmark.circle" title:@"알아 둘 점"
                       body:@"응용 프로그램 폴더 밖에 있는 앱과 제어 센터에서 꺼낸 항목(타이머 등)은 숨김 중에는 표시되지 않습니다. 이 앱을 종료하면 숨긴 아이콘은 모두 돌아옵니다."],
    ];

    NSMutableArray<NSView *> *all = [NSMutableArray arrayWithObjects:head, sub, nil];
    [all addObjectsFromArray:rows];
    NSStackView *root = [NSStackView stackViewWithViews:all];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14;
    [root setCustomSpacing:2 afterView:head];
    [root setCustomSpacing:18 afterView:sub];
    root.edgeInsets = NSEdgeInsetsMake(20, 22, 22, 22);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [NSView new];
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];

    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 470, 480)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    w.title = @"정보";
    w.releasedWhenClosed = NO;
    w.contentView = content;
    [w setContentSize:content.fittingSize];   // 내용 높이에 맞춤
    [w center];
    self.window = w;
}

- (void)show {
    if (!self.window) [self buildWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

@end
