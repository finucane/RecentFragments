//
//  ICNetConsentVideoForm.h
//  iConsult Enterprise
//
//  Created by finucane on 3/12/13.
//  Donated to the public domain.
//
//

#import "ICNet.h"
#import "ICAccount.h"

@interface ICNetConsentVideoForm : ICNet
{
    @private
    ICAccount*account;
    int maxTries;
    NSMutableArray*workList;
    int workListIndex;
}

-(id)initWithDelegate:(ICProgressDelegate)delegate baseUrl:(NSString*)baseUrl timeout:(NSTimeInterval)timeout maxConnections:(int)maxConnections retries:(int)retries account:(ICAccount*)account completionBlock:(ICNetCompletionBlock)block;
-(BOOL)upload;

@end
