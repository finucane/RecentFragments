//
//  ICNetFileOperation.h
//  iConsult Enterprise
//
//  Created by finucane on 2/14/13.
//  Donated to the public domain.
//
//

#import "ICNetOperation.h"

@interface ICNetFileOperation : ICNetOperation
{
    @private
    NSFileHandle*fileHandle;
    NSString*path;
}
-(id)initWithRequest:(NSURLRequest*)request net:(ICNet*)aNet path:(NSString*)aPath completionBlock:(ICNetOperationCompletionBlock)block;
-(BOOL)appendData:(NSData*)data;
-(BOOL)resetData;
-(ICNetOperation*)retryWithNet:(ICNet*)aNet;

@end
