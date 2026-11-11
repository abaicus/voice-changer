#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the reason of any Objective-C exception it raises, or nil if none.
FOUNDATION_EXPORT NSString * _Nullable VCCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
