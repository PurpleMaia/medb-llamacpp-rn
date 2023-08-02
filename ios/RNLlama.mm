#import "RNLlama.h"
#import "RNLlamaContext.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import "RNLlamaSpec.h"
#endif

@implementation Llama

NSMutableDictionary *contexts;
double context_limit = 1;

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(setContextLimit:(double)limit
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    context_limit = limit;
    resolve(nil);
}

RCT_EXPORT_METHOD(initContext:(NSDictionary *)contextParams
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    if (contexts == nil) {
        contexts = [[NSMutableDictionary alloc] init];
    }

    if (context_limit > 0 && [contexts count] >= context_limit) {
        reject(@"llama_error", @"Context limit reached", nil);
        return;
    }

    RNLlamaContext *context = [RNLlamaContext initWithParams:contextParams];
    if (![context isModelLoaded]) {
        reject(@"llama_cpp_error", @"Failed to load the model", nil);
        return;
    }

    double contextId = (double) arc4random_uniform(1000000);

    NSNumber *contextIdNumber = [NSNumber numberWithDouble:contextId];
    [contexts setObject:context forKey:contextIdNumber];

    resolve(contextIdNumber);
}

- (NSArray *)supportedEvents {
  return@[
    @"@RNLlama_onToken",
  ];
}

RCT_EXPORT_METHOD(completion:(double)contextId
                 withCompletionParams:(NSDictionary *)completionParams
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    RNLlamaContext *context = contexts[[NSNumber numberWithDouble:contextId]];
    if (context == nil) {
        reject(@"llama_error", @"Context not found", nil);
        return;
    }
    if ([context isPredicting]) {
        reject(@"llama_error", @"Context is busy", nil);
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSDictionary* completionResult = [context completion:completionParams
                onToken:^(NSDictionary *tokenResult) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self sendEventWithName:@"@RNLlama_onToken"
                            body:@{
                                @"contextId": [NSNumber numberWithDouble:contextId],
                                @"tokenResult": tokenResult
                            }
                        ];
                    });
                }
            ];
            resolve(completionResult);
        } @catch (NSException *exception) {
            reject(@"llama_cpp_error", exception.reason, nil);
        }
    });
    
}

RCT_EXPORT_METHOD(stopCompletion:(double)contextId
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    RNLlamaContext *context = contexts[[NSNumber numberWithDouble:contextId]];
    if (context == nil) {
        reject(@"llama_error", @"Context not found", nil);
        return;
    }
    [context stopCompletion];
    resolve(nil);
}

RCT_EXPORT_METHOD(releaseContext:(double)contextId
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    RNLlamaContext *context = contexts[[NSNumber numberWithDouble:contextId]];
    if (context == nil) {
        reject(@"llama_error", @"Context not found", nil);
        return;
    }
    [context stopCompletion];
    [context invalidate];
    [contexts removeObjectForKey:[NSNumber numberWithDouble:contextId]];
    resolve(nil);
}

RCT_EXPORT_METHOD(releaseAllContexts:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    [self invalidate];
    resolve(nil);
}


- (void)invalidate {
    if (contexts == nil) {
        return;
    }

    for (NSNumber *contextId in contexts) {
        RNLlamaContext *context = contexts[contextId];
        [context invalidate];
    }

    [contexts removeAllObjects];
    contexts = nil;

    [super invalidate];
}

// Don't compile this code when we build for the old architecture.
#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeRNLlamaSpecJSI>(params);
}
#endif

@end