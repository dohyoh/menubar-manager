// 검증용 설정 창 — "메뉴바 관리" (FR-17 의 최소 구현)
#import <AppKit/AppKit.h>

@protocol SpikeSettingsHost <NSObject>
@property (nonatomic, copy) NSSet<NSString *> *hiddenIDs;   // 숨길 앱의 번들 ID
@property (nonatomic) BOOL autoRehide;
@property (nonatomic, readonly) BOOL restricted;            // YES = 숨김 적용 중
- (void)hiddenIDsDidChange;                                 // 저장 + (숨김 중이면) 즉시 재적용
- (void)toggle;                                             // 펼치기 ↔ 숨기기
@end

@interface SettingsController : NSObject
- (instancetype)initWithHost:(id<SpikeSettingsHost>)host;
- (void)show;            // 창을 열고 앞으로 가져옴
- (void)reloadApps;      // 앱 목록 다시 수집
- (void)refreshStatus;   // 상태 표시 갱신
@property (nonatomic, readonly) BOOL isVisible;
- (BOOL)debugClickSwitchForBundleID:(NSString *)bundleID;   // 자동 검증용
@end
