//
//  ICNetDataOperation.h
//  iConsult Enterprise
//
//  Created by finucane on 2/14/13.
//
//

#import "ICNetOperation.h"

@interface ICNetDataOperation : ICNetOperation
{
    @private
    NSMutableData*data;
}

-(ICNetOperation*)retryWithNet:(ICNet*)aNet;
-(BOOL)appendData:(NSData*)data;
-(BOOL)resetData;
-(NSData*)data;

@end
