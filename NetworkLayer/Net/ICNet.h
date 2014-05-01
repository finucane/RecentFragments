//
//  ICNet.h
//  iConsult Enterprise
//
//  Created by finucane on 2/13/13.
//  Donated to the public domain.
//
//

/*
 something to add to the object graph based on downloading from the portal. objects are added to
 the managed object context and saved to persistent store in consistent chunks, on any fatal error the context
 is rolled back to the last consistent state and the downloading aborts. assuming the code is correct, there's no
 way you can get the object graph into an inconsitent state using this code.
 
 the error handling is in layers. in the network connection layer, the first error is remembered, the moc is rolled
 back, and all pending connections are cancelled. this causes the operation queue to drain, with all other
 connections being marked as cancellation errors. When the operation queue is drained (when totalReceived == totalSent)
 the high level completion handler is called with the original error. This logic is all done by ICNet:dieFromAnyThread.

 the actual application level code could can use the original error to do high level error handling, for instance if
 downloading and uploading were based on loops that kept going (retrying) as long as progress was being made.
 
 if the ICNet level cancellation block is ever called with the cancel error, it means the download was cancelled by the user doing cancel.
 
 the error reporting is, in the ICNet completion block, [error code] will an ICNetError value and [error localizedDescription]
 will contain any extra information that might have been collected.
  
 the managed object context is assumed to be on the main thread. also the completion blocks should be a single call to
 dispatch_async (dispatch_get_main_queue(), ...), this is for thread safety but also for using closures to keep the underlying
 objects alive.
 
 this code avoids the use of synchronous NSURLConnection calls. one benefit is we can cancel all pending requests as part of
 error handling, or to implement a cancel from the user. another benefit is we can download large files directly to disk.
 
 For a high level example of how to use this code, see ICNetConsentVideos
 
*/

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ICNetOperation.h"
#import "ICProgress.h"

/*this class just lets us know when we have already translated generic errors into errors we know how to handle.*/

@interface ICNetError : NSError
+(ICNetError*)errorWithCode:(int)code description:(NSString*)description;
+(ICNetError*)errorWithCode:(int)code error:(NSError*)error;
+(ICNetError*)randomError;

@end;

typedef void (^ICNetCompletionBlock)(ICNetError*error);

typedef enum ICNetErrorCode
{
    ICNetErrorCancelled = 0,
    ICNetErrorLogin,
    ICNetErrorConnection,
    ICNetErrorDisconnected,
    ICNetErrorTimeout,
    ICNetErrorHttp,
    ICNetErrorServer,
    ICNetErrorJson,
    ICNetErrorCoreData,
    ICNetErrorFile,
    ICNetErrorNumErrors
}ICNetErrorCode;

extern NSString*const kICNetErrorDomain;

@interface ICNet : ICProgress
{
    @public
    unsigned _______totalCompleted; //for ICNetOperation to use as a friend

    @private
    NSManagedObjectContext*moc;
    NSOperationQueue*operationQueue;
    unsigned totalSent;
    ICNetError*originalError;
    ICNetCompletionBlock completionBlock;

    @protected
    NSTimeInterval timeout;
    NSURL*baseUrl;
}


-(id)initWithDelegate:(ICProgressDelegate)delegate baseUrl:(NSString*)baseUrl timeout:(NSTimeInterval)timeout maxConnections:(int)maxConnections managedObjectContext:(NSManagedObjectContext*)moc completionBlock:(ICNetCompletionBlock)block;
-(void)cancel;

/*methods for subclasses to override, calling the superclass methods first*/
-(BOOL)download;
-(BOOL)upload;

/*methods for subclasses to use*/
-(int)pending;
-(BOOL)save;
-(NSManagedObject*)newManagedObject:(NSString*)name error:(ICNetError*__autoreleasing*)error;
-(void)die:(ICNetErrorCode)code description:(NSString*)description;
-(void)dieWithError:(ICNetError*)error;
-(void)retry:(ICNetOperation*)op;
-(void)addFileURL:(NSURL*)url path:(NSString*)path body:(id)body block:(ICNetOperationCompletionBlock)block;
-(void)addDataURL:(NSURL*)url body:(id)body block:(ICNetOperationCompletionBlock)block;
-(void)addUploadURL:(NSURL*)url data:(NSData*)data block:(ICNetOperationCompletionBlock)block;
-(void)ack:(NSString*)tableName identifier:(NSString*)identifier block:(ICNetOperationCompletionBlock)block;
-(BOOL)deleteMatchesSet:(NSMutableSet*)set array:(NSMutableArray*)array setKey:(NSString*)setKey arrayKey:(NSString*)arrayKey deleteKey:(NSString*)deleteKey error:(ICNetError*__autoreleasing*)error;
-(void)update:(NSManagedObject*)owner set:(NSString*)name key:(NSString*)key mo:(NSManagedObject*)mo;
-(void)updateSet:(NSMutableSet*)set key:(NSString*)key mo:(NSManagedObject*)mo;
-(BOOL)removeFromSet:(NSMutableSet*)set key:(NSString*)key value:(id)value;
-(id)valueforKey:(NSString*)key dictionary:(NSDictionary*)dict error:(ICNetError*__autoreleasing*)error;
-(void)callCompletionBlock:(ICNetError*)error;
-(NSArray*)hashesFromSet:(NSSet*)set idKey:(NSString*)idKey hashKey:(NSString*)hashKey;

@property (nonatomic) unsigned maxPending;

/*some macros for readability*/
#define ICNET_SET(v,mo,attr,key,dict,error)\
if (!(v = [self valueforKey:key dictionary:dict error:error]))\
{\
    [mo.managedObjectContext deleteObject:mo];\
    return nil;\
}else{mo.attr = v;};

@end
