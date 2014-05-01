//
//  ICNetConsentVideos.h
//  iConsult Enterprise
//
//  Created by finucane on 2/14/13.
//  Donated to the public domain.
//
//

#import "ICNet.h"
#import "ICAccount.h"
#import "ICDownloader.h"

@interface ICNetConsentVideos : ICNet
{
    @private
    ICAccount*account;
    NSArray*workList;
    int workListIndex;
}

-(id)initWithDelegate:(ICProgressDelegate)delegate baseUrl:(NSString*)baseUrl timeout:(NSTimeInterval)timeout maxConnections:(int)maxConnections account:(ICAccount*)account completionBlock:(ICNetCompletionBlock)block;
-(BOOL)download;
@end
