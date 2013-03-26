//
//  ICLoader.m
//  iConsult Enterprise
//
//  Created by finucane on 3/11/13.
//
//

#import "ICLoad.h"

@implementation ICLoad


-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl account:(ICAccount*)anAccount
{
    insist (aBaseUrl && anAccount);
    insist (aDelegate);
    
    if ((self = [super initWithDelegate:aDelegate]))
    {
        baseUrl = aBaseUrl;
        account = anAccount;
    }
    return self;
}

/*we are synchronizing on the main thread so we know that there's still downloading going on. the cancel will result in
 an ICNet completionBlock being called with ICNetErrorCancelled which will end this module cleanly.
 */
-(void)cancel
{
    insist (net);
    insist ([NSThread isMainThread]);
    
    [net cancel];
    net = nil;
}
@end
