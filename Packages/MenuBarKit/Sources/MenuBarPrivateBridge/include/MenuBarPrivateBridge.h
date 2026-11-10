// macOS 비공개 API 접점. 비공개 클래스명·셀렉터 문자열은 이 타깃 밖에 두지 않는다.
// 링크하지 않고 런타임 조회(dlopen, NSClassFromString)로만 접근하며, 없으면 조용히 "지원 안 됨"을 돌려준다.
// 근거와 검증 기록: docs/architecture/platform-notes.md 3.2~3.8, docs/adr/0003-visibility-mechanism.md

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 메뉴바 표시 제한(허용 목록). 메인 스레드에서만 사용한다.
NS_SWIFT_UI_ACTOR
@interface MBKVisibilityBridge : NSObject

/// 이 macOS 에 필요한 시스템 클래스와 메서드가 있는가.
@property (class, nonatomic, readonly) BOOL isSupported;

/// 지금 제한을 걸고 있는가.
@property (nonatomic, readonly) BOOL isRestricted;

/// 허용 목록에 있는 앱·시스템 아이템만 메뉴바에 남긴다.
/// 이미 제한 중이면 새 제한을 먼저 켠 뒤 이전 것을 해제해 깜빡임 없이 교체한다.
/// completion 은 메인 큐에서 한 번 호출된다. 성공이면 error 가 nil.
- (void)restrictToBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                        systemItems:(NSArray<NSNumber *> *)systemItems
                         completion:(void (^)(NSError *_Nullable error))completion;

/// 제한 해제 — 전부 표시.
- (void)unrestrict;

@end

NS_ASSUME_NONNULL_END
