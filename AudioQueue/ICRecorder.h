//
//  ICRecorder.h
//  iConsult Enterprise
//
//  Created by finucane on 2/25/13.
//  Donated to the public domain.
//
//

#include <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#define ICRECORDER_NUM_BUFFERS 3
typedef void (^ICRecorderBlock)(NSData*data);

@interface ICRecorder : NSObject
{
    @private
    NSMutableData*data;
    AudioStreamBasicDescription format;
    AudioQueueRef audioQueue;
    AudioQueueBufferRef buffers [ICRECORDER_NUM_BUFFERS];
    AudioFileID fileId;
    SInt64 packetsWritten;
    size_t bufferSize;
    BOOL isRunning;
    ICRecorderBlock block;
    OSStatus status;
    NSError*error;
}

-(id)initWithBlock:(ICRecorderBlock)block;
-(BOOL)start;
-(BOOL)stop;
-(NSError*)error;
-(void)badCall:(char*)e;

@end
