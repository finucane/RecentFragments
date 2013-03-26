//
//  ICProgress.h
//  iConsult Enterprise
//
//  Created by finucane on 3/6/13.
//
//

#import <Foundation/Foundation.h>

@class ICProgress;

@protocol ICProgressDelegate <NSObject>
-(void)progress:(ICProgress*)progress phase:(NSString*)phase;
-(void)progress:(ICProgress*)progress description:(NSString*)description;
-(void)progress:(ICProgress*)progress pending:(int)pending;
-(void)progress:(ICProgress*)progress done:(NSError*)error;
@end

typedef id <ICProgressDelegate> ICProgressDelegate;

@interface ICProgress : NSObject
{
    @private
    __weak ICProgressDelegate delegate;
}

-(id)initWithDelegate:(ICProgressDelegate)delegate;
-(ICProgressDelegate)delegate;

/*wrappers to make it easy for subclasses to report progress*/
-(void)phase:(NSString*)format,...;
-(void)description:(NSString*)format,...;
-(void)pending:(int)pending;
-(void)done:(NSError*)error;

@end
