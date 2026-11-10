// 검증용 "정보" 창 — 주요 기능의 간략한 설명 (FR-20 의 최소 구현)
#import <AppKit/AppKit.h>

@interface InfoController : NSObject
- (void)show;
@property (nonatomic, readonly) BOOL isVisible;
@end
