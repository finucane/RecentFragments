//
//  ICProgress.m
//  iConsult Enterprise
//
//  Created by finucane on 3/6/13.
//
//

#import "ICProgress.h"
#import "insist.h"

@implementation ICProgress

-(id)initWithDelegate:(ICProgressDelegate)aDelegate
{
    insist (aDelegate);
    
    if ((self = [super init]))
    {
        delegate = aDelegate;
    }
    return self;
}

-(ICProgressDelegate)delegate
{
    return delegate;
}

-(void)phase:(NSString*)format,...
{
    va_list args;
    va_start(args, format);
    NSString*s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [delegate progress:self phase:s];
}

-(void)description:(NSString*)format,...
{
    va_list args;
    va_start(args, format);
    NSString*s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [delegate progress:self description:s];
}

-(void)pending:(int)pending
{
    [delegate progress:self pending:pending];
}

-(void)done:(NSError*)error
{
    [delegate progress:self done:error];
}

@end
