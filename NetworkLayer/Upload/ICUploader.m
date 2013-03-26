//
//  ICUploader.m
//  iConsult Enterprise
//
//  Created by finucane on 3/11/13.
//
//

#import "ICUploader.h"
#import "ICNetConsentVideoForm.h"

/*hardcoded numbers. in real code these might be app settings with reasonable defaults.*/
#define TIMEOUT 60*5
#define MAX_CONNECTIONS 50
#define RETRIES 99

@implementation ICUploader

-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl account:(ICAccount*)anAccount
{
    insist (aDelegate && aBaseUrl && anAccount);
    
    if ((self = [super initWithDelegate:aDelegate]))
    {
        baseUrl = aBaseUrl;
        account = anAccount;
    }
    return self;
}
-(void)start
{
    [self phase:@"Upload"];
    [self startConsentVideoForms];
}

-(void)startConsentVideoForms
{
    [self phase:@"Consent Video Forms"];
    
  //  [self description:@"Try to show the race condition in the upload api by faking network errors."];
   // [ICNetOperation setErrorRate:2];
    
    net = [[ICNetConsentVideoForm alloc] initWithDelegate:self.delegate
                                                  baseUrl:baseUrl
                                                  timeout:TIMEOUT
                                           maxConnections:MAX_CONNECTIONS
                                                  retries:RETRIES
                                                  account:account
                                          completionBlock:^(ICNetError *error)
           {
               dispatch_async (dispatch_get_main_queue(), ^{
                   [self consentVideosDone:error];
               });
           }];
    insist (net);
    
    net.maxPending = 1000;
    [net upload];
    
}

-(void)consentVideosDone:(NSError*)error
{
    [ICNetOperation setErrorRate:0];
    
    if (error)
    {
        if (error.code == ICNetErrorCancelled)
        {
            [self done:nil];
            return;
        }
        
        [self description:@"Failed with error %@", error.localizedDescription];
        [self done:error];
        return;
    }
    
    [self done:nil];
}


@end
