//


#import "AudioDecodeController.h"
#import "Frames.h"


void audioQueueDecodeCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer);
void audioDecodeIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID);

void audioQueueDecodeCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer) {

    AudioDecodeController *audioController = (__bridge AudioDecodeController*)inClientData;
    [audioController audioQueueDecodeCallback:inAQ inBuffer:inBuffer];
}

void audioDecodeIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID) {

    AudioDecodeController *audioController = (__bridge AudioDecodeController*)inClientData;
    [audioController audioDecodeIsRunningCallback];
}
frames *_streamer;
AVCodecContext *_audioCodecContext;
@interface AudioDecodeController ()

@end

@implementation AudioDecodeController

- (id)initWithStreamer:(frames*)streamer {
    if (self = [super init]) {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        _streamer = streamer;
        _audioCodecContext = _streamer._audioCodecContext;
    }
    return  self;
}

- (void)dealloc {
    [super dealloc];
    [self removeAudioQueue];
}


- (IBAction)playAudio:(UIButton*)sender {
    [self _startAudio];
}

- (IBAction)pauseAudio:(UIButton*)sender {
    if (started_) {
      state_ = AUDIO_STATE_PAUSE;

      AudioQueuePause(audioQueue_);
      AudioQueueReset(audioQueue_);
    }
}



- (void)_startAudio {
    NSLog(@"ready to start audio");
    if (started_) {
      AudioQueueStart(audioQueue_, NULL);
    }
    else {
     
        [self createAudioQueue] ;
    
      [self startQueue];

     
    }

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      [self enqueueBuffer:audioQueueBuffer_[i]];
    }

    state_ = AUDIO_STATE_PLAYING;
}

- (void)_stopAudio{
    if (started_) {
      AudioQueueStop(audioQueue_, YES);
    startedTime_ = 0.0;
      state_ = AUDIO_STATE_STOP;
      finished_ = NO;
    }
}

- (BOOL)createAudioQueue {
    state_ = AUDIO_STATE_READY;
    finished_ = NO;

    decodeLock_ = [[NSLock alloc] init];
    
    // 16bit PCM LE.
    audioStreamBasicDesc_.mFormatID = kAudioFormatLinearPCM;
    audioStreamBasicDesc_.mSampleRate = _audioCodecContext->sample_rate;
    audioStreamBasicDesc_.mBitsPerChannel = 16;
    audioStreamBasicDesc_.mChannelsPerFrame = _audioCodecContext->channels;
    audioStreamBasicDesc_.mFramesPerPacket = 1;
    audioStreamBasicDesc_.mBytesPerFrame = audioStreamBasicDesc_.mBitsPerChannel / 8 
    * audioStreamBasicDesc_.mChannelsPerFrame;
    audioStreamBasicDesc_.mBytesPerPacket = 
    audioStreamBasicDesc_.mBytesPerFrame * audioStreamBasicDesc_.mFramesPerPacket;
    audioStreamBasicDesc_.mReserved = 0;
    audioStreamBasicDesc_.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    



    OSStatus status = AudioQueueNewOutput(&audioStreamBasicDesc_, audioQueueDecodeCallback, (__bridge void*)self,
      NULL, NULL, 0, &audioQueue_);
    if (status != noErr) {
      NSLog(@"Could not create new output.");
      return NO;
    }

    status = AudioQueueAddPropertyListener(audioQueue_, kAudioQueueProperty_IsRunning, 
      audioDecodeIsRunningCallback, (__bridge void*)self);
    if (status != noErr) {
      NSLog(@"Could not add propery listener. (kAudioQueueProperty_IsRunning)");
      return NO;
    }


//    [ffmpegDecoder_ seekTime:10.0];

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      status = AudioQueueAllocateBufferWithPacketDescriptions(audioQueue_, 
        _audioCodecContext->bit_rate * kAudioBufferSeconds / 8, 
        _audioCodecContext->sample_rate * kAudioBufferSeconds / 
          _audioCodecContext->frame_size + 1, 
        &audioQueueBuffer_[i]);
      if (status != noErr) {
        NSLog(@"Could not allocate buffer.");
        return NO;
      }
    }
    
    return YES;
}

- (void)removeAudioQueue {
    [self _stopAudio];
    started_ = NO;

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      AudioQueueFreeBuffer(audioQueue_, audioQueueBuffer_[i]);
    }
    AudioQueueDispose(audioQueue_, YES);
}


- (void)audioQueueDecodeCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer {
    if (state_ == AUDIO_STATE_PLAYING) {
        NSLog(@"called the queue");
      [self enqueueBuffer:inBuffer];
    }
}

- (void)audioDecodeIsRunningCallback {
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    OSStatus status = AudioQueueGetProperty(audioQueue_, kAudioQueueProperty_IsRunning, &isRunning, &size);

    if (status == noErr && !isRunning && state_ == AUDIO_STATE_PLAYING) {
      state_ = AUDIO_STATE_STOP;

      if (finished_) {
            }
    }
}


   

- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer {
	AudioTimeStamp bufferStartTime;
    OSStatus status = noErr;
	buffer->mAudioDataByteSize = 0;
	buffer->mPacketDescriptionCount = 0;
    NSInteger decodedDataSize = 0;
    
	if (_streamer.audioPacketQueue.count <= 0) {
        NSLog(@"called back but queue is empty");
        _streamer.emptyAudioBuffer = buffer;
		return;
	}
    NSLog(@"now have something in queue");
	//NSLog(@" audio packets in queue  %d ",audioPacketQueue.count);
	_streamer.emptyAudioBuffer = nil;
	
	while (_streamer.audioPacketQueue.count && buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity) {
		decodedDataSize = [_streamer decode];
		//NSLog(@"packet size for fill %d ",packet->size);
        
		if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= decodedDataSize) {
			
			
			memcpy(buffer->mAudioData + buffer->mAudioDataByteSize, _streamer._audioBuffer, decodedDataSize);
			buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
			buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = decodedDataSize;
			buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = _audioCodecContext->frame_size;
			
			buffer->mAudioDataByteSize += decodedDataSize;
			buffer->mPacketDescriptionCount++;
            [_streamer nextPacket];
        }
		else {
			break;
		}
	}
    [decodeLock_ lock];
    if (buffer->mPacketDescriptionCount > 0) {
        status = AudioQueueEnqueueBuffer(audioQueue_, buffer, 0, NULL);
        if (status != noErr) { 
            NSLog(@"Could not enqueue buffer.");
        }
    }
    else {
        AudioQueueStop(audioQueue_, NO);
        finished_ = YES;
    }
    
    [decodeLock_ unlock];
    
    return status;
	
}


- (OSStatus)startQueue {
    OSStatus status = noErr;

    if (!started_) {
      status = AudioQueueStart(audioQueue_, NULL);
      if (status == noErr) {
        started_ = YES;
      }
      else {
        NSLog(@"Could not start audio queue.");
      }
    }

    return status;
}

@end
