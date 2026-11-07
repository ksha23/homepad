#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
#import <Foundation/Foundation.h>

// The iOS Simulator's Metal SDK does not export these, but MLX refers to them
// when it loads. Device builds use Metal's own.
NSString * const MTLIOErrorDomain = @"MTLIOErrorDomain";
NSString * const MTLTensorDomain = @"MTLTensorDomain";
#endif
