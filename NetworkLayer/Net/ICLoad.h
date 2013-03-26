//
//  ICLoad.h
//  iConsult Enterprise
//
//  Created by finucane on 3/11/13.
//
//

#import "ICProgress.h"
#import "ICAccount.h"
#import "ICProgress.h"
#import "ICNet.h"

@interface ICLoad : ICProgress
{
    @protected
    NSString*baseUrl;
    ICAccount*account;
    ICNet*net;
}

-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl account:(ICAccount*)anAccount;

@end
