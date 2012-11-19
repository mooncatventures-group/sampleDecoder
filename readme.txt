this is just a sample of audio queue  used with ffmpeg audio decoding

it is for education only and is not in anyway complete.

You will also need the following code in the streamer class (your equivalent of frames)


- (NSInteger)decode {
    if (_inBuffer) return _decodedDataSize;
    
    _decodedDataSize = 0;
    AVPacket *packet = [self readPacket];
    NSLog(@"read packet");
    while (packet && packet->size > 0) {
        NSLog(@"decoding packet");
        if (_audioBufferSize < FFMAX(packet->size * sizeof(*_audioBuffer), AVCODEC_MAX_AUDIO_FRAME_SIZE)) {
            _audioBufferSize = FFMAX(packet->size * sizeof(*_audioBuffer), AVCODEC_MAX_AUDIO_FRAME_SIZE);
            av_free(_audioBuffer);
            _audioBuffer = av_malloc(_audioBufferSize);
        }
        _decodedDataSize = _audioBufferSize;
        NSInteger len = avcodec_decode_audio3(_audioCodecContext, _audioBuffer, &_decodedDataSize, packet);
        NSLog(@"packet size %d ",packet->size);
        if (len < 0) {
            NSLog(@"Could not decode audio packet.");
            
            return 0;
        }
        
        packet->data += len;
        packet->size -= len;
        
        if (_decodedDataSize <= 0) {
            NSLog(@"Decoding was completed.");
            packet = NULL;
            break;
        }
        
        _inBuffer = YES;
    }
    

        NSLog(@"added decoded packet...decoded %d ",_decodedDataSize);
    return _decodedDataSize;
}

- (void)nextPacket {
    _inBuffer = NO;
}

- (AVPacket*)readPacket {
    
    if (_currentPacket.size > 0 || _inBuffer) return &_currentPacket;
    
    NSMutableData *packetData = [audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];

           NSLog(@"got audio stream");
        if (_packet->dts != AV_NOPTS_VALUE) {
            _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        if (_packet->pts != AV_NOPTS_VALUE) {
            _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        NSLog(@"ready with audio");
       
    
    [audioPacketQueueLock lock];
    audioPacketQueueSize -= _packet->size;
    [audioPacketQueue removeObjectAtIndex:0];
    [audioPacketQueueLock unlock];
    
    

    _currentPacket = *(_packet);
    
    return &_currentPacket;   
}


