//
//  H264Encoder.m
//  
//
//  Created by jimmygao on 12/31/15.
//
//

#import "H264Encoder.h"

@implementation H264Encoder
{
    VTCompressionSessionRef _session;
    dispatch_queue_t _queue;
}

static H264Encoder* _instance = NULL;
static void didCompressFinished(void *outputCallbackRefCon,void *sourceFrameRefCon,OSStatus status,VTEncodeInfoFlags infoFlags,CMSampleBufferRef sampleBuffer )
{
    
    if(status != noErr){
        NSError *error = [NSError errorWithDomain: NSOSStatusErrorDomain code:status userInfo:nil];
        return;
    }
    
    if(!CMSampleBufferDataIsReady(sampleBuffer)){
        return;
    }
    
    UInt64 pts = (UInt64)(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000);

    size_t sparameterSetSize = 0;
    size_t pparameterSetSize = 0;
    const uint8_t *sparameterSet;
    const uint8_t *pparameterSet;
    static const uint8_t nalHeader[] = {0x00,0x00,0x00,0x01};
    uint8_t * sampleData = NULL;
    uint32_t sampleSize = 0;
    
    H264Encoder *encoder = (__bridge H264Encoder*)outputCallbackRefCon;
    
    BOOL keyframe = !CFDictionaryContainsKey((CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false),0), kCMSampleAttachmentKey_NotSync);
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t sparameterSetCount = 0;
        
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            
            size_t pparameterSetCount = 0;
            
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                sampleSize += sparameterSetSize + pparameterSetSize + 8;
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length = 0;
    size_t totalLength = 0;
    char *dataPointer = NULL;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            memcpy(dataPointer + bufferOffset, nalHeader, AVCCHeaderLength);
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
        sampleSize += totalLength;
    }
    
    if(sampleData != NULL)
    {
        free(sampleData);
        sampleData = NULL;
    }
    
    sampleData = (uint8_t*)malloc(sampleSize);
    if(keyframe){
        memcpy(sampleData, nalHeader, 4);
        memcpy(sampleData + 4, sparameterSet, sparameterSetSize);
        memcpy(sampleData + 4 + sparameterSetSize, nalHeader, 4);
        memcpy(sampleData + 8 + sparameterSetSize, pparameterSet, pparameterSetSize);
        memcpy(sampleData + 8 + sparameterSetSize + pparameterSetSize , dataPointer, totalLength);
    }else{
        memcpy(sampleData, dataPointer, totalLength);
    }
    
    SampleData sample;
    sample.width = encoder.width;
    sample.height = encoder.height;
    sample.type = Sample_Type_Video;
    sample.flags = keyframe ? 1 : 0;
    sample.timestamp = pts;
    sample.data_size = sampleSize;
    sample.data = (uint8_t*)sampleData;
    
    if(sampleData != NULL)
    {
        free(sampleData);
        sampleData = NULL;
    }
}

+(instancetype)getInstance{
    
    @synchronized(_instance){
        if(_instance == NULL){
            _instance = [[H264Encoder alloc]init];
        }
    }
    return _instance;
    
}
+(void)startEncoder{
    [[self getInstance] setUpEncoder];
}

+(void)stopEncoder{
    [[self getInstance] tearDownEncoder];
}

+(void)restartEncoderWith:(int)width andHeight:(int)height andFPS:(int)fps{
    [[self getInstance] resetEncoderWith:width andHeight:height andFPS:fps];
}

-(instancetype)init{
    self = [super init];
    if(self){
        _width = 1920;
        _height = 1080;
        _fps = 30;
        _bitrate = 5*1000*1000;
        
        _queue = dispatch_queue_create("com.test.h264encoder", DISPATCH_QUEUE_SERIAL);
        _session = nil;
        _state = H264ENCODE_STATE_INIT;
        _error = H264ENCODE_ERROR_NOERR;

    }
    return self;
}


-(void)resetEncoderWith:(int)width andHeight:(int)height andFPS:(int)fps{
    if((width != _width) || (height != _height) || fps != _fps ){
        _width = width;
        _height = height;
        _fps = fps;
        [self resetEncoder];
    }
}

-(void)resetEncoder{
    NSLog(@"%s",__FUNCTION__);
    [self tearDownEncoder];
    [self setUpEncoder];
}

-(void)setUpEncoder{

    dispatch_sync(_queue, ^{
        OSStatus status = noErr;
        if(_state == H264ENCODE_STATE_INIT){
            
            CFArrayRef ref;
            VTCopyVideoEncoderList(NULL, &ref);
            NSLog(@"encoder list = %@",(__bridge NSArray*)ref);
            CFRelease(ref);
            
            CFMutableDictionaryRef encodeSpecific = NULL;
            
            CFStringRef key = kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder;
            CFBooleanRef value = kCFBooleanTrue;
            CFStringRef key1 = kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder;
            CFBooleanRef value1 = kCFBooleanTrue;
            CFStringRef key2 = kVTVideoEncoderSpecification_EncoderID;
            CFStringRef value2 = CFSTR("com.apple.videotoolbox.videoencoder.h264.gva");
            
            encodeSpecific = CFDictionaryCreateMutable(NULL, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictionaryAddValue(encodeSpecific, key, value);
            CFDictionaryAddValue(encodeSpecific, key1, value1);
            CFDictionaryAddValue(encodeSpecific, key2, value2);
            
            SInt32 cvPixelFormatTypeValue = k2vuyPixelFormat;
            CFDictionaryRef emptyDict = CFDictionaryCreate(kCFAllocatorDefault, nil, nil, 0, nil, nil);
            CFNumberRef cvPixelFormatType = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, (const void*)(&(cvPixelFormatTypeValue)));
            CFNumberRef frameW = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, (const void*)(&(_width)));
            CFNumberRef frameH = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, (const void*)(&(_height)));
            
            const void *pixelBufferOptionsDictKeys[] = { kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey,  kCVPixelBufferHeightKey, kCVPixelBufferIOSurfacePropertiesKey};
            const void *pixelBufferOptionsDictValues[] = { cvPixelFormatType,  frameW, frameH, emptyDict};
            CFDictionaryRef pixelBufferOptions = CFDictionaryCreate(kCFAllocatorDefault, pixelBufferOptionsDictKeys, pixelBufferOptionsDictValues, 4, nil, nil);
            
            status = VTCompressionSessionCreate(NULL, self.width, self.height, kCMVideoCodecType_H264, encodeSpecific, pixelBufferOptions, NULL, didCompressFinished, (__bridge void *)(self), &_session);

            if(status != noErr){
                _error = H264ENCODE_ERROR_Create;
            }
            CFRelease(pixelBufferOptions);

            log4cplus_info("h264", "create session: resolution:(%d,%d)  fps:(%d)",self.width,self.height,self.fps);
            if(_session){
                
                CFBooleanRef b = NULL;
                VTSessionCopyProperty(_session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &b);
                if (b== kCFBooleanTrue) {
                    log4cplus_info("h264", "Check result: Using hardware encoder now!");
                }else{
                    log4cplus_fatal("h264", "Check result: Not using hardware encoder now!");
                    NSAssert(b == kCFBooleanTrue, @"Not using hardware encoder now");
                }
                
                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_RealTime,kCFBooleanTrue);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_RealTime;
                }

                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_ProfileLevel;
                }
                
                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CAVLC);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_H264EntropyMode;
                }
                
                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_AllowFrameReordering;
                }
                

                int temp = self.fps;
                
                CFNumberRef refFPS = CFNumberCreate(NULL, kCFNumberSInt32Type, &temp);
                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_ExpectedFrameRate, refFPS);
                CFRelease(refFPS);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_ExpectedFrameRate;
                }
                
                temp = self.bitrate;
                CFNumberRef refBitrate = CFNumberCreate(NULL, kCFNumberSInt32Type, &temp);
                VTSessionSetProperty(_session, kVTCompressionPropertyKey_AverageBitRate, refBitrate);
                CFRelease(refBitrate);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_AverageBitRate;
                }
            
                temp = 1;
                CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &temp);
                VTSessionSetProperty(_session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, ref);
                CFRelease(ref);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_MaxKeyFrameIntervalDuration;
                }
                
                temp = 3;
                CFNumberRef refFrameDelay = CFNumberCreate(NULL, kCFNumberSInt32Type, &temp);
                status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_MaxFrameDelayCount, refFrameDelay);
                CFRelease(refFrameDelay);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_MaxFrameDelayCount;
                }
                
                status = VTCompressionSessionPrepareToEncodeFrames(_session);
                if(status != noErr){
                    _error = H264ENCODE_ERROR_PrepareEncode;
                }
            }
        }

        if(_error == H264ENCODE_ERROR_NOERR){
            _state = H264ENCODE_STATE_SET;
            NSLog(@"h264encoder setup success");
        }else{
            NSLog(@"h264encoder setup fauilured : %d",_error);
            sleep(1);
            [self resetEncoder];
        }
    });
}

-(void)doSetBitrate{

    static int count = 0;
    count++;
    if(count == 10){
        count = 0;
    }else{
        return;
    }
    
    _bitrate = g_bitrate << 10;

    int tmp = self.bitrate;
    CFNumberRef bitrate = CFNumberCreate(NULL,kCFNumberSInt32Type , &tmp);
    OSStatus status = VTSessionSetProperty(_session, kVTCompressionPropertyKey_AverageBitRate, bitrate);
    if(status != noErr)
    {
        _error = H264ENCODE_ERROR_AverageBitRate;
        NSError *error = [NSError errorWithDomain: NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"h264encoder set bitrate fauilured:%s",error.description.UTF8String);
    }
    CFRelease(bitrate);
    
    tmp = 0;
    CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &tmp);
    VTSessionCopyProperty(_session, kVTCompressionPropertyKey_AverageBitRate, NULL, &ref);
    CFNumberGetValue(ref, kCFNumberSInt32Type, &tmp);
    NSLog(@"current bitrate from encoder = %d",tmp);
    CFRelease(ref);
    
}

-(void)tearDownEncoder{

    dispatch_sync(_queue, ^{
        if(_session){
            VTCompressionSessionCompleteFrames(_session, kCMTimeInvalid);
            VTCompressionSessionInvalidate(_session);
            CFRelease(_session);
            _session = NULL;
            _state = H264ENCODE_STATE_INIT;
            NSLog(@"%s",__FUNCTION__);
        }
    });
}

-(BOOL)isSessionSupportedProperty:(CFStringRef)propertyKey
{
    BOOL isSupport = NO;
    CFDictionaryRef supportedPropertyDictionary = NULL;
    OSStatus status = VTSessionCopySupportedPropertyDictionary(_session, &supportedPropertyDictionary);
    NSLog(@"h264 supported properties = %@",(__bridge NSDictionary*)supportedPropertyDictionary);
    if(status != noErr)
    {
        isSupport = CFDictionaryContainsKey(supportedPropertyDictionary, propertyKey);
    }
    CFRelease(supportedPropertyDictionary);
    if(!isSupport){
        NSString *error = (__bridge NSString*)propertyKey;
        NSLog(@"set property %s not supported",error.UTF8String);
    }
    return isSupport;
}

@end


@implementation H264Encoder (__USB__)

-(void)pushSample:(CMSampleBufferRef)sampleBuffer{
    
    if(self.state == H264ENCODE_STATE_SET){
        [self doSetBitrate];
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        uint64_t timestamp = CTimeThread::GetInstance()->GetCurrentTime() - g_mediastarttime;
        OSStatus status = VTCompressionSessionEncodeFrame(_session, imageBuffer, CMTimeMake(timestamp, 1000), kCMTimeInvalid, NULL, NULL, NULL);
        if(status != noErr){
            NSLog(@"usb encode frame error, reset encoder...");
            [self resetEncoder];
        }
    }
}

@end

@implementation H264Encoder (__BLACKMAGIC__)

-(void)pushData:(uint8_t*)data Size:(size_t)size timestamp:(uint64_t)pts{
    if(data == NULL || size == 0 || pts == 0){
        return;
    }
    
    if(self.state == H264ENCODE_STATE_SET){
        
        CVPixelBufferRef pixelBuffer = NULL;
        CVReturn ret = CVPixelBufferCreateWithBytes(NULL, self.width, self.height, k2vuyPixelFormat, data, self.width*2, NULL, NULL, NULL, &pixelBuffer);
        if(ret != kCVReturnSuccess)
        {
            NSLog(@"decklink CVPixelBufferCreate error return %d",ret);
            return;
        }

        [self doSetBitrate];
        
        OSStatus status = VTCompressionSessionEncodeFrame(_session, (CVImageBufferRef) pixelBuffer, CMTimeMake(pts, 1000), kCMTimeInvalid, NULL, NULL, NULL);
        if(status != noErr)
        {
            NSLog(@"decklink encode frame failured!%d,reset encoder...",status);
            [self resetEncoder];
        }
        CVPixelBufferRelease(pixelBuffer);
    }
}
@end
