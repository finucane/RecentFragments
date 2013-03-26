//
//  ICNetConsentVideoForm.m
//  iConsult Enterprise
//
//  Created by finucane on 3/12/13.
//
//

#import "ICNetConsentVideoForm.h"
#import "ICPatient.h"
#import "ICConsentVideoFormElement.h"
#import "ICConsentVideo.h"
#import "ICContent.h"

#define CONSENT_VIDEO_FORM_URL @"Api/Consent/ConsentVideoForm"
#define CONSENT_VIDEO_FORM_FORMAT @"Api/Content/ConsentVideoForm/%@"
#define PATIENT_ID_KEY @"PatientID"
#define CONSENT_VIDEO_ID_KEY @"ConsentVideoID"
#define FILENAME_KEY @"FileName"
#define ID_KEY @"ID"

@implementation ICNetConsentVideoForm
-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl timeout:(NSTimeInterval)aTimeout maxConnections:(int)aMaxConnections retries:(int)retries account:(ICAccount*)anAccount completionBlock:(ICNetCompletionBlock)block
{
    insist (aDelegate && aBaseUrl && aMaxConnections > 0);
    insist (retries >= 0);
    
    if ([super initWithDelegate:aDelegate baseUrl:aBaseUrl timeout:aTimeout maxConnections:aMaxConnections managedObjectContext:anAccount.managedObjectContext completionBlock:block])
    {
        account = anAccount;
        maxTries = retries + 1;
    }
    return self;
}

-(BOOL)upload
{
    insist (self && account);
    if (![super upload])
        return NO;
    
    /*add every patient that's marked as edited to the work list. in real life it would be someone's job to mark the patient as not edited at some point.*/
    workList = [[NSMutableArray alloc] init];
    for (ICPatient*patient in account.patients)
    {
        if (patient.edited)
            [workList addObject: patient];
    }
    
    workListIndex = 0;
    [self work];
    return YES;
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
    
    for (;workListIndex < [workList count] && [self pending] < self.maxPending; workListIndex++)
    {
        /*we don't limit maxPending more finely than by the top level iteration. if we wanted do, we'd
         unroll this second for loop into an ivar saying what the current index is into the video
         consent form array of the current patient. there's probably just at most 1 form per patient
         anyway*/
        
        ICPatient*patient = [workList objectAtIndex:workListIndex];
        
        /*queue up the first pass requests, these just allocate ids for new consent video forms*/
        for (ICConsentVideoFormElement*consentVideoFormElement in patient.consentVideoForms)
        {
            /*if we already have an element id, it is not new. we have no way of updating in the upload direction, and it probably doesn't make sense since
             once the form is filled out, it becomes read only.
             */
            
            if (consentVideoFormElement.elementId)
                continue;
            
            /*upload assumes that core data is consistent*/
            if (! consentVideoFormElement.video)continue;//we broke our core data
            insist (patient.patientId && consentVideoFormElement.video.consentMovieId);
            insist (consentVideoFormElement.content.fileName);
            insist (consentVideoFormElement.content.data);
            
            NSDictionary*body = @{PATIENT_ID_KEY:patient.patientId,
                                  CONSENT_VIDEO_ID_KEY:consentVideoFormElement.video.consentMovieId,
                                  FILENAME_KEY:consentVideoFormElement.content.fileName};
            
            __unsafe_unretained ICNetConsentVideoForm*myself = self;
            [self addDataURL:[NSURL URLWithString:CONSENT_VIDEO_FORM_URL relativeToURL:baseUrl]
                        body:body
                       block:^(ICNetOperation*op)
             {
                 dispatch_async (dispatch_get_main_queue(), ^{[myself gotConsentVideoFormId:op consentVideoFormElement:consentVideoFormElement];});
             }];
        }
    }
}

/*used to deal with errors, retry or die. this would be refactored into a superclass if we decide we want to do retries*/
-(void)error:(ICNetError*)error operation:(ICNetOperation*)op
{
    insist (error && op);
    insist (op.numTries > 0 && op.numTries <= maxTries);
    
    if (op.numTries == maxTries)
    {
        [self description:@"Exceeded %d tries with URL %@", maxTries, op.url];
        [self dieWithError:error];
    }
    else
    {
        [self description:@"Retrying %@", op.url];
        [self retry:[op retryWithNet:self]];
    }
}

-(void)gotConsentVideoFormId:(ICNetOperation*)op consentVideoFormElement:(ICConsentVideoFormElement*)consentVideoFormElement
{
    insist (self && op);
    insist (consentVideoFormElement);
    insist (!consentVideoFormElement.elementId);
    insist (consentVideoFormElement.content.data);
    
    insist ([NSThread isMainThread]);
    
    /*if there's some kind of underlying network error, retry. since the upload api has a race condition, this can fill the consent video form
     table with empty forms, and make the app unstable no matter how much random typing we do on our typewriters.
     */
    if (op.error)
    {
        [self error:op.error operation:op];
        return;
    }
    
    /*if there's a json error, give up*/
    __autoreleasing ICNetError*error;
    NSDictionary*dict = [op jsonDictionaryWithError:&error];
    if (!dict)
    {
        [self dieWithError:error];
        return;
    }
    
    /*the only thing that's returned is the new ID for the consent video form*/
    NSString*elementId = [dict valueForKey:ID_KEY];
    
    if (!elementId)
    {
        ICNetError*error = [ICNetError errorWithCode:ICNetErrorJson description:[NSString stringWithFormat:@"Missing ID value in consent video form."]];
        insist (error);
        [self dieWithError:error];
        return;
    }
    
    [self description:@"New id %@", elementId];
    
    /*post the form as data*/
    __unsafe_unretained ICNetConsentVideoForm*myself = self;
    [self addUploadURL:[NSURL URLWithString:[NSString stringWithFormat:CONSENT_VIDEO_FORM_FORMAT, elementId] relativeToURL:baseUrl]
                  data:consentVideoFormElement.content.data
                 block:^(ICNetOperation*op){
         dispatch_async (dispatch_get_main_queue(), ^{[myself postedConsentVideoForm:op consentVideoFormElement:consentVideoFormElement elementId:elementId];
         });
     }];
    
    
}

-(void)postedConsentVideoForm:(ICNetOperation*)op consentVideoFormElement:(ICConsentVideoFormElement*)consentVideoFormElement elementId:(NSString*)elementId
{
    insist (self && op);
    insist (consentVideoFormElement);
    insist (!consentVideoFormElement.elementId);
    insist (elementId);
    
    /*retry or die on errors*/
    if (op.error)
    {
        [self error:op.error operation:op];
        return;
    }
    
    [self description:@"Posted data for id %@", elementId];
    
    /*we may have totally trashed the server, but at least we know we are consistent*/
    consentVideoFormElement.elementId = elementId;
    
    /*do more work or notice that we are done and be done*/
    [self work];
}

@end
