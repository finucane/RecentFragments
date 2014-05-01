//
//  ICNetPatientSketches.h
//  iConsult Enterprise
//
//  Created by finucane on 3/6/13.
//  Donated to the public domain.
//
//

#import "ICNet.h"
#import "ICAccount.h"
#import "ICDownloader.h"

@interface ICNetPatientSketches : ICNet
{
    @private
    NSArray*patients;
    int maxTries;
    NSArray*workList;
    int workListIndex;
}
-(id)initWithDelegate:(ICProgressDelegate)delegate baseUrl:(NSString*)baseUrl timeout:(NSTimeInterval)timeout maxConnections:(int)maxConnections retries:(int)retries patients:(NSArray*)patients completionBlock:(ICNetCompletionBlock)block;
-(BOOL)download;
@end
