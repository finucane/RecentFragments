//
//  ICNet.m
//  iConsult Enterprise
//
//  Created by finucane on 2/13/13.
//
//

#import "insist.h"
#import <CoreData/CoreData.h>
#import "ICNet.h"
#import "ICNetOperation.h"
#import "ICNetDataOperation.h"
#import "ICNetFileOperation.h"
#import <stdlib.h>

/*default value for this, to limit the size of the queue*/
#define MAX_PENDING 32000

NSString*const kICNetErrorDomain = @"ICNetErrorDomain";

#define ACK_URL @"/Api/Syncs/Sync/"
#define TABLE_NAME @"TableName"
#define PRIMARY_KEY @"PrimaryKey"
#define ID_KEY @"ID"
#define HASH_KEY @"Hash"

@implementation ICNetError
+(ICNetError*)errorWithCode:(int)code description:(NSString*)description
{
    return [ICNetError errorWithDomain:kICNetErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:description}];
}
+(ICNetError*)errorWithCode:(int)code error:(NSError*)error
{
    return [ICNetError errorWithDomain:kICNetErrorDomain code:code userInfo:error.userInfo];
}
-(NSString*)stringForCode:(ICNetErrorCode)code
{
    switch (code)
    {
        case ICNetErrorCancelled: return @"Cancelled";
        case ICNetErrorLogin: return @"Not Logged In";
        case ICNetErrorConnection: return @"Connection";
        case ICNetErrorDisconnected: return @"Network Down";
        case ICNetErrorTimeout: return @"Timeout";
        case ICNetErrorHttp: return @"Http";
        case ICNetErrorServer: return @"Server";
        case ICNetErrorJson: return @"JSON";
        case ICNetErrorCoreData: return @"Core Data";
        case ICNetErrorFile: return @"File System";
        default:insist (0);
    }
    return @"";
}

+(ICNetError*)randomError
{
    return [ICNetError errorWithCode:arc4random_uniform (ICNetErrorNumErrors - 1) + 1 description:@"Random error."];
}

-(NSString*)localizedDescription
{
    return [NSString stringWithFormat:@"ICNetError \"%@\" %@", [self stringForCode:self.code], self.userInfo];
}
@end;


@implementation ICNet


-(id)initWithDelegate:(ICProgressDelegate)delegate baseUrl:(NSString*)aBaseUrl timeout:(NSTimeInterval)aTimeout maxConnections:(int)maxConnections managedObjectContext:(NSManagedObjectContext*)aMoc completionBlock:(ICNetCompletionBlock)block
{
    insist (aBaseUrl && aMoc && block);
    
    if (self = [super initWithDelegate:delegate])
    {
        operationQueue = [[NSOperationQueue alloc] init];
        insist (operationQueue);
        
        /*save a bunch of parameters*/
        timeout = aTimeout;
        baseUrl = [NSURL URLWithString:aBaseUrl];
        moc = aMoc;
        operationQueue.maxConcurrentOperationCount = maxConnections;
        completionBlock = block;
        
        /*leading underscores are a convention to tell the programmer he should not be touching a variable.
          we need totalCompleted to be accessible outside this class in one line in ICNetOperation.m, which
          is sort of a friend class to this. and _maxPending is the backing store for the maxPending property
          and should never be accessed directly, except we have to do somewhere to init it.
         */
         totalSent = _______totalCompleted = 0;
        _maxPending = MAX_PENDING;
    }
    return self;
}


/*these are really just ways to start the chain of callbacks that is either an upload or a download. as far as ICNet is concerned
  there's no difference between them. only the subclasses care*/
-(BOOL)download
{
    insist ([NSThread isMainThread]);
    
    if (![self save])
        return NO;
    return YES;
}

-(BOOL)upload
{
    return [self download];
}

/*for anyone to cancel with. clean up core data and make every connection a cancel. probably useless code because of a race condition.*/
-(void)cancel
{
    insist (self && operationQueue);
    insist ([NSThread isMainThread]);
    
    [moc rollback];
    [operationQueue cancelAllOperations];
    
    originalError = [ICNetError errorWithCode:ICNetErrorCancelled description:@""];
}

-(int)pending
{
    insist (totalSent >= _______totalCompleted);
    return totalSent - _______totalCompleted;
}

-(NSManagedObject*)newManagedObject:(NSString*)name error:(ICNetError*__autoreleasing*)error
{
    insist (self && moc && name && [name length]);
    insist (error);
    
    NSManagedObject*mo;
    @try
    {
        mo = [NSEntityDescription insertNewObjectForEntityForName:name inManagedObjectContext:moc];
    }
    @catch (NSException *exception)
    {
        *error = [ICNetError errorWithCode:ICNetErrorCoreData description:exception.reason];
        return nil;
    }
    return mo;
}

/*grab all the descriptions out of an error coming from an NSManagedObjectContext call (save)*/
-(NSString*)descriptionFromMocError:(NSError*)error
{
    insist (self && error);
    NSMutableString*s = [[NSMutableString alloc] init];
    insist (s);
    
    /*first get the description of the error*/
    [s appendString:[error localizedDescription]];
    
    /*if there was more than one error, grab all of them too*/
    NSArray*errors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
    if (errors)
    {
        for (NSError*e in errors)
            [s appendString: [e localizedDescription]];
    }
    return s;
}


-(BOOL)save
{
    insist (self && [NSThread isMainThread]);
    __autoreleasing NSError*error;
    
    if (![moc save:&error])
    {
        [self die:ICNetErrorCoreData description:[self descriptionFromMocError:error]];
        return NO;
    }
    return YES;
}

/*this is to make sure the cancel logic is always followed by subclasses, since it's required to
 deal with draining the operation queue and returning the actual error to the upper layers
 */
-(void)callCompletionBlock:(ICNetError*)error
{
    insist (completionBlock);
    completionBlock (originalError ? originalError : error);
    completionBlock = nil;
}

-(void)dieWithError:(ICNetError*)error
{
    insist ([NSThread isMainThread]);
    
    /*if we are the real error, handle it here. everything else is a side effect of the first error or a cancel call*/
    if (error.code != ICNetErrorCancelled)
    {
        /*give up on whatever we might have been planning on doing*/
        [operationQueue cancelAllOperations];
        
        /*rollback any pending modifications to the moc*/
        [moc rollback];
        
        /*remember the actual error*/
        originalError = error;
    }
    
    insist (originalError);
    /*call completion block if the operation queue is drained*/
    if ([self pending] == 0)
        [self callCompletionBlock:originalError];
}
-(void)die:(ICNetErrorCode)code description:(NSString*)description
{
    [self dieWithError:[ICNetError errorWithCode:code description:description]];
}

/*make a json request, with some optional array/dictionary stuff to attach as json*/
-(NSURLRequest*)requestWithUrl:(NSURL*)url body:(id)body
{
    insist (url);
    
    NSMutableURLRequest*request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:timeout];
    
    if (body)
    {
        insist ([body isKindOfClass:[NSArray class]] || [body isKindOfClass:[NSDictionary class]]);
        
        __autoreleasing NSError *dc = nil;
        NSData*json = [NSJSONSerialization dataWithJSONObject:body options:0 error:&dc];
        insist (json);
        
        [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
        [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
        
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody: json];
    }
    return request;
}

/*make an upload request*/
-(NSURLRequest*)requestWithUrl:(NSURL*)url data:(NSData*)data
{
    insist (url && data);
    
    NSMutableURLRequest*request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:timeout];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setHTTPMethod: @"POST"];
    
    NSString*boundary = @"---------------------------114782935826962";
    NSString*contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
    [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
    
    NSMutableData*body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"param1\"; filename=\"thefilename\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:body];
    return request;
}


/*op can only be an op created by one of the "add" functions below.*/
-(void)retry:(ICNetOperation*)op
{
    insist (op);
    insist (op.numTries > 1);
    totalSent++;
    [operationQueue addOperation:op];
}

/*
 these 2 methods are only for internal use, because they assume timeout has been set in the request.
 */

-(void)addDataRequest:(NSURLRequest*)request block:(ICNetOperationCompletionBlock)block
{
    ICNetDataOperation*op = [[ICNetDataOperation alloc] initWithRequest:request net:self completionBlock:block];
    insist (op);
    totalSent++;
    [operationQueue addOperation:op];
    
    //NSLog (@"%@", [ICNetOperation stringOfRequest:request]);
}
-(void)addFileRequest:(NSURLRequest*)request path:(NSString*)path block:(ICNetOperationCompletionBlock)block
{
    ICNetFileOperation*op = [[ICNetFileOperation alloc] initWithRequest:request net:self path:path completionBlock:block];
    insist (op);
    totalSent++;
    [operationQueue addOperation:op];
}

/*these 4 are the only way to actually send any requests in all of the ICNet stuff*/
-(void)addDataURL:(NSURL*)url body:(id)body block:(ICNetOperationCompletionBlock)block
{
    [self addDataRequest:[self requestWithUrl:url body:body] block:block];
}

-(void)addFileURL:(NSURL*)url path:(NSString*)path body:(id)body block:(ICNetOperationCompletionBlock)block
{
    [self addFileRequest:[self requestWithUrl:url body:body] path:path block:block];
}

/*send a sync ack to the portal.*/
-(void)ack:(NSString*)tableName identifier:(NSString*)identifier block:(ICNetOperationCompletionBlock)block
{
    NSURLRequest*request = [self requestWithUrl:[NSURL URLWithString:ACK_URL relativeToURL:baseUrl] body:@{TABLE_NAME:tableName, PRIMARY_KEY:identifier}];
    insist (request);
    
    [self addDataRequest:request block:block];
}

-(void)addUploadURL:(NSURL*)url data:(NSData*)data block:(ICNetOperationCompletionBlock)block
{
    NSURLRequest*request = [self requestWithUrl:url data:data];
    insist (request);
    
    [self addDataRequest:request block:block];
}

/*return an array suitable for posting as part of the hashes part of a request*/
-(NSArray*)hashesFromSet:(NSSet*)set idKey:(NSString*)idKey hashKey:(NSString*)hashKey
{
    insist (set && idKey && hashKey);
    NSMutableArray*hashes = [[NSMutableArray alloc] init];
    insist (hashes);
    
    for (NSManagedObject*mo in set)
    {
        insist ([mo valueForKey:idKey] && [mo valueForKey:hashKey]);
        [hashes addObject:@{ID_KEY:[mo valueForKey:idKey], HASH_KEY:[mo valueForKey:hashKey]}];
    }
    return hashes;
}
/*
 delete objects from a core data nsset proxy that are marked as deleted in the json array. remove the corresponding objects from the array as well.
 return false if there was any error.
 */
-(BOOL)deleteMatchesSet:(NSMutableSet*)set array:(NSMutableArray*)array setKey:(NSString*)setKey arrayKey:(NSString*)arrayKey deleteKey:(NSString*)deleteKey error:(ICNetError*__autoreleasing*)error
{
    insist (self && set && array && setKey && arrayKey && deleteKey);
    insist (error);
    
    /*simple n^2 search, using a loop variable for the outer loop because you can't do this with iteration*/
    for (int i = 0; i < [array count]; i++)
    {
        NSDictionary*json = [array objectAtIndex:i];
        NSNumber*deleted = [json valueForKey:deleteKey];
        
        id arrayValue = [json valueForKey:arrayKey];
        
        if (!arrayValue)
        {
            *error = [ICNetError errorWithCode:ICNetErrorJson description:[NSString stringWithFormat:@"Missing key %@, json is:%@.", arrayKey, json]];
            return NO;
        }
        if (!deleted)
        {
            *error = [ICNetError errorWithCode:ICNetErrorJson description:@"No delete key."];
            return NO;
        }
        if (![deleted isKindOfClass:[NSNumber class]])
        {
            *error = [ICNetError errorWithCode:ICNetErrorJson description:[NSString stringWithFormat:@"Malformed delete key not an NSNumber (%@), json is:%@", deleted.description, json]];
            return NO;
        }
        if (![deleted boolValue])
            continue;
        
        for (NSManagedObject*mo in set)
        {
            id setValue = [mo valueForKey:setKey];
            insist (setValue);
            
            if ([setValue isEqual:arrayValue])
            {
                [set removeObject:mo];
                [array removeObjectAtIndex:i];
                break;
            }
        }
    }
    return YES;
}

/*
 add or replace an item in a managed object set, uniqueness is determined by key. if it turns out that this causes too much faulting, we can write the hard way.
 but really we shouldn't be scared of this sort of thing.
 */

-(void)updateSet:(NSMutableSet*)set key:(NSString*)key mo:(NSManagedObject*)mo
{
    insist (self && key && mo);
    
    /*handle case where the object already exists.*/
    
    id value = [mo valueForKey:key];
    insist (value);
    [self removeFromSet:set key:key value:value];
    
    /*add the object*/
    [set addObject:mo];
}

/*remove the object, if any, from set with key value equal to value. return YES if an object was removed*/
-(BOOL)removeFromSet:(NSMutableSet*)set key:(NSString*)key value:(id)value;
{
    insist (self && key);
    insist (value);
    
    /*handle case where the object already exists. it's not safe to modify a set in an enumeration*/
    NSManagedObject*o = nil;
    
    for (o in set)
    {
        if ([[o valueForKey:key]isEqual:value])
            break;
    }
    if (o)
    {
        [set removeObject:o];
        return YES;
    }
    return NO;
}

-(void)update:(NSManagedObject*)owner set:(NSString*)name key:(NSString*)key mo:(NSManagedObject*)mo
{
    NSMutableSet*set = [owner mutableSetValueForKey:name];
    insist (set);
    [self updateSet:set key:key mo:mo];
}


-(id)valueforKey:(NSString*)key dictionary:(NSDictionary*)dict error:(ICNetError*__autoreleasing*)error
{
    insist (self && key && dict && error);
    
    id v;
    v = [dict valueForKey:key];
    if (!v)
    {
        *error = [ICNetError errorWithCode:ICNetErrorJson description:[NSString stringWithFormat:@"Missing key %@, json is:%@", key, dict]];
        return nil;
    }
    return v;
}
@end
