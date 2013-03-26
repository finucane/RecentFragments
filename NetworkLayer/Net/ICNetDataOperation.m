//
//  ICNetDataOperation.m
//  iConsult Enterprise
//
//  Created by finucane on 2/14/13.
//
//

#import "insist.h"
#import "ICNetDataOperation.h"

@implementation ICNetDataOperation

/*NSOperations cannot be re-used, so we make a new operation based on our own details. net has to be set afresh*/
-(ICNetOperation*)retryWithNet:(ICNet*)aNet
{
    insist (aNet && block);
    
    ICNetDataOperation*op = [[ICNetDataOperation alloc] initWithRequest:request net:aNet completionBlock:block];
    insist (op);
    op->numTries = numTries + 1;
    return op;
}
-(BOOL)appendData:(NSData*)someData
{ 
    insist (self && data && someData);
    [data appendData:someData];
    return YES;
}
-(BOOL)resetData
{
    insist (self);
    
    if (!data)
        data = [[NSMutableData alloc] init];
    insist (data);
    [data setLength:0];
    return YES;
}
-(NSData*)data
{
    return data;
}

@end
