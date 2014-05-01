//
//  ICNetPatientSketches.m
//  iConsult Enterprise
//
//  Created by finucane on 3/6/13.
//  Donated to the public domain.
//
//

#import "ICNetPatientSketches.h"
#import "ICPatient.h"
#import "ICPatientSketchElement.h"
#import "ICSecureContent.h"

#define PATIENT_SKETCHES_FORMAT @"Api/PatientSketches/%@"
#define PATIENT_SKETCH_FORMAT @"/Api/PatientSketches/PatientSketch/%@"
#define PATIENT_SKETCH_TABLE_NAME @"PatientSketch"

#define ID_KEY @"ID"
#define PATIENT_ID_KEY @"PatientID"
#define NAME_KEY @"Name"
#define FILENAME_KEY @"FileName"
#define FILE_EXTENSION_KEY @"FileExtension"

#define SKETCHES_ATTR_KEY @"sketches"
#define SKETCH_ID_ATTR_KEY @"elementId"

/*
 the error handling in this module is that for network errors, operations will be retried some number of times before the module fails. any other error (json errors) will
 cause the module to fail, the higher levels should deal with it.
 */

@implementation ICNetPatientSketches

-(id)initWithDelegate:(ICProgressDelegate)aDelegate baseUrl:(NSString*)aBaseUrl timeout:(NSTimeInterval)aTimeout maxConnections:(int)aMaxConnections retries:(int)retries patients:(NSArray*)somePatients completionBlock:(ICNetCompletionBlock)block;
{
    insist (aBaseUrl && somePatients && block);
    insist ([somePatients count]);
    insist ([NSThread isMainThread]);
    insist (retries >= 0);
    
    /*get any patient just for its moc*/
    ICPatient*anyPatient = [somePatients objectAtIndex:0];
    insist (anyPatient);
    
    if ((self = [super initWithDelegate:aDelegate baseUrl:aBaseUrl timeout:aTimeout maxConnections:aMaxConnections managedObjectContext:anyPatient.managedObjectContext completionBlock:block]))
    {
        /*save the array of patients*/
        patients = somePatients;
        maxTries = retries + 1;
    }
    return self;
}

/*start the download by requesting lists of patient sketches for each patient*/
-(BOOL)download
{
    insist (self && [NSThread isMainThread]);
    insist (patients);
    
    if (![super download])
        return NO;
    
    workList = patients;
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
        ICPatient*patient = [workList objectAtIndex:workListIndex];
        __unsafe_unretained ICNetPatientSketches*myself = self;
        
        [self addDataURL:[NSURL URLWithString:[NSString stringWithFormat:PATIENT_SKETCHES_FORMAT, patient.patientId]
                                relativeToURL:baseUrl] body:nil block:^(ICNetOperation*op)
         {
             dispatch_async (dispatch_get_main_queue(), ^{[myself gotSketches:op patient:patient];});
         }];
    }
}

/*used to deal with errors, retry or die*/
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

/*called when we have a list of sketches for a patient.*/
-(void)gotSketches:(ICNetOperation*)op patient:(ICPatient*)patient
{
    insist (self && op);
    insist (patient);
    insist ([NSThread isMainThread]);
    
    /*if there's some kind of underlying network error, retry*/
    if (op.error)
    {
        [self error:op.error operation:op];
        return;
    }
    
    /*if there's a json error, give up*/
    __autoreleasing ICNetError*error;
    NSMutableArray*sketches = [op jsonArrayWithError:&error];
    if (!sketches)
    {
        [self dieWithError:error];
        return;
    }
    
    [self description:@"Got %d sketches for patient %@", [sketches count], patient.fullName];
    
    /*
     request each sketch. we don't care if we might already have them, we will overwrite in that case. there's
     no concept of delete in this api and it's all going to be changed to hashing anyway.
     
     we are careful to not touch core data here, because we are only going to add to core data when we
     have a whole object, that way we can rollback easily for error handling.
     
     we don't care if we go over maxPending here, it's a coarse limit really.
     */
    
    for (NSDictionary*dict in sketches)
    {
        NSString*sid = [self valueforKey:ID_KEY dictionary:dict error:&error];
        if (!sid)
        {
            [self dieWithError:error];
            return;
        }
        
        __unsafe_unretained ICNetPatientSketches*myself = self;
        
        [self addDataURL:[NSURL URLWithString:[NSString stringWithFormat:PATIENT_SKETCH_FORMAT, sid] relativeToURL:baseUrl]
                    body:nil
                   block:^(ICNetOperation*op)
         {
             dispatch_async (dispatch_get_main_queue(), ^{[myself gotSketch:op patient:patient dictionary:dict];});
         }];
    }
    
    /*check to see if we can add more work or if we are done (which cannot happen in this case but who cares)*/
    [self work];
}

-(void)gotSketch:(ICNetOperation*)op patient:(ICPatient*)patient dictionary:(NSDictionary*)dict
{
    insist (self && op);
    insist (patient && dict);
    insist ([NSThread isMainThread]);
    
    /*if there's some kind of underlying network error, retry*/
    if (op.error)
    {
        [self error:op.error operation:op];
        return;
    }
    
    /*now we can make a new ICPatientSketchElement, on any failure give up.*/
    __autoreleasing ICNetError*error;
    ICPatientSketchElement*sketch = [self sketchWithDictionary:dict patient:patient error:&error];
    if (!sketch)
    {
        [self dieWithError:error];
        return;
    }
    
    insist (op.data);
    insist (sketch.content);
    
    [self description:@"Got sketch of %d bytes.", [op.data length]];
    sketch.content.data = op.data;
    [self update:patient set:SKETCHES_ATTR_KEY key:SKETCH_ID_ATTR_KEY mo:sketch];
    insist (sketch.patient == patient);
    
    /*update core data. any error is fatal*/
    if (![self save])
        return;
    
#if 0
    acks are not implemented
    /*send the ack, this code will go away when we move to the hash stuff*/
    __unsafe_unretained ICNetPatientSketches*myself = self;
    
    [self ack:PATIENT_SKETCH_TABLE_NAME identifier:sketch.elementId block:^(ICNetOperation*op)
     {
         dispatch_async (dispatch_get_main_queue(), ^{[myself gotAck:op];});
     }];
#endif
    
    /*check to see if we can add more work or if we are done (which cannot happen in this case but who cares)*/
    [self work];
}

/*left in as an example i guess*/
-(void)gotAck:(ICNetOperation*)op
{
    insist (self && op);
    insist ([NSThread isMainThread]);
    
    [self description:@"pending is %d", [self pending]];
    
    /*check to see if we can add more work or if we are done (which cannot happen in this case but who cares)*/
    [self work];
}


/*
 make a new managed object from json data. if there's any error in the json, clean up and return nil. the content field
 of ICPatientSketchElement is impossible to get at using the objective-c language, but we know its type, so we can
 defeat the compiler and get to it by casting.
 */

-(ICPatientSketchElement*)sketchWithDictionary:(NSDictionary*)dict patient:(ICPatient*)patient error:(ICNetError*__autoreleasing*)error
{
    insist (self && dict && patient && error);
    
    NSString*patientId;
    NSString*extension;
    
    /*make the sketch*/
    ICPatientSketchElement*mo = (ICPatientSketchElement*)[self newManagedObject:kICPatientSketchEntityName error:error];
    if (!mo)
        return nil;
    
    insist (mo.content);
    insist (((ICSecureContent*)mo.content).element);
    
    /*set its attributes and stuff from the json*/
    id v;
    ICNET_SET(v, mo, elementId, ID_KEY, dict, error);
    ICNET_SET(v, mo, name, NAME_KEY, dict, error);
    
    if (!(extension = [self valueforKey:FILE_EXTENSION_KEY dictionary:dict error:error]))
    {
        [mo.managedObjectContext deleteObject:mo];
        return nil;
    }
    
    /*by. any. means. necessary. (the core data here is so ill designed you have to exert effort to use it).*/
    ((ICSecureContent*)mo.content).extension = extension;
    
    /*the other fields we are ignoring. just check for consistency*/
    if (![self valueforKey:FILENAME_KEY dictionary:dict error:error] ||
        !((patientId = [self valueforKey:PATIENT_ID_KEY dictionary:dict error:error])))
    {
        [mo.managedObjectContext deleteObject:mo];
        return nil;
    }
    
    
    /*make sure the patientId we got from the server makes sense*/
    if (![patientId isEqualToString:patient.patientId])
    {
        [mo.managedObjectContext deleteObject:mo];
        *error = [ICNetError errorWithCode:ICNetErrorJson description:[NSString stringWithFormat:@"In patient sketch %@ got patientId %@ expected %@",
                                                                       mo.elementId, patientId, patient.patientId]];
        return nil;
    }
    
    return mo;
}

@end
