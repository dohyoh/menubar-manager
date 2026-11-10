#import "MenuBarPrivateBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const kConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const kAssertionClass = @"MBAssessmentModeAssertion";
static NSString *const kInitSelector = @"initWithAllowedSystemItems:allowedBundleIdentifiers:";
static NSString *const kActivateSelector = @"activateWithConfiguration:completionHandler:";
static NSString *const kInvalidateSelector = @"invalidate";

static NSString *const kErrorDomain = @"MenuBarKit.VisibilityBridge";
static const NSTimeInterval kActivationTimeout = 3.0;

static void LoadFrameworkOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen(kFrameworkPath.fileSystemRepresentation, RTLD_LAZY); });
}

static NSError *BridgeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface MBKVisibilityBridge ()
/// 현재 활성화된(또는 활성화 중인) assertion. 동시에 1개만 유지한다.
@property (nonatomic, strong, nullable) id current;
@end

@implementation MBKVisibilityBridge

+ (BOOL)isSupported {
    LoadFrameworkOnce();
    Class cfg = NSClassFromString(kConfigurationClass);
    Class asr = NSClassFromString(kAssertionClass);
    return cfg != Nil && asr != Nil
        && [cfg instancesRespondToSelector:NSSelectorFromString(kInitSelector)]
        && [asr instancesRespondToSelector:NSSelectorFromString(kActivateSelector)]
        && [asr instancesRespondToSelector:NSSelectorFromString(kInvalidateSelector)];
}

- (BOOL)isRestricted {
    return self.current != nil;
}

- (void)restrictToBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                        systemItems:(NSArray<NSNumber *> *)systemItems
                         completion:(void (^)(NSError *_Nullable))completion {
    if (!MBKVisibilityBridge.isSupported) {
        completion(BridgeError(1, @"unsupported"));
        return;
    }
    Class cfgClass = NSClassFromString(kConfigurationClass);
    Class asrClass = NSClassFromString(kAssertionClass);

    id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)([cfgClass alloc], NSSelectorFromString(kInitSelector), systemItems, bundleIdentifiers);
    id next = [[asrClass alloc] init];
    if (!configuration || !next) {
        completion(BridgeError(2, @"activationFailed"));
        return;
    }

    // 같은 객체로 다시 activate 하면 이전 제한이 해제되지 않고 누적된다(검증됨).
    // 새 assertion 을 먼저 켜고, 완료되면 이전 것을 해제한다.
    id previous = self.current;
    self.current = next;

    __block BOOL finished = NO;
    __weak typeof(self) weakSelf = self;
    void (^finish)(NSError *_Nullable) = ^(NSError *_Nullable error) {
        if (finished) return;
        finished = YES;
        if (previous) ((void (*)(id, SEL))objc_msgSend)(previous, NSSelectorFromString(kInvalidateSelector));
        if (error) {
            // 실패한 assertion 은 버린다. 그 사이 다른 것으로 교체됐다면 건드리지 않는다.
            ((void (*)(id, SEL))objc_msgSend)(next, NSSelectorFromString(kInvalidateSelector));
            if (weakSelf.current == next) weakSelf.current = nil;
        }
        completion(error);
    };

    // 완료 핸들러의 인자는 오류 객체(성공 시 nil)다. 문서화되지 않은 타입이므로 nil 여부만 본다.
    void (^handler)(void *) = ^(void *rawError) {
        BOOL failed = rawError != NULL;
        dispatch_async(dispatch_get_main_queue(), ^{ finish(failed ? BridgeError(2, @"activationFailed") : nil); });
    };

    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(next, NSSelectorFromString(kActivateSelector), configuration, (id)handler);
    } @catch (NSException *exception) {
        finish(BridgeError(2, @"activationFailed"));
        return;
    }

    // 핸들러가 영영 불리지 않는 경우에 대비한다.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kActivationTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(BridgeError(3, @"timedOut"));
    });
}

- (void)unrestrict {
    id current = self.current;
    self.current = nil;
    if (current) ((void (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(kInvalidateSelector));
}

- (void)dealloc {
    if (_current) ((void (*)(id, SEL))objc_msgSend)(_current, NSSelectorFromString(kInvalidateSelector));
}

@end
