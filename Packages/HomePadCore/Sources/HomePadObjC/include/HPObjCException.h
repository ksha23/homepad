#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the Objective-C exception it raised, or nil. Swift
/// cannot catch these, and a few framework calls raise them instead of
/// returning an error (an AVAudioNode tap with a stale format).
FOUNDATION_EXPORT NSException *_Nullable HPCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
