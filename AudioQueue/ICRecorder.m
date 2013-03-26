//
//  ICRecorder.m
//  iConsult Enterprise
//
//  Created by finucane on 2/25/13.
//
//


/*
 the way this thing works is you make it, then do start/stop on it. every time you do a stop you get data for
 the audio that was recorded since the last stop.
 */

#include <AudioToolbox/AudioToolbox.h>
#import "insist.h"
#import "ICRecorder.h"

#define NUM_SECONDS_PER_BUFFER 0.5
#define ICRECORDER_FILE @"icRecorder.m4a"

/*error handling*/

#define AQ_CALL(e)if((status = e)){[self badCall:#e];return 0;}


@implementation ICRecorder

static void callback (void*context, AudioQueueRef aq, AudioQueueBufferRef buffer,
                      const AudioTimeStamp *startTime, UInt32 numPackets,
                      const AudioStreamPacketDescription*descriptions);

/*
 C callbacks for AudioFileInitializeWithCallbacks. these are just shims around what would have been file system reads/writes so don't
 bother making them wrappers around ICRecorder methods. This code assumes infinite RAM, no effort is made to limit the size of the
 sound file in RAM.
 */
static OSStatus readProc (void*inClientData,
                          SInt64 inPosition,
                          UInt32 requestCount,
                          void*buffer,
                          UInt32*actualCount
                          )
{
    
    insist (inClientData && buffer && actualCount);
    
    ICRecorder*recorder = (__bridge ICRecorder*)inClientData;
    
    insist (recorder->data);
    
    *actualCount = requestCount;
    SInt64 over = inPosition + requestCount - [recorder->data length];
    if (over > 0)
    {
        if (inPosition >= [recorder->data length])
            *actualCount = 0;
        else
            *actualCount = [recorder->data length] - inPosition; //obfuscated by algebra
    }
    
    insist (inPosition + *actualCount <= [recorder->data length]);
    memcpy (buffer, [recorder->data bytes] + inPosition, *actualCount);
    return 0;
}

static SInt64 getSizeProc (void*inClientData)
{
    insist (inClientData);
    ICRecorder*recorder = (__bridge ICRecorder*)inClientData;
    return [recorder->data length];
}

static OSStatus setSizeProc (void*inClientData,
                             SInt64 size)
{
    insist (inClientData);
    ICRecorder*recorder = (__bridge ICRecorder*)inClientData;
    [recorder->data setLength:size];
    return 0;
}

static OSStatus writeProc (void*inClientData,
                           SInt64 inPosition,
                           UInt32 requestCount,
                           const void*buffer,
                           UInt32*actualCount)
{
    insist (inClientData && buffer && actualCount);
    
    ICRecorder*recorder = (__bridge ICRecorder*)inClientData;
    
    *actualCount = requestCount;
    SInt64 end = inPosition + requestCount;
    if (end > [recorder->data length])
        [recorder->data setLength:end];
    
    [recorder->data replaceBytesInRange:NSMakeRange(inPosition, requestCount) withBytes:buffer];
    
    //NSLog (@"data length is %d", [recorder->data length]);
    return 0;
}

-(void)dealloc
{
    /*free audio queue resources*/
    if (audioQueue)
        AudioQueueDispose (audioQueue, YES);
}

-(id)initWithBlock:(ICRecorderBlock)aBlock
{
    insist (aBlock);
    if ((self = [super init]))
    {
        /*save the completion block and null out our opaque C pointer for dealloc*/
        block = aBlock;
        
        /*we'll make this on start when the UI can deal w/ failure easily*/
        audioQueue = 0;
        
        status = 0;
    }
    
    return self;
}

/*seconds is a float to allow buffer sizes for less than a second. this size doesn't have to be accurate*/
-(unsigned)bufferSizeForSeconds:(double)seconds
{
    insist (self && seconds);
    
    /*if we have a bytes per frame, we are done*/
    unsigned numFrames = seconds * format.mSampleRate;
    if (format.mBytesPerFrame > 0)
        return numFrames * format.mBytesPerFrame;
    
    unsigned maxPacketSize;
    if (format.mBytesPerPacket > 0)
        maxPacketSize = format.mBytesPerPacket;
    else
    {
        /*if we can't get this thing, we can't do anything. end of story. (should never happen).*/
        UInt32 propertySize = sizeof (maxPacketSize);
        
        AQ_CALL(AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &propertySize));
    }
    
    unsigned numPackets = format.mFramesPerPacket > 0 ? numFrames / format.mFramesPerPacket : numFrames;
    if (numPackets == 0)
        numPackets = 1;
    
    return numPackets * maxPacketSize;
}

/*reset the audio queue. return NO on error. rely on dealloc to clean up any resources.*/

-(BOOL)magicCookie
{
    /*get the magic cookie, if any*/
    UInt32 cookieSize, dc;
    if (!AudioQueueGetPropertySize (audioQueue, kAudioQueueProperty_MagicCookie, &cookieSize) && cookieSize > 0)
    {
        char*cookie = malloc (cookieSize);
        insist (cookie);
        
        AQ_CALL (AudioQueueGetProperty (audioQueue, kAudioQueueProperty_MagicCookie, cookie, &dc));
        
        /*if we have no data yet, write the cookie to the start*/
        if ([data length] == 0)
            [data appendBytes:cookie length:cookieSize];
        
        /*and also to the file*/
        UInt32 wantsCookie = NO;
        if (!AudioFileGetPropertyInfo(fileId, kAudioFilePropertyMagicCookieData, 0, &wantsCookie) && wantsCookie)
        {
            AQ_CALL (AudioFileSetProperty (fileId, kAudioFilePropertyMagicCookieData, cookieSize, cookie));
        }
        free (cookie);
    }
    return YES;
}

-(BOOL)reset
{
    /*free any old resources*/
    if (audioQueue)
    {
        OSStatus r = AudioQueueDispose (audioQueue, YES);
        insist (r == 0);
        audioQueue = 0;
    }
    
    /*get data to write our recording to*/
    data = [[NSMutableData alloc] init];
    insist (data);
    
    /*set up the audio session. let this fail*/
    AudioSessionInitialize (0, 0, 0, 0);
    
    UInt32 category = kAudioSessionCategory_PlayAndRecord;
	AQ_CALL (AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category));
    
    AQ_CALL (AudioSessionSetActive(true));
    
    /*set up the AudioStreamBasicDescription*/
    memset (&format, 0, sizeof (format));
    
    UInt32 dc = sizeof (format.mSampleRate);
    AQ_CALL (AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &dc, &format.mSampleRate));
    
    dc = sizeof (format.mChannelsPerFrame);
    AQ_CALL (AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareInputNumberChannels, &dc, &format.mChannelsPerFrame));
    
    format.mFormatID = kAudioFormatMPEG4AAC;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 0;
    format.mFramesPerPacket = 1024;
    format.mBytesPerFrame = 0;
    format.mBytesPerPacket = 0;
    
    /*create the audioqueue*/
    AQ_CALL (AudioQueueNewInput(&format, callback, (__bridge void *)self, 0, 0, 0, &audioQueue));
    
    insist (audioQueue);
    
    /*get possibly more format info from the audio queue now that it's created*/
    
    dc = sizeof (format);
    AQ_CALL (AudioQueueGetProperty (audioQueue, kAudioQueueProperty_StreamDescription, &format, &dc));
    
    /*calculate buffer size after we make the queue*/
    unsigned size = [self bufferSizeForSeconds:NUM_SECONDS_PER_BUFFER];
    
    if (size == 0)
        return NO;
    
    /*before we can write to a callback stream, we need a file to "initialize" from. nothing will get written to it.*/
    NSURL*url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:ICRECORDER_FILE]];
    
    /*create the audio file*/
    AQ_CALL (AudioFileCreateWithURL((__bridge CFURLRef) url, kAudioFileM4AType, &format, kAudioFileFlags_EraseFile, &fileId));
    [self magicCookie];
    
    /*re-initialize it to do reads/writes through callbacks instead of the file system*/
    AQ_CALL (AudioFileInitializeWithCallbacks ((__bridge void *)self, readProc, writeProc, getSizeProc, setSizeProc, kAudioFileM4AType, &format, 0, &fileId));
    
    /*now the buffers, on any failure back out and return false*/
    for (int i = 0; i < ICRECORDER_NUM_BUFFERS; i++)
    {
        AQ_CALL (AudioQueueAllocateBuffer (audioQueue, size, &buffers [i]));
        
        /*can't use AQ_CALL here since we have to do some cleanup*/
        if ((status = AudioQueueEnqueueBuffer (audioQueue, buffers [i], 0, 0)))
        {
            AudioQueueFreeBuffer (audioQueue, buffers [i]);
            [self badCall:"AudioQueueEnqueueBuffer"];
            return NO;
        }
    }
    
    packetsWritten = 0;
    isRunning = NO;
    return YES;
}

-(BOOL)start
{
    insist (self);
    
    if (isRunning) 
        return YES;
    
    /*set up everything we need to record*/
    if (![self reset])
        return NO;
    
    /*this is used for asychnronously stopping the recording, it will be set by stop and looked
     at by the callback routine as the last packet arrives*/
    
    AQ_CALL (AudioQueueStart (audioQueue, 0));
    
    isRunning = YES;
    return YES;
}

-(BOOL)stop
{
    insist (self);
    
    if (!isRunning)
        return YES;
    
    /*stop but not immediately*/
    AQ_CALL (AudioQueueStop (audioQueue, NO));
    
    isRunning = NO;
    return YES;
}

-(BOOL)callback:(AudioQueueBufferRef)buffer numPackets:(UInt32)numPackets packetDescriptions:(const AudioStreamPacketDescription*)descriptions
{
    insist (self && buffer);
    insist (data);
    
    /*write to the file*/
    if (numPackets)
    {
        /*this thing will fail if we are writing and already stopped. so just ignore error handling here*/
        AudioFileWritePackets(fileId, NO, buffer->mAudioDataByteSize, descriptions, packetsWritten, &numPackets, buffer->mAudioData);
        packetsWritten += numPackets;
    }
    
    /*if we were stopped, call the completion block and dispose of the queue. that's important because we don't want the completion block
     to be called after this*/
    if (!isRunning)
    {
        /*write data to the file*/
        
        /*the header might contain length information*/
        [self magicCookie];
        AudioFileClose(fileId);
        
#if 0
        //for debugging
        NSString*path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"data.m4a"];
        NSLog (@"path is %@", path);
        [data writeToFile:path atomically:NO];
#endif
        /*call the completion block and then dispose of the queue*/
        block (data);
        AudioQueueDispose (audioQueue, YES);
        audioQueue = 0;
    }
    
    /*otherwise enqueue the buffer again. we can't really handle this error here.*/
    AQ_CALL (AudioQueueEnqueueBuffer (audioQueue, buffer, 0, 0));
    return YES;
}

/*code ripped off from apple to print out a 4-char code, which is useful a lot of times, or just a number*/
-(NSString*)statusToString
{
	char mStr[16];
    char *str = mStr;
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(status);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else if (status > -200000 && status < 200000)
        // no, format it as an integer
        sprintf(str, "%d", (int)status);
    else
        sprintf(str, "0x%x", (int)status);
    return [NSString stringWithCString:str encoding:NSASCIIStringEncoding];
}

/*generate an error that has the 4-char code and the function call that failed*/
-(void)badCall:(char*)e
{
    insist (self && e);
    error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:
             @{@"error": [self statusToString],
             @"function": [NSString stringWithCString:e encoding:NSUTF8StringEncoding]}];
}

-(NSError*)error
{
    return error;
}

/*wrapper function in C for the audioqueue callback*/
static void callback (void*context, AudioQueueRef aq, AudioQueueBufferRef buffer,
                      const AudioTimeStamp *startTime, UInt32 numPackets,
                      const AudioStreamPacketDescription*descriptions)
{
    ICRecorder*recorder = (__bridge ICRecorder*)context;
    
    insist (recorder);
    insist (aq == recorder->audioQueue);
    
    @autoreleasepool
    {
        [recorder callback:buffer numPackets:numPackets packetDescriptions:descriptions];
    }
}


@end
