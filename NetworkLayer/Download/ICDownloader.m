//
//  ICDownloader.m
//  iConsult Enterprise
//
//  Created by finucane on 3/6/13.
//  Donated to the public domain.
//
//



#import "ICDownloader.h"
#import "ICNetConsentVideos.h"
#import "ICNetPatientSketches.h"
 
/*hardcoded numbers. in real code these might be app settings with reasonable defaults.*/
#define TIMEOUT 60*5
#define MAX_CONNECTIONS 50
#define RETRIES 99

@implementation ICDownloader


-(void)start
{
    [self pending:0];
    [self startPatientSketches];
}

-(void)startPatientSketches
{
    [self phase:@"Patient Sketches"];
    
    /*get an array of all the patients*/
    NSArray*patients = [account.patients allObjects];
    
    /*if there aren't any, we are done*/
    
    if (!patients || ![patients count])
    {
        [self description:@"No patients. Done"];
        [self patientSketchesDone:nil];
        return;
    }
    
    /*for testing the code, this thing is a global switch so it should be set to 0 later.*/
   // [self description:@"Inducing a 50% error rate in the network layer."];
    //[ICNetOperation setErrorRate:2];
    
    net = [[ICNetPatientSketches alloc] initWithDelegate:self.delegate
                                                 baseUrl:baseUrl
                                                 timeout:TIMEOUT
                                          maxConnections:MAX_CONNECTIONS
                                                 retries:RETRIES
                                                patients:patients
                                         completionBlock:^(ICNetError*error)
           {
               
               dispatch_async (dispatch_get_main_queue(), ^{
                   [self patientSketchesDone:error];
               });
           }];
    insist (net);
    
    /*if we want to limit how much queue space the download takes we set maxPending to something other than whatever the default is*/
    //net.maxPending = 10;
    [net download];
}

/*
 example of reliability done at a lower level than this.
 
 ICNet has request retries built into its design, so it's no effort to retry there.
*/

-(void)patientSketchesDone:(ICNetError*)error
{
    /*fault the object graph to make sure it's consistent and to limit our memory footprint*/
    [account.managedObjectContext refreshObject:account mergeChanges:NO];
    
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
    [self startConsentVideos];
}


-(void)startConsentVideos
{
    [self phase:@"Consent Videos"];
    
    net = [[ICNetConsentVideos alloc] initWithDelegate:self.delegate
                                               baseUrl:baseUrl
                                               timeout:TIMEOUT
                                        maxConnections:MAX_CONNECTIONS
                                               account:account
                                       completionBlock:^(ICNetError*error)
           {
               
               dispatch_async (dispatch_get_main_queue(), ^{
                   [self consentVideosDone:error];
               });
           }];
    insist (net);
    
   // net.maxPending = 3;//testing this

    [net download];
}

/*
 example of retrying at this level, not using the lower level retry functionality.
*/

-(void)consentVideosDone:(ICNetError*)error
{
    /*fault the object graph to make sure it's consistent and to limit our memory footprint*/
    [account.managedObjectContext refreshObject:account mergeChanges:NO];
    
    if (error)
    {
        if (error.code == ICNetErrorCancelled)
        {
            [self done:nil];
            return;
        }
        if (error.code == ICNetErrorTimeout)
        {
            [self description:@"Timed out. Retrying."];
            [self startConsentVideos];
            return;
        }
        [self description:@"Failed with error %@", error.localizedDescription];
        [self done:error];
        return;
    }
    
    [self description:@"Download done."];
    net = nil;
    
    /*last item in our chain, we are done*/
    [self done:nil];
}


@end
