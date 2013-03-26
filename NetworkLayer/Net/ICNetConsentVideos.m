//
//  ICNetConsentVideos.m
//  iConsult Enterprise
//
//  Created by finucane on 2/14/13.
//
//

#import "ICNetConsentVideos.h"
#import "ICNetDataOperation.h"
#import "ICConsentVideo.h"

/*the flow through this is:
 
 main --> gotConsentVideos --> gotConsentVideo
                           --> gotConsentVideo
                           ...                              ->completionBlock
 
 each stage in the flow is done on the main thread.
 
 this module handles errors by aborting at the first error and letting the upper layers deal with it (retrying for instance).
*/

/*sample output from server
 [{"ID":"81c43083-b175-4641-9d40-2c51d666b6d4","SpecialtyID":"a92caf6b-f4bf-4084-8685-1549c514c549","SpecialtyName":"OMS","FileName":"Sample Video","Deleted":false}]
 */

#define CONSENT_VIDEOS_URL @"/Api/ConsentVideos/"
#define CONSENT_VIDEO_URL_FORMAT @"/Api/Content/ConsentVideo/%@"
#define CONSENT_VIDEO_TABLE_NAME @"ConsentVideo"

#define ID_KEY @"ID"
#define SPECIALITYID_KEY @"SpecialtyID"
#define SPECIALTY_NAME_KEY @"SpecialtyName"
#define FILENAME_KEY @"FileName"
#define DELETED_KEY @"Deleted"
#define HASH_KEY @"Hash"
#define HASH_ATTR_KEY @"serverHash"
#define ID_ATTR_KEY @"consentMovieId"

#define CONSENT_MOVIES_ATTR_KEY @"consentMovies"
#define CONSENT_MOVIE_ID_ATTR_KEY @"consentMovieId"

@implementation ICNetConsentVideos


-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl timeout:(NSTimeInterval)aTimeout maxConnections:(int)maxConnections account:(ICAccount*)anAccount completionBlock:(ICNetCompletionBlock)block
{
    insist (aBaseUrl && anAccount && block);
    insist ([NSThread isMainThread]);

    if ((self = [super initWithDelegate:aDelegate baseUrl:aBaseUrl timeout:aTimeout maxConnections:maxConnections managedObjectContext:anAccount.managedObjectContext completionBlock:block]))
    {
        account = anAccount;
    }
    return self;
}


/*start the download by requesting a list of consent videos*/
-(BOOL)download
{
    insist (self && [NSThread isMainThread]);
    insist (account);
    
    if (![super download])
        return NO;
    
    /*we are done if we aren't in consent mode, if that's what we decide.*/
    if (!account.consentMode)
    {
        [self description:@"Not in consent mode."];
        [self callCompletionBlock:nil];
        return YES;
    }
    
    __unsafe_unretained ICNetConsentVideos*myself = self;
    [self addDataURL:[NSURL URLWithString:CONSENT_VIDEOS_URL relativeToURL:baseUrl]
                body:[self hashesFromSet:account.consentMovies idKey:ID_ATTR_KEY hashKey:HASH_ATTR_KEY]
               block:^(ICNetOperation*op)
     {
         dispatch_async (dispatch_get_main_queue(), ^{[myself gotConsentVideos:op];});
     }];
    return YES;
}

/*the request for the list of consent videos completed*/
-(void)gotConsentVideos:(ICNetOperation*)op
{
    insist (self && op);
    insist (account);
    insist ([NSThread isMainThread]);

    if (op.error)
    {
        [self dieWithError:op.error];
        return;
    }
    
    __autoreleasing ICNetError*error;
    NSMutableArray*videos = [op jsonArrayWithError:&error];
    if (!videos)
    {
        [self dieWithError:error];
        return;
    }
    
    [self description:@"Got %d consent videos", [videos count]];

    /*delete any items that need deleting*/
    NSMutableSet*set = [account mutableSetValueForKey:CONSENT_MOVIES_ATTR_KEY];
    insist (set);
    
    /*don't bother trying to survive a json error, report the bug instead*/
    if (![self deleteMatchesSet:set array:videos setKey:CONSENT_MOVIE_ID_ATTR_KEY arrayKey:ID_KEY deleteKey:DELETED_KEY error:&error])
    {
        [self dieWithError:error];
        return;
    }
    
    /*update core data. any error is fatal*/
    if (![self save])
        return;
    
    /*for any remaining json items, fetch the videos. we do this even if they already exist, because they might have been updated. set up the work list for this so we can throttle how much we are queueing up. this has nothing to with
        throttling the network connections, but how large the queue itself is allowed to grow
     */

    workList = videos;
    workListIndex = 0;
    [self work];
}

/*queue more requests if we aren't over our limit. also check for doneness.*/
-(void)work
{
    insist (workList && workListIndex <= [workList count]);
    
    /*if we have no more requests, check to see if we are done*/
    if (workListIndex == [workList count])
    {
        if ([self pending] == 0)
            [self callCompletionBlock:nil];
        return;
    }
    
    __autoreleasing ICNetError*error;

    for (;workListIndex < [workList count] && [self pending] < self.maxPending; workListIndex++)
    {
        NSDictionary*d = [workList objectAtIndex:workListIndex];
        
        /*make a video object from the json data.*/
        ICConsentVideo*mo;
        if (!(mo = [self videoWithDictionary:d error:&error]))
        {
            /*if there was an error, we are done*/
            [self dieWithError:error];
            return;
        }
        
        /*queue up an operation to get the video data*/
        __unsafe_unretained ICNetConsentVideos*myself = self;

        [self addFileURL:[baseUrl URLByAppendingPathComponent:[NSString stringWithFormat:CONSENT_VIDEO_URL_FORMAT, mo.consentMovieId]]
                    path:mo.filePathString
                    body:nil block:^(ICNetOperation*op)
         {
             dispatch_async (dispatch_get_main_queue(), ^{[myself gotConsentVideo:mo op:op];});
         }];
    }
}


/*downloading a video finished. if there was no error, complete the managed object. otherwise get rid of it.*/
-(void)gotConsentVideo:(ICConsentVideo*)mo op:(ICNetOperation*)op
{
    insist (self && mo && op);
    insist (account);
    insist ([NSThread isMainThread]);
    
    if (op.error)
    {
        [self dieWithError:op.error];
        return;
    }
    [self description:@"Got consent video %@, pending is %d", mo.name, [self pending]];

    NSMutableSet*set = [account mutableSetValueForKey:CONSENT_MOVIES_ATTR_KEY];
    insist (set);
    
    [self updateSet:set key:CONSENT_MOVIE_ID_ATTR_KEY mo:mo];

    /*we should be magically linked to the account now*/
    insist (mo.account == account);
    
    /*update core data. any error is fatal*/
    if (![self save])
        return;
    
    [self work];
}


/*make a new managed object from json data. if there's any error in the json, clean up and return nil*/
-(ICConsentVideo*)videoWithDictionary:(NSDictionary*)dict error:(ICNetError*__autoreleasing*)error
{
    insist (self && dict && error);
    
    ICConsentVideo*mo = (ICConsentVideo*)[self newManagedObject:kICConsentMovieEntityName error:error];
    if (!mo)
        return nil;
    
    id v;
    ICNET_SET(v, mo, consentMovieId, ID_KEY, dict, error);
    ICNET_SET(v, mo, name, FILENAME_KEY, dict, error);
    ICNET_SET(v, mo, specialtyId, SPECIALITYID_KEY, dict, error);
    ICNET_SET(v, mo, specialtyName, SPECIALTY_NAME_KEY, dict, error);
    ICNET_SET(v, mo, serverHash, HASH_KEY, dict, error);

    return mo;
}

@end