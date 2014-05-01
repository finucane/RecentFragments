//
//  ICNetOperation.h
//  iConsult Enterprise
//
//  Created by finucane on 2/13/13.
//  Donated to the public domain.
//
//

#import <Foundation/Foundation.h>

@class ICNetOperation;
@class ICNetError;
@class ICNet;



typedef void (^ICNetOperationCompletionBlock)(ICNetOperation*);

@interface ICNetOperation : NSOperation <NSURLConnectionDelegate>
{
    @private
    NSURLConnection*connection;
    BOOL isFinished;
    BOOL isExecuting;

    @protected
    ICNetOperationCompletionBlock block;
    int numTries;
    NSURLRequest*request;
    ICNetError*error;
    ICNet*net;
}

-(id)initWithRequest:(NSURLRequest*)request net:(ICNet*)net completionBlock:(ICNetOperationCompletionBlock)block;
-(id)initWithUrl:(NSString*)url net:(ICNet*)net completionBlock:(ICNetOperationCompletionBlock)block;
-(ICNetError*)error;
-(NSMutableArray*)jsonArrayWithError:(ICNetError*__autoreleasing*)error;
-(NSDictionary*)jsonDictionaryWithError:(ICNetError*__autoreleasing*)error;
-(NSString*)dataAsString;
-(int)numTries;
-(ICNetOperation*)retryWithNet:(ICNet*)net;
-(NSString*)url;
+(NSString*)stringOfRequest:(NSURLRequest*)req;

/*subclasses should call this on error*/
-(BOOL)die:(int)errorCode description:(NSString*)description;

/*concrete subclasses should override these*/
-(BOOL)appendData:(NSData*)data;
-(BOOL)resetData;
-(NSData*)data;

/*if overriding this call super at end*/
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)anError;

/*setting this to nonzero simulates errors in the entire "Net" module, this is for testing the code. an error rate of 5 means 1 out of 4 times
 operations will fail*/
+(void)setErrorRate:(unsigned)rate;

@end