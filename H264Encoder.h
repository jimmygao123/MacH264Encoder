//
//  H264Encoder.h
//  
//
//  Created by jimmygao on 12/31/15.
//
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

enum H264NALTYPE{
    H264NT_NAL = 0,
    H264NT_SLICE,
    H264NT_SLICE_DPA,
    H264NT_SLICE_DPB,
    H264NT_SLICE_DPC,
    H264NT_SLICE_IDR,
    H264NT_SEI,
    H264NT_SPS,
    H264NT_PPS,
};

typedef enum {
    H264ENCODE_STATE_INIT = 100,
    H264ENCODE_STATE_SET
}H264ENCODE_STATE;

typedef enum{
    H264ENCODE_ERROR_NOERR = 1000,
    H264ENCODE_ERROR_Create,
    H264ENCODE_ERROR_PrepareEncode,
    H264ENCODE_ERROR_UsingHardwareAcceleratedVideoEncoder,
    H264ENCODE_ERROR_RealTime,
    H264ENCODE_ERROR_ProfileLevel,
    H264ENCODE_ERROR_AllowFrameReordering,
    H264ENCODE_ERROR_H264EntropyMode,
    H264ENCODE_ERROR_ExpectedFrameRate,
    H264ENCODE_ERROR_AverageBitRate,
    H264ENCODE_ERROR_MaxKeyFrameIntervalDuration,
    H264ENCODE_ERROR_MaxFrameDelayCount,
    H264ENCODE_ERROR_DataRateLimits,
}H264ENCODE_ERROR;

@interface H264Encoder : NSObject

@property (nonatomic, assign, readonly) int height;
@property (nonatomic, assign, readonly) int width;
@property (nonatomic, assign, readonly) int fps;
@property (nonatomic, assign, readonly) int bitrate;

@property (atomic, assign, readonly) H264ENCODE_STATE state;
@property (nonatomic, assign, readonly) H264ENCODE_ERROR error;

+(instancetype)getInstance;

+(void)startEncoder;
+(void)stopEncoder;
+(void)restartEncoderWith:(int)width andHeight:(int)height andFPS:(int)fps;

@end

@interface H264Encoder (__USB__)
-(void)pushSample:(CMSampleBufferRef)sampleBuffer;
@end

@interface H264Encoder (__BLACKMAGIC__)
-(void)pushData:(uint8_t*)data Size:(size_t)size timestamp:(uint64_t)pts;
@end
