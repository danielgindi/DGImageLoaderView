//
//  DGImageLoaderView.m
//  DGImageLoaderView
//
//  Created by Daniel Cohen Gindi on 01/03/2012.
//  Copyright (c) 2011 Daniel Cohen Gindi. All rights reserved.
//
//  https://github.com/danielgindi/DGImageLoaderView
//
//  The MIT License (MIT)
//  
//  Copyright (c) 2014 Daniel Cohen Gindi (danielgindi@gmail.com)
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE. 
//  

#import "DGImageLoaderView.h"
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

#define DEFAULT_MAX_ASYNC_CONNECTIONS 8

@interface DGImageLoaderView ()
{
    BOOL _isDefaultLoaded;
    DGImageLoaderViewAnimationType _animationType;
    BOOL _waitingForDisplay, _waitingForDisplayWithAnimation;
    BOOL _hasImageLoaded;
    
    NSURL * _Nullable _nextUrlToLoad;
    NSDictionary<NSString *, NSString *> * _Nullable _headers;
    int _asyncOperationCounter;
    
    NSString *_tempFilePath;
    NSFileHandle *_fileWriteHandle;
    
    UIView *animatingViewToRemove;
    
    CGSize _cachedImageSize;
    CGFloat _cachedImageScale;
}

@property (nonatomic, strong) NSURLRequest *urlRequest;
@property (nonatomic, strong) NSURLConnection *urlConnection;

@property (nonatomic, strong) UIActivityIndicatorView *indicator;
@property (nonatomic, strong) UIImageView *nextImageView;
@property (nonatomic, strong) UIImageView *oldImageView;
@property (nonatomic, strong) UIImage *nextImage;

@end

@implementation DGImageLoaderView

// Performance tweaks

static NSUInteger s_DGImageLoaderView_maxAsyncConnections = DEFAULT_MAX_ASYNC_CONNECTIONS;
static NSUInteger s_DGImageLoaderView_currentActiveConnections = 0;
static NSMutableArray *s_DGImageLoaderView_queuedConnectionsArray = nil;
static NSMutableArray *s_DGImageLoaderView_activeConnectionsArray = nil;

#pragma mark - Init

- (id)init 
{
    if ((self = [super init]))
	{
		[self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder]))
	{
		[self initialize];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
	if ((self = [super initWithFrame:frame]))
	{
		[self initialize];
    }
    return self;
}

- (void)initialize
{
    if (!s_DGImageLoaderView_queuedConnectionsArray)
    {
        s_DGImageLoaderView_queuedConnectionsArray = [[NSMutableArray alloc] init];
    }
    if (!s_DGImageLoaderView_activeConnectionsArray)
    {
        s_DGImageLoaderView_activeConnectionsArray = [[NSMutableArray alloc] init];
    }
    
    _delayActualLoadUntilDisplay = NO;
    _delayImageShowUntilDisplay = YES;
    _waitingForDisplay = NO;
    _waitingForDisplayWithAnimation = NO;
    _isDefaultLoaded = NO;
    _keepAspectRatio = YES;
    _animationDuration = 0.8;
    _asyncLoadImages = YES;
    _resizeImages = YES;
    _cropAnchor = DGImageLoaderViewCropAnchorCenterCenter;
    _detectScaleFromFileName = YES;
    _autoFindScaledUrlForFileUrls = YES;
    _landscapeMode = DGImageLoaderViewLandscapeModeNone;
    _enlargeImage = YES;
    _defaultImageEnlarge = NO;
    
    self.clipsToBounds = YES;
}

- (void)dealloc
{
    [self closeAndRemoveTempFile];
}

- (void)closeAndRemoveTempFile
{
    if (_fileWriteHandle)
    {
        [_fileWriteHandle closeFile];
        _fileWriteHandle = nil;
    }
    if (_tempFilePath)
    {
        [[NSFileManager defaultManager] removeItemAtPath:_tempFilePath error:nil];
        _tempFilePath = nil;
    }
}

- (void)loadImageFromPath:(NSString *)path originalUrl:(NSURL *)originalURL notFromCache:(BOOL)notFromCache immediate:(BOOL)immediate
{
    int asyncIndex = ++_asyncOperationCounter;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        void (^loadBlock)(UIImage *, BOOL) = ^(UIImage *image, BOOL fromCache)
        {
            self.nextImage = image;
            
            if (image == nil)
            {
                if (self.onError != nil)
                {
                    self.onError();
                }
            }
            
            BOOL animate = notFromCache || !self->_doNotAnimateFromCache || !fromCache;
            [self playWithAnimation:animate immediate:immediate];
        };
        
        if (_resizeImages)
        {
            [self generateImageThumbnailForImage:nil localPath:path fromCacheOfURL:originalURL completion:^(UIImage *thumbnailImage, BOOL fromCache) {
                
                // If current operation is irrelevant by the time we finished thumbnailing the image from file, then cancel
                if (asyncIndex != self->_asyncOperationCounter) return;
                
                loadBlock(thumbnailImage, fromCache);
            }];
        }
        else
        {
            if (notFromCache || !_doNotAnimateFromCache)
            { // Load from file on another queue
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    
                    UIImage *image = [UIImage imageWithContentsOfFile:path];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        // If current operation is irrelevant by the time we finished thumbnailing the image from file, then cancel
                        if (asyncIndex != self->_asyncOperationCounter) return;
                        
                        loadBlock(image, NO);
                    });
                    
                });
            }
            else
            { // Load immediately, on main queue, to prevent visual hiccups
                loadBlock([UIImage imageWithContentsOfFile:path], YES);
            }
        }
    }
    else
    {
        if (self.onError != nil)
        {
            self.onError();
        }
    }
}

#pragma mark - UIView

- (void)layoutSubviews
{
    if (self.oldImageView)
    {
        self.oldImageView.frame = [self rectForImageSize:_oldImageView.image.size imageScale:_oldImageView.image.scale allowEnlarge:((_isDefaultLoaded && !self.nextImageView) ? _defaultImageEnlarge : _enlargeImage) flipForSuperview:YES];
    }
    if (self.nextImageView)
    {
        self.nextImageView.frame = [self rectForImageSize:_nextImageView.image.size imageScale:_nextImageView.image.scale allowEnlarge:(_isDefaultLoaded ? _defaultImageEnlarge : _enlargeImage) flipForSuperview:YES];
    }
    if (self.indicator)
    {
        CGRect rc = self.indicator.frame;
        rc.origin.x = (self.frame.size.width - rc.size.width) / 2.f;
        rc.origin.y = (self.frame.size.height - rc.size.height) / 2.f;
        self.indicator.frame = rc;
    }
}

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    
    if (_waitingForDisplay)
    { // Image is present, we are just waiting for this moment to start animating it, when the view came into view...
        _waitingForDisplay = NO;
        [self playWithAnimation:_waitingForDisplayWithAnimation immediate:YES];
    }
    
    if (_nextUrlToLoad)
    { // We are waiting for this moment to start loading the image, when the view came into view...
        [self loadImageFromURL:_nextUrlToLoad headers:_headers animationType:_animationType immediate:YES];
        _nextUrlToLoad = nil;
    }
}

- (CGSize)intrinsicContentSize
{
    if (_enableIntrinsicContentSize
        && (!CGSizeEqualToSize(_imageBounds, CGSizeZero)
        || !CGSizeEqualToSize(self.bounds.size, CGSizeZero))
        && (!CGSizeEqualToSize(_cachedImageSize, CGSizeZero)))
    {
        CGSize neededSize = [self rectForImageSize:_cachedImageSize imageScale:_cachedImageScale allowEnlarge:_enlargeImage flipForSuperview:NO].size;
        return neededSize;
    }
    return CGSizeMake(UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric);
}

#pragma mark - Utilities

// These are more accurate than CGAffineTransformMakeRotation, because of rounding errors
#define TRANSFORM_ROTATE_PLUS_90 ((CGAffineTransform){0.f, 1.f, -1.f, 0.f, 0.f, 0.f})
#define TRANSFORM_ROTATE_MINUS_90 ((CGAffineTransform){0.f, -1.f, 1.f, 0.f, 0.f, 0.f})

- (BOOL)requiresTransformForImageSize:(CGSize)imageSize
{
    if (_landscapeMode != DGImageLoaderViewLandscapeModeNone)
    {
        CGSize size = self.bounds.size;
        return ((imageSize.width > imageSize.height &&
             size.height > size.width) ||
            (imageSize.height > imageSize.width &&
             size.width > size.height));
    }
    return NO;
}

- (CGAffineTransform)transformForImage:(UIImage *)image
{
    if ([self requiresTransformForImageSize:image.size])
    {
        switch (_landscapeMode)
        {
            case DGImageLoaderViewLandscapeModeLeft:
                return TRANSFORM_ROTATE_MINUS_90;
            case DGImageLoaderViewLandscapeModeRight:
                return TRANSFORM_ROTATE_PLUS_90;
            default:
                break;
        }
    }
    return CGAffineTransformIdentity;
}

- (CGRect)rectForImageSize:(CGSize)imageSize
                imageScale:(CGFloat)imageScale
              allowEnlarge:(BOOL)allowEnlarge
          flipForSuperview:(BOOL)flipForSuperview
{
    float scale = imageScale / UIScreen.mainScreen.scale;
    BOOL flipSize = [self requiresTransformForImageSize:imageSize];
    
    CGRect bounds = self.bounds;
    if (self.imageBounds.width != 0.f ||
        self.imageBounds.height != 0.f)
    {
        bounds.size = self.imageBounds;
    }
    
    if (flipSize)
    {
        CGFloat temp = bounds.size.height;
        bounds.size.height = bounds.size.width;
        bounds.size.width = temp;
        temp = bounds.origin.y;
        bounds.origin.y = bounds.origin.x;
        bounds.origin.x = temp;
    }
    
    bounds = [DGImageLoaderView rectForWidth:imageSize.width * scale
                                   height:imageSize.height * scale
                                     inFrame:bounds
                                allowEnlarge:allowEnlarge
                             keepAspectRatio:_keepAspectRatio
                              fitFromOutside:_fitFromOutside
                                  cropAnchor:_cropAnchor];
    
    if (flipForSuperview && flipSize)
    {
        CGFloat temp = bounds.size.height;
        bounds.size.height = bounds.size.width;
        bounds.size.width = temp;
        temp = bounds.origin.y;
        bounds.origin.y = bounds.origin.x;
        bounds.origin.x = temp;
    }
    
    return bounds;
}

+ (CGRect)rectForWidth:(CGFloat)w
             height:(CGFloat)h
               inFrame:(CGRect)parentBox
          allowEnlarge:(BOOL)allowEnlarge
       keepAspectRatio:(BOOL)keepAspectRatio
        fitFromOutside:(BOOL)fitFromOutside
            cropAnchor:(DGImageLoaderViewCropAnchor)cropAnchor
{
    CGRect box;
    
    if (parentBox.size.width == 0.0 || parentBox.size.height == 0.0)
    {
        if (parentBox.size.width == 0.0 && parentBox.size.height == 0.0)
        {
            parentBox.size.width = w;
            parentBox.size.height = h;
        }
        else if (parentBox.size.width == 0.0)
        {
            parentBox.size.width = w / h * parentBox.size.height;
        }
        else
        {
            parentBox.size.height = h / w * parentBox.size.width;
        }
    }
    
    if (keepAspectRatio)
    {
        if (w <= parentBox.size.width && h <= parentBox.size.height && !allowEnlarge)
        {
            box.size.width = w;
            box.size.height = h;
        }
        else
        {
            CGFloat ratio = h == 0 ? 1 : (w / h);
            CGFloat newRatio = parentBox.size.height == 0 ? 1 : (parentBox.size.width / parentBox.size.height);
            
            if ((newRatio > ratio && !fitFromOutside) ||
                (newRatio < ratio && fitFromOutside))
            {
                box.size.height = parentBox.size.height;
                box.size.width = box.size.height * ratio;
            }
            else if ((newRatio > ratio && fitFromOutside) ||
                     (newRatio < ratio && !fitFromOutside))
            {
                box.size.width = parentBox.size.width;
                box.size.height = box.size.width / ratio;
            }
            else
            {
                box.size = parentBox.size;
            }
        }
        
        if (fitFromOutside)
        {
            switch (cropAnchor)
            {
                default:
                case DGImageLoaderViewCropAnchorCenterCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGImageLoaderViewCropAnchorCenterLeft:
                    box.origin.x = 0.f;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGImageLoaderViewCropAnchorCenterRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGImageLoaderViewCropAnchorTopCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = 0.f;
                    break;
                case DGImageLoaderViewCropAnchorTopLeft:
                    box.origin.x = 0.f;
                    box.origin.y = 0.f;
                    break;
                case DGImageLoaderViewCropAnchorTopRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = 0.f;
                    break;
                case DGImageLoaderViewCropAnchorBottomCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
                case DGImageLoaderViewCropAnchorBottomLeft:
                    box.origin.x = 0.f;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
                case DGImageLoaderViewCropAnchorBottomRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
            }
        }
        else
        {
            box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
            box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
        }
    }
    else
    {
        box.origin.x = 0.f;
        box.origin.y = 0.f;
        box.size = parentBox.size;
    }
    
    box.origin.x += parentBox.origin.x;
    box.origin.y += parentBox.origin.y;
    
    return box;
}

- (UIImage *)imageByScalingImage:(UIImage *)image toSize:(CGSize)size
{
    UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (NSString *)newTempFilePath
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef uuidStr = CFUUIDCreateString(NULL, uuid);
    
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"image-loader-%@", uuidStr]];
    
    CFRelease(uuidStr);
    CFRelease(uuid);
    
    return path;
}

- (NSFileHandle *)fileHandleToANewTempFile:(out NSString **)filePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *tempFilePath = self.newTempFilePath;
    int tries = 3;
    BOOL success = [fileManager createFileAtPath:tempFilePath contents:nil attributes:nil];
    while (!success && --tries)
    {
        tempFilePath = self.newTempFilePath;
        success = [fileManager createFileAtPath:tempFilePath contents:nil attributes:nil];
    }
    
    if (success)
    {
        if (filePath)
        {
            *filePath = tempFilePath;
        }
        return [NSFileHandle fileHandleForWritingAtPath:tempFilePath];
    }
    
    return nil;
}

- (NSURL *)normalizedUrlForUrl:(NSURL * _Nullable)url
{
    if (url == nil)
    {
        return url;
    }
    
    if (_autoFindScaledUrlForFileUrls && url.isFileURL)
    {
        CGFloat screenScale = UIScreen.mainScreen.scale;
        NSString *scaleString = [NSString stringWithFormat:@"@%gx", screenScale];
        if (screenScale != 1.f && ![[[url lastPathComponent] stringByDeletingPathExtension] hasSuffix:scaleString])
        {
            NSString *path = [[url path] stringByDeletingPathExtension];
            path = [path stringByAppendingString:scaleString];
            if (url.pathExtension.length || [[url lastPathComponent] hasSuffix:@"."])
            {
                path = [path stringByAppendingPathExtension:url.pathExtension];
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            {
                return [[NSURL alloc] initFileURLWithPath:path];
            }
        }
    }
    return url;
}

#pragma mark - Caching stuff

+ (NSString *)md5ForString:(NSString *)string
{
    const char *urlStr = string.UTF8String;
    unsigned char md5result[16];
    CC_MD5(urlStr, (CC_LONG)strlen(urlStr), md5result); // This is the md5 call
    return [NSString stringWithFormat:
             @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
             md5result[0], md5result[1], md5result[2], md5result[3],
             md5result[4], md5result[5], md5result[6], md5result[7],
             md5result[8], md5result[9], md5result[10], md5result[11],
             md5result[12], md5result[13], md5result[14], md5result[15]
             ];
}

- (NSString * _Nullable)localCachePathForUrl:(NSURL * _Nullable)url
{
    if (!url) return nil; // Silence Xcode's Analyzer
    
    // an alternative to the NSTemporaryDirectory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = paths.count ? paths[0] : [NSHomeDirectory() stringByAppendingString:@"/Library/Caches"];
    path = [path stringByAppendingPathComponent:@"dg-image-loader/original"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path])
    {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error])
        {
            NSLog(@"Can't create cache folder, error: %@", error);
            return nil;
        }
    }
    
    path = [path stringByAppendingPathComponent:[DGImageLoaderView md5ForString:url.absoluteString]];
    
    NSString *fn = url.lastPathComponent.lowercaseString;
    
    NSString *fnWithoutExtension = [fn stringByDeletingPathExtension];
    NSString *scaleString = nil;
    if (_detectScaleFromFileName)
    {
        scaleString = [fnWithoutExtension hasSuffix:@"@2x"] ? @"@2x" : ([fnWithoutExtension hasSuffix:@"@3x"] ? @"@3x" : nil);
    }
    else
    {
        CGFloat screenScale = UIScreen.mainScreen.scale;
        scaleString = screenScale == 1.f ? nil : [NSString stringWithFormat:@"@%gx", UIScreen.mainScreen.scale];
    }

    if (scaleString)
    {
        path = [path stringByAppendingString:scaleString];
    }
    
    if (fn.pathExtension.length)
    {
        path = [path stringByAppendingPathExtension:fn.pathExtension];
    }
    
    return path;
}

- (NSString * _Nullable)localCachePathForUrl:(NSURL * _Nullable)url withThumbnailSize:(CGSize)thumbnailSize
{
    // an alternative to the NSTemporaryDirectory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = paths.count ? paths[0] : [NSHomeDirectory() stringByAppendingString:@"/Library/Caches"];
    path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"dg-image-loader/Thumbnail%f,%f", thumbnailSize.width, thumbnailSize.height]];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path])
    {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error])
        {
            NSLog(@"Can't create cache folder, error: %@", error);
            return nil;
        }
    }
    
    path = [path stringByAppendingPathComponent:[DGImageLoaderView md5ForString:url.absoluteString]];
    
    NSString *fn = url.lastPathComponent.lowercaseString;
    
    CGFloat screenScale = UIScreen.mainScreen.scale;
    if (screenScale != 1.f)
    {
        NSString *scaleString = [NSString stringWithFormat:@"@%gx", screenScale];
        path = [path stringByAppendingString:scaleString];
    }
    
    if (fn.pathExtension.length)
    {
        path = [path stringByAppendingPathExtension:fn.pathExtension];
    }
    
    return path;
}

- (void)generateImageThumbnailForImage:(UIImage *)image localPath:(NSString *)path fromCacheOfURL:(NSURL *)url completion:(void(^)(UIImage *thumbnailImage, BOOL fromCache))completion
{
    CGSize neededSize, imageSize = CGSizeZero;
    CGFloat imageScale = 1.f;
    
    if (image)
    {
        imageSize = image.size;
        imageScale = image.scale;
    }
    else if (path)
    {
        imageSize = [DGImageLoaderView sizeOfImageFileAtPath:path];
        if (imageSize.width == 0.f)
        {
            image = [UIImage imageWithContentsOfFile:path];
            imageSize = image.size;
            imageScale = image.scale;
        }
    }
    
    imageSize.width *= imageScale / UIScreen.mainScreen.scale;
    imageSize.height *= imageScale / UIScreen.mainScreen.scale;
    imageScale = UIScreen.mainScreen.scale;
    
    _cachedImageSize = imageSize;
    _cachedImageScale = imageScale;
    
    if (self.onImageSizeKnown)
    {
        self.onImageSizeKnown(imageSize);
    }
    
    if (self.enableIntrinsicContentSize)
    {
        [self invalidateIntrinsicContentSize];
    }
    
    if (imageSize.width <= 0.f || imageSize.height <= 0.f)
    {
        completion(nil, YES);
        return;
    }
    
    neededSize = [self rectForImageSize:imageSize imageScale:imageScale allowEnlarge:_enlargeImage flipForSuperview:NO].size;
    
    CGSize currentSize = imageSize;
    float scale = imageScale / UIScreen.mainScreen.scale;
    currentSize.width *= scale;
    currentSize.height *= scale;
    
    if (neededSize.width != currentSize.width ||
        neededSize.height != currentSize.height)
    {
        neededSize.width = roundf(neededSize.width);
        neededSize.height = roundf(neededSize.height);
        
        NSString *thumbCachePath = url ? [self localCachePathForUrl:url withThumbnailSize:neededSize] : nil;
        
        if (thumbCachePath && !_noCache && [[NSFileManager defaultManager] fileExistsAtPath:thumbCachePath])
        {
            image = [UIImage imageWithContentsOfFile:thumbCachePath];
            completion(image, YES);
            return;
        }
        
        if (_asyncLoadImages)
        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                UIImage *originalImage = image ?: [UIImage imageWithContentsOfFile:path];
                UIImage *thumbnailImage = [self imageByScalingImage:originalImage toSize:neededSize];
                originalImage = nil;
                if (thumbCachePath)
                {
                    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(thumbnailImage.CGImage);
                    if (alphaInfo != kCGImageAlphaNone && alphaInfo != kCGImageAlphaNoneSkipLast && alphaInfo != kCGImageAlphaNoneSkipFirst)
                    {
                        [UIImagePNGRepresentation(thumbnailImage) writeToFile:thumbCachePath options:NSDataWritingAtomic error:nil];
                    }
                    else
                    {
                        [UIImageJPEGRepresentation(thumbnailImage, 1.f) writeToFile:thumbCachePath options:NSDataWritingAtomic error:nil];
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(thumbnailImage, NO);
                });
            });
        }
        else
        {
            UIImage *originalImage = image ?: [UIImage imageWithContentsOfFile:path];
            UIImage *thumbnailImage = [self imageByScalingImage:originalImage toSize:neededSize];
            originalImage = nil;
            if (thumbCachePath)
            {
                CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(thumbnailImage.CGImage);
                if (alphaInfo != kCGImageAlphaNone && alphaInfo != kCGImageAlphaNoneSkipLast && alphaInfo != kCGImageAlphaNoneSkipFirst)
                {
                    [UIImagePNGRepresentation(thumbnailImage) writeToFile:thumbCachePath options:NSDataWritingAtomic error:nil];
                }
                else
                {
                    [UIImageJPEGRepresentation(thumbnailImage, 1.f) writeToFile:thumbCachePath options:NSDataWritingAtomic error:nil];
                }
            }
            completion(thumbnailImage, NO);
        }
    }
    else
    {
        completion(image ?: [UIImage imageWithContentsOfFile:path], YES);
    }
}

#pragma mark - Accessors

- (void)setDefaultImage:(UIImage *)defaultImage
{
    _defaultImage = defaultImage;
    if (!_hasImageLoaded)
    {
        UIImageView *imageView = self.nextImageView ?: self.oldImageView;
        if (imageView)
        {
            if (_defaultImage)
            { // There's a default image, set it to the existing view
                imageView.image = defaultImage;
                imageView.transform = [self transformForImage:imageView.image];
                imageView.frame = [self rectForImageSize:imageView.image.size imageScale:imageView.image.scale allowEnlarge:_defaultImageEnlarge flipForSuperview:YES];
            }
            else
            { // There's no default image, remove the view
                [imageView removeFromSuperview];
                if (imageView == self.nextImageView)
                {
                    self.nextImageView = nil;
                }
                else if (imageView == self.oldImageView)
                {
                    self.oldImageView = nil;
                }
            }
        }
        else
        { // There's no image view
            if (defaultImage)
            {
                self.oldImageView = imageView = [[UIImageView alloc] initWithImage:_defaultImage];
                imageView.contentMode = UIViewContentModeScaleToFill;
                imageView.transform = [self transformForImage:imageView.image];
                imageView.frame = [self rectForImageSize:imageView.image.size imageScale:imageView.image.scale allowEnlarge:_defaultImageEnlarge flipForSuperview:YES];
                [self addSubview:imageView];
            }
        }
        _isDefaultLoaded = !!defaultImage;
    }
}

- (UIImage *)currentVisibleImage
{
    return self.oldImageView.image;
}

- (UIImage *)currentVisibleImageNotDefault
{
    if (!_isDefaultLoaded)
    {
        return self.oldImageView.image;
    }
    return nil;
}

- (BOOL)hasImageLoaded
{
    return _hasImageLoaded;
}

- (void)setEnableIntrinsicContentSize:(BOOL)enableIntrinsicContentSize
{
    if (_enableIntrinsicContentSize != enableIntrinsicContentSize)
    {
        _enableIntrinsicContentSize = enableIntrinsicContentSize;
    }
    [self invalidateIntrinsicContentSize];
}

- (void)setImageBounds:(CGSize)imageBounds
{
    _imageBounds = imageBounds;
    [self invalidateIntrinsicContentSize];
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if ([response respondsToSelector:@selector(statusCode)])
	{
		NSInteger statusCode = [((NSHTTPURLResponse *)response) statusCode];
        if (statusCode >= 400)
		{
			[self connection:connection didFailWithError:[NSError errorWithDomain:response.URL.host code:statusCode userInfo:nil]];
		}
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)incrementalData 
{
    if (!_fileWriteHandle)
	{
        NSString *filePath;
        _fileWriteHandle = [self fileHandleToANewTempFile:&filePath];
        _tempFilePath = filePath;
    }
    [_fileWriteHandle writeData:incrementalData];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self stopAndRemoveConnection];
    [self.indicator stopAnimating];
    self.indicator.hidden = YES;
    
    if (self.onError != nil)
    {
        self.onError();
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (_fileWriteHandle)
	{
        [self stopAndRemoveConnection];
        [_fileWriteHandle closeFile];
        _fileWriteHandle = nil;
        
        [self.indicator stopAnimating];
        self.indicator.hidden = YES;
        
        NSString *localPath = [self localCachePathForUrl:_urlRequest.URL];
        NSFileManager *fileManager = NSFileManager.defaultManager;
        [fileManager removeItemAtPath:localPath error:nil];
        [fileManager moveItemAtPath:_tempFilePath toPath:localPath error:nil];
        _tempFilePath = nil;
        
        [self loadImageFromPath:localPath originalUrl:_urlRequest.URL notFromCache:YES immediate:NO];
	}
    else
    {
        [self connection:connection didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]];
    }
}

#pragma mark - Public methods

- (void)loadImageFromURL:(NSURL * _Nullable)url
        andAnimationType:(DGImageLoaderViewAnimationType)animationType
{
    [self loadImageFromURL:url
                   headers:nil
             animationType:animationType
                 immediate:NO];
}

- (void)loadImageFromURL:(NSURL * _Nullable)url
        andAnimationType:(DGImageLoaderViewAnimationType)animationType
        immediate:(BOOL)immediate
{
    [self loadImageFromURL:url
                   headers:nil
             animationType:animationType
                 immediate:immediate];
}

- (void)loadImageFromURL:(NSURL * _Nullable)url
                 headers:(NSDictionary * _Nullable)headers
           animationType:(DGImageLoaderViewAnimationType)animationType
{
    [self loadImageFromURL:url
                   headers:headers
             animationType:animationType
                 immediate:NO];
}

- (void)loadImageFromURL:(NSURL * _Nullable)url
                 headers:(NSDictionary * _Nullable)headers
           animationType:(DGImageLoaderViewAnimationType)animationType
               immediate:(BOOL)immediate
{
    url = [self normalizedUrlForUrl:url];
    
    _animationType = animationType;
    
    _nextUrlToLoad = nil;
    _headers = nil;
    
    // If we need to delay loading until the view is actually displayed, and it hasn't yet, then:
    if (_delayActualLoadUntilDisplay && !immediate)
    {
        _nextUrlToLoad = url;
        _headers = headers;
        [self setNeedsDisplay]; // Cause drawRect: to be called when coming on-screen
        return;
    }
    
    BOOL isFileURL = url.isFileURL;
    
    NSString *cachePath = isFileURL ? nil : (url ? [self localCachePathForUrl:url] : nil);
    
    if (!url || isFileURL || (!_noCache && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]))
    {
        [self loadImageFromPath:(isFileURL ? url.path : cachePath) originalUrl:url notFromCache:NO immediate:immediate];
    }
    else
    {
        if (!self.indicator)
        {
            self.indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            CGRect rc = self.indicator.frame;
            rc.origin.x = (self.frame.size.width - rc.size.width) / 2.f;
            rc.origin.y = (self.frame.size.height - rc.size.height) / 2.f;
            self.indicator.frame = rc;
            [self addSubview:self.indicator];
        }
        else
        {
            self.indicator.hidden = NO;
            [self bringSubviewToFront:self.indicator];
        }
        [self.indicator startAnimating];
        
        if (self.urlConnection)
        {
            [self stopAndRemoveConnection];
        }
        [self closeAndRemoveTempFile];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60.0];

        if (headers != nil)
        {
            for (NSString * key in headers.allKeys)
            {
                [request addValue:headers[key] forHTTPHeaderField:key];
            }
        }

        self.urlRequest = request;
        self.urlConnection = [[NSURLConnection alloc] initWithRequest:_urlRequest delegate:self startImmediately:NO];
        
        @synchronized(s_DGImageLoaderView_queuedConnectionsArray)
        {
            [s_DGImageLoaderView_queuedConnectionsArray addObject:self.urlConnection];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^(void){
                [DGImageLoaderView continueConnectionQueue];
            });
        }
    }
}

- (void)loadImage:(UIImage * _Nullable)image withAnimationType:(DGImageLoaderViewAnimationType)animationType
{
    _nextUrlToLoad = nil;
    _headers = nil;
    
    if (!image)
    {
        [self reset];
    }
    else
    {
        [self stopAndRemoveConnection];
        
        int asyncIndex = ++_asyncOperationCounter;
        
        void (^loadBlock)(UIImage *, BOOL) = ^(UIImage *image, BOOL fromCache)
        {
            self.nextImage = image;
            
            BOOL animate = !self->_doNotAnimateFromCache;
            [self playWithAnimation:animate immediate:NO];
        };
        
        if (_resizeImages)
        {
            [self generateImageThumbnailForImage:image localPath:nil fromCacheOfURL:nil completion:^(UIImage *thumbnailImage, BOOL fromCache) {
                // If current operation is irrelevant by the time we finished thumbnailing the image from file
                if (asyncIndex != self->_asyncOperationCounter) return;
                
                loadBlock(thumbnailImage, fromCache);
            }];
        }
        else
        {
            loadBlock(image, YES);
        }
    }
}

- (void)stop
{
    [self stopAndRemoveConnection];
    [self closeAndRemoveTempFile];
    _waitingForDisplay = NO;
    _nextUrlToLoad = nil;
    _headers = nil;
}

- (void)reset
{
	[self stop];
    
    if (self.oldImageView)
    {
        [self.oldImageView removeFromSuperview];
        self.oldImageView = nil;
    }
    
    if (self.nextImageView)
    {
        [self.nextImageView removeFromSuperview];
        self.nextImageView = nil;
    }
    
    if (animatingViewToRemove)
    {
        [animatingViewToRemove removeFromSuperview];
        animatingViewToRemove = nil;
    }
    
    if (self.defaultImage)
    {
        UIImageView *oldImageView = self.oldImageView = [[UIImageView alloc] initWithImage:self.defaultImage];
        oldImageView.contentMode = UIViewContentModeScaleToFill;
        oldImageView.transform = [self transformForImage:oldImageView.image];
        oldImageView.frame = [self rectForImageSize:oldImageView.image.size imageScale:oldImageView.image.scale allowEnlarge:_defaultImageEnlarge flipForSuperview:YES];
        [self addSubview:oldImageView];
    }
    
    [self.indicator stopAnimating];
    self.indicator.hidden = YES;
    
    _hasImageLoaded = NO;
    _isDefaultLoaded = !!self.defaultImage;
    _nextUrlToLoad = nil;
    _headers = nil;
    _waitingForDisplayWithAnimation = NO;
    _waitingForDisplay = NO;
    _cachedImageSize = CGSizeZero;
    _cachedImageScale = 0.0;
}

+ (int)removeImageFromCache:(NSURL * _Nullable)url
{
    if (!url) return 0;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = paths.count ? paths[0] : [NSHomeDirectory() stringByAppendingString:@"/Library/Caches"];
    path = [path stringByAppendingPathComponent:@"dg-image-loader"];
    
    NSString *fileNameToRemove = [self md5ForString:url.absoluteString];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    int deleted = 0;
    
    for (NSURL *subFolder in [fileManager enumeratorAtURL:[[NSURL alloc] initFileURLWithPath:path isDirectory:YES] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil])
    {
        for (NSURL *fileName in [fileManager enumeratorAtURL:subFolder includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil])
        {
            if ([[fileName lastPathComponent] hasPrefix:fileNameToRemove])
            {
                NSError *error;
                [fileManager removeItemAtURL:fileName error:&error];
                deleted++;
            }
        }
    }
    
    return deleted;
}

+ (void)clearCache
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = paths.count ? paths[0] : [NSHomeDirectory() stringByAppendingString:@"/Library/Caches"];
    path = [path stringByAppendingPathComponent:@"dg-image-loader"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSURL *url in [fileManager enumeratorAtURL:[[NSURL alloc] initFileURLWithPath:path isDirectory:YES] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil])
    {
        [fileManager removeItemAtURL:url error:nil];
    }
}

#pragma mark - Animation stuff

- (void)playWithAnimation:(BOOL)withAnimation immediate:(BOOL)immediate
{
    if (self.nextImage)
    {
        _hasImageLoaded = YES;
    }
    
    // Default next image if needed
    if (!self.nextImage || (self.nextImage.size.width <= 1 && self.nextImage.size.height <= 1))
    {
        self.nextImage = self.defaultImage;
        _hasImageLoaded = NO;
        _isDefaultLoaded = !!self.nextImage;
    }
    else
    {
        _isDefaultLoaded = NO;
    }
    
    // If we need to delay loading until the view is actually displayed, and it hasn't yet and also its not the default image which is already loaded to memory, then:
    if (self.nextImage && (_delayActualLoadUntilDisplay || _delayImageShowUntilDisplay) && !immediate && !_isDefaultLoaded)
    {
        _waitingForDisplay = YES;
        _waitingForDisplayWithAnimation = withAnimation;
        [self setNeedsDisplay]; // Cause drawRect: to be called when coming on-screen
        return;
    }
    
    // Clear animation type if the [withAnimation] argument is not set
    DGImageLoaderViewAnimationType animationType = withAnimation?_animationType:DGImageLoaderViewAnimationTypeNone;
    
    if (self.nextImage)
    {
        // Prepare next image view for animation
        UIImageView *nextImageView = self.nextImageView = [[UIImageView alloc] initWithImage:self.nextImage];
        nextImageView.contentMode = UIViewContentModeScaleToFill;
        nextImageView.transform = [self transformForImage:nextImageView.image];
        nextImageView.frame = [self rectForImageSize:nextImageView.image.size imageScale:nextImageView.image.scale allowEnlarge:_defaultImageEnlarge flipForSuperview:YES];
    }
    
    [self.indicator stopAnimating];
    self.indicator.hidden = YES;
    self.nextImage = nil;
    
    // Switch image views with or without animation
    switch (animationType)
    {
        default:
        case DGImageLoaderViewAnimationTypeNone:
        {
            if (self.nextImageView)
            {
                [self addSubview:self.nextImageView];
            }
            [self.oldImageView removeFromSuperview];
            self.oldImageView = self.nextImageView;
            self.nextImageView = nil;
        }
            break;
            
        case DGImageLoaderViewAnimationTypeFade:
        {
            if (animatingViewToRemove)
            {
                [animatingViewToRemove removeFromSuperview];
                animatingViewToRemove = nil;
            }
            
            self.nextImageView.alpha = 0;
            if (self.nextImageView)
            {
                [self addSubview:self.nextImageView];
            }
            UIView *oldView = self.oldImageView, *nextView = self.nextImageView;
            self.oldImageView = self.nextImageView;
            self.nextImageView = nil;
            animatingViewToRemove = oldView;
            [UIView animateWithDuration:_animationDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                nextView.alpha = 1;
                oldView.alpha = 0;
            } completion:^(BOOL finished) {
                [oldView removeFromSuperview];
                if (self->animatingViewToRemove == oldView)
                {
                    self->animatingViewToRemove = nil;
                }
            }];
        }
            break;
    }
}

#pragma mark - Connection control

+ (NSUInteger)maxAsyncConnections
{
    return s_DGImageLoaderView_maxAsyncConnections;
}

+ (void)setMaxAsyncConnections:(NSUInteger)max
{
    @synchronized(s_DGImageLoaderView_queuedConnectionsArray)
    {
        s_DGImageLoaderView_maxAsyncConnections = max;
    }
    [DGImageLoaderView continueConnectionQueue];
}

+ (NSUInteger)activeConnections
{
    return s_DGImageLoaderView_currentActiveConnections;
}

+ (NSUInteger)totalConnections
{
    @synchronized(s_DGImageLoaderView_queuedConnectionsArray)
    {
        return s_DGImageLoaderView_activeConnectionsArray.count + s_DGImageLoaderView_queuedConnectionsArray.count;
    }
}

- (void)stopAndRemoveConnection
{
    if (!self.urlConnection) return;
    [self.urlConnection cancel];
    @synchronized(s_DGImageLoaderView_queuedConnectionsArray)
    {
        if ([s_DGImageLoaderView_activeConnectionsArray containsObject:self.urlConnection])
        {
            [s_DGImageLoaderView_activeConnectionsArray removeObject:self.urlConnection];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1), dispatch_get_main_queue(), ^(void) {
                [DGImageLoaderView continueConnectionQueue];
            });
        }
        else if ([s_DGImageLoaderView_queuedConnectionsArray containsObject:self.urlConnection])
        {
            [s_DGImageLoaderView_queuedConnectionsArray removeObject:self.urlConnection];
        }
    }
    self.urlConnection = nil;
}

+ (void)continueConnectionQueue
{
    @synchronized(s_DGImageLoaderView_queuedConnectionsArray)
    {
        if (s_DGImageLoaderView_queuedConnectionsArray.count && s_DGImageLoaderView_activeConnectionsArray.count < s_DGImageLoaderView_maxAsyncConnections)
        {
            NSURLConnection *connection = [s_DGImageLoaderView_queuedConnectionsArray objectAtIndex:0];
            [s_DGImageLoaderView_queuedConnectionsArray removeObject:connection];
            [s_DGImageLoaderView_activeConnectionsArray addObject:connection];
            [connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            [connection start];
        }
    }
}

#pragma mark - DGFastImageSize

/* DGFastImageSize is embedded here to prevent dependency on another library */

// Headers to identify the different formats
#define JPEG_HEADER			(uint8_t[2]){ 0xff, 0xd8 }
#define JPEG_EXIF_HEADER	(uint8_t[4]){ 'E', 'x', 'i', 'f' }
#define PNG_HEADER			(uint8_t[8]){ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }
#define GIF_HEADER			(uint8_t[3]){ 'G', 'I', 'F' }
#define BMP_HEADER			(uint8_t[2]){ 0x42, 0x4D }
#define ICNS_HEADER			(uint8_t[4]){ 'i', 'c', 'n', 's' }

// Exit tag types
#define EXIF_TAGTYPE_BYTE			1		// BYTE	    8-bit unsigned integer
#define EXIF_TAGTYPE_SHORT			3		// SHORT    16-bit unsigned integer
#define EXIF_TAGTYPE_LONG			4		// LONG     32-bit unsigned integer
#define EXIF_TAGTYPE_SBYTE			6		// SBYTE    8-bit signed integer
#define EXIF_TAGTYPE_SSHORT         8		// SSHORT   16-bit signed integer
#define EXIF_TAGTYPE_SLONG			9		// SLONG    32-bit signed integer

// Exif tags
#define EXIF_TAG_ORIENTATION 0x0112
#define EXIF_TAG_PIX_XDIM 0xA002
#define EXIF_TAG_PIX_YDIM 0xA003
#define EXIF_TAG_IMAGE_WIDTH 0x0100
#define EXIF_TAG_IMAGE_HEIGHT 0x0101
#define EXIF_TAG_IFD 0x8769

// Bitwise macros
#define READ_UINT16	(fread(buffer, 1, 2, file) == 2)
#define LAST_UINT16	(uint16_t)(littleEndian ? (buffer[0] | buffer[1] << 8) : (buffer[1] | buffer[0] << 8))
#define LAST_INT16	(int16_t)(littleEndian ? (buffer[0] | buffer[1] << 8) : (buffer[1] | buffer[0] << 8))
#define READ_UINT32	(fread(buffer, 1, 4, file) == 4)
#define LAST_UINT32	(uint32_t)(littleEndian ? (buffer[0] | buffer[1] << 8 | buffer[2] << 16 | buffer[3] << 24) : (buffer[3] | buffer[2] << 8 | buffer[1] << 16 | buffer[0] << 24))

+ (CGSize)sizeOfImageFileAtPath:(NSString *)filePath;
{
    BOOL success = NO;
    CGSize size = CGSizeZero;
    
    FILE *file = fopen([[NSFileManager defaultManager] fileSystemRepresentationWithPath:filePath], "r");
    if (file)
    {
        uint8_t buffer[4];
        if (fread(buffer, 1, 2, file) == 2 &&
            memcmp(buffer, JPEG_HEADER, 2) == 0)
        { // JPEG
            size = [self sizeOfImageFileAtPath_JPEG:file];
            success = size.width > 0.f && size.height > 0.f;
        }
        
        if(!success)
        { // Apple icon file
            fseek( file, 0, SEEK_SET );
            size = [self sizeOfImageFileAtPath_ICNS: file];
            success = size.width > 0.f && size.height > 0.f;
        }
        
        if (!success)
        { // Now try to detect a PNG
            fseek(file, 0, SEEK_SET);
            
            uint8_t buffer8[8];
            if (fread(buffer8, 1, 8, file) == 8 &&
                memcmp(buffer8, PNG_HEADER, 8) == 0)
            {
                // It's a PNG!
                
                if (!fseek(file, 8, SEEK_CUR))
                {
                    if (fread(buffer, 1, 4, file) == 4)
                    {
                        size.width = (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
                    }
                    if (fread(buffer, 1, 4, file) == 4)
                    {
                        size.height = (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
                        success = YES;
                    }
                }
            }
        }
        
        if (!success)
        { // Now try to detect a GIF
            fseek(file, 0, SEEK_SET);
            
            if (fread(buffer, 1, 3, file) == 3 &&
                memcmp(buffer, GIF_HEADER, 3) == 0)
            {
                // It's a GIF!
                
                if (!fseek(file, 3, SEEK_CUR)) // 87a / 89a
                {
                    if (fread(buffer, 1, 4, file) == 4)
                    {
                        size = (CGSize){*((int16_t*)buffer), *((int16_t*)(buffer + 2))};
                        success = YES;
                    }
                }
            }
        }
        
        if (!success)
        { // Now try to detect a bitmap
            fseek(file, 0, SEEK_SET);
            
            if (fread(buffer, 1, 2, file) == 2 &&
                memcmp(buffer, BMP_HEADER, 2) == 0)
            {
                // It's a bitmap!
                
                if (!fseek(file, 16, SEEK_CUR))
                {
                    if (fread(buffer, 1, 4, file) == 4)
                    {
                        size.width = *((int32_t*)buffer);
                    }
                    if (fread(buffer, 1, 4, file) == 4)
                    {
                        size.height = *((int32_t*)buffer);
                        success = YES;
                    }
                }
            }
        }
        
        if(!success)
        {
            // TIFF starts with just plain EXIF
            
            fseek(file, 0, SEEK_SET);
            size = [self sizeOfImageFileAtPath_EXIF:file];
            // success = size.width > 0.f && size.height > 0.f; // Not needed, analyzer...
        }
        
        fclose(file);
    }
    
    return size;
}

+ (CGSize)sizeOfImageFileAtPath_EXIF:(FILE *)file
{
    uint8_t buffer[4];
    
    fpos_t offset;
    if (fgetpos(file, &offset)) return CGSizeZero;
    
    // Read Byte alignment
    if (fread(buffer, 1, 2, file) != 2) return CGSizeZero;
    
    bool littleEndian = false;
    if (buffer[0] == 0x49 && buffer[1] == 0x49)
    {
        littleEndian = true;
    }
    else if (buffer[0] != 0x4D && buffer[1] != 0x4D) return CGSizeZero;
    
    // TIFF tag marker
    if (!READ_UINT16 || LAST_UINT16 != 0x002A) return CGSizeZero;
    
    // Directory offset bytes
    if (!READ_UINT32) return CGSizeZero;
    uint32_t dirOffset = LAST_UINT32;
    
    int tag;
    uint16_t numberOfTags, tagType;
    uint32_t /*tagLength, */tagValue;
    int orientation = 1, width = 0, height = 0;
    uint32_t exifIFDOffset = 0;
    
    while (dirOffset != 0)
    {
        fseek(file, (long)offset + dirOffset, SEEK_SET);
        
        if (!READ_UINT16) return CGSizeZero;
        numberOfTags = LAST_UINT16;
        
        for (uint16_t i = 0; i < numberOfTags; i++)
        {
            if (!READ_UINT16) return CGSizeZero;
            tag = LAST_UINT16;
            
            if (!READ_UINT16) return CGSizeZero;
            tagType = LAST_UINT16;
            
            if (!READ_UINT32) return CGSizeZero;
            /*tagLength = LAST_UINT32*/;
            
            if (tag == EXIF_TAG_ORIENTATION ||
                tag == EXIF_TAG_PIX_XDIM ||
                tag == EXIF_TAG_IMAGE_WIDTH ||
                tag == EXIF_TAG_PIX_YDIM ||
                tag == EXIF_TAG_IMAGE_HEIGHT ||
                tag == EXIF_TAG_IFD)
            {
                switch (tagType)
                {
                    default:
                    case EXIF_TAGTYPE_BYTE:
                    case EXIF_TAGTYPE_SBYTE:
                        tagValue = fread(buffer, 1, 1, file) == 1 && buffer[0];
                        fseek(file, 3, SEEK_CUR);
                        break;
                    case EXIF_TAGTYPE_SHORT:
                    case EXIF_TAGTYPE_SSHORT:
                        if (!READ_UINT16) return CGSizeZero;
                        tagValue = LAST_UINT16;
                        fseek(file, 2, SEEK_CUR);
                        break;
                    case EXIF_TAGTYPE_LONG:
                    case EXIF_TAGTYPE_SLONG:
                        if (!READ_UINT32) return CGSizeZero;
                        tagValue = LAST_UINT32;
                        break;
                }
                
                switch (tag)
                {
                    case EXIF_TAG_ORIENTATION:
                        // Orientation tag
                        orientation = (int)tagValue;
                        break;
                    case EXIF_TAG_PIX_XDIM:
                    case EXIF_TAG_IMAGE_WIDTH:
                        // Width tag
                        width = (int)tagValue;
                        break;
                    case EXIF_TAG_PIX_YDIM:
                    case EXIF_TAG_IMAGE_HEIGHT:
                        // Height tag
                        height = (int)tagValue;
                        break;
                    case EXIF_TAG_IFD:
                        // EXIF IFD offset tag
                        exifIFDOffset = tagValue;
                        break;
                    default:
                        break;
                }
            }
            else
            {
                fseek(file, 4, SEEK_CUR);
            }
        }
        
        if (dirOffset == exifIFDOffset)
        {
            break;
        }
        
        if (!READ_UINT32) return CGSizeZero;
        dirOffset = LAST_UINT32;
        
        if (dirOffset == 0)
        {
            dirOffset = exifIFDOffset;
        }
    }
    
    if (width > 0 && height > 0)
    {
        if (orientation >= 5 && orientation <= 8)
        {
            return (CGSize){height, width};
        }
        else
        {
            return (CGSize){width, height};
        }
    }
    
    return CGSizeZero;
}

+ (CGSize)sizeOfImageFileAtPath_JPEG:(FILE *)file
{
    uint8_t buffer[4];
    
    while (fread(buffer, 1, 2, file) == 2 && buffer[0] == 0xFF &&
           ((buffer[1] >= 0xE0 && buffer[1] <= 0xEF) ||
            buffer[1] == 0xDB ||
            buffer[1] == 0xC4 || buffer[1] == 0xC2 ||
            buffer[1] == 0xC0))
    {
        if (buffer[1] == 0xE1)
        { // Parse APP1 EXIF
            
            // Marker segment length
            
            if (fread(buffer, 1, 2, file) != 2) return CGSizeZero;
            // int blockLength = ((buffer[0] << 8) | buffer[1]) - 2;
            
            // Exif
            if (fread(buffer, 1, 4, file) != 4 ||
                memcmp(buffer, JPEG_EXIF_HEADER, 4) != 0) return CGSizeZero;
            
            // Read Byte alignment offset
            if (fread(buffer, 1, 2, file) != 2 ||
                buffer[0] != 0x00 || buffer[1] != 0x00) return CGSizeZero;
            
            CGSize size = [self sizeOfImageFileAtPath_EXIF:file];
            if (size.width >= 0 && size.height >= 0)
            {
                return size;
            }
        }
        else if (buffer[1] == 0xC0 || buffer[1] == 0xC2)
        { // Parse SOF0 (Start of Frame, Baseline DCT or Progressive DCT)
            
            // Skip LF, P
            if (fseek(file, 3, SEEK_CUR)) return CGSizeZero;
            
            // Read Y,X
            if (fread(buffer, 1, 4, file) != 4) return CGSizeZero;
            
            return (CGSize){buffer[2] << 8 | buffer[3], buffer[0] << 8 | buffer[1]};
        }
        else
        { // Skip APPn segment
            if (fread(buffer, 1, 2, file) == 2)
            { // Marker segment length
                fseek(file, (int)((buffer[0] << 8) | buffer[1]) - 2, SEEK_CUR);
            }
            else
            {
                return CGSizeZero;
            }
        }
    }
    
    return CGSizeZero;
}

#pragma mark - ICNS

/*!
 @author David W. Stockton
 @brief
 Code below based on the description at:
 http://en.wikipedia.org/wiki/Apple_Icon_Image_format
 */

typedef struct {
    char osType[5];
    int width;
    int height;
} appleIconInfo;

static appleIconInfo appleIconInfoTable[] = {
    //	OSType	Width, Height		// Length	Size	Supported OS Version	Description
    //					  (bytes)	(pixels)
    { "ICON", 32, 32 },		// 128		32	1.0	32ֳ—32 1-bit mono icon
    { "ICN#", 32, 32 },		// 256		32	6.0	32ֳ—32 1-bit mono icon with 1-bit mask
    { "icm#", 16, 12 },		// 48		16	6.0	16ֳ—12 1 bit mono icon with 1-bit mask
    { "icm4", 16, 12 },		// 96		16	7.0	16ֳ—12 4 bit icon
    { "icm8", 16, 12 },		// 192		16	7.0	16ֳ—12 8 bit icon
    { "ics#", 16, 16 },		// 64 (32 img + 32 mask) 16	6.0	16ֳ—16 1-bit mask
    { "ics4", 16, 16 },		// 128		16	7.0	16ֳ—16 4-bit icon
    { "ics8", 16, 16 },		// 256		16	7.0	16x16 8 bit icon
    { "is32", 16, 16 },		// varies (768)	16	8.5	16ֳ—16 24-bit icon
    { "s8mk", 16, 16 },		// 256		16	8.5	16x16 8-bit mask
    { "icl4", 32, 32 },		// 512		32	7.0	32ֳ—32 4-bit icon
    { "icl8", 32, 32 },		// 1,024	32	7.0	32ֳ—32 8-bit icon
    { "il32", 32, 32 },		// varies (3,072) 32	8.5	32x32 24-bit icon
    { "l8mk", 32, 32 },		// 1,024	32	8.5	32ֳ—32 8-bit mask
    { "ich#", 48, 48 },		// 288		48	8.5	48ֳ—48 1-bit mask
    { "ich4", 48, 48 },		// 1,152	48	8.5	48ֳ—48 4-bit icon
    { "ich8", 48, 48 },		// 2,304	48	8.5	48ֳ—48 8-bit icon
    { "ih32", 48, 48 },		// varies (6,912) 48	8.5	48ֳ—48 24-bit icon
    { "h8mk", 48, 48 },		// 2,304	48	8.5	48ֳ—48 8-bit mask
    { "it32", 128, 128 },	// varies (49,152) 128	10.0	128ֳ—128 24-bit icon
    { "t8mk", 128, 128 },	// 16,384	128	10.0	128ֳ—128 8-bit mask
    { "icp4", 16, 16 },		// varies	16	10.7	16x16 icon in JPEG 2000 or PNG format
    { "icp5", 32, 32 },		// varies	32	10.7	32x32 icon in JPEG 2000 or PNG format
    { "icp6", 64, 64 },		// varies	64	10.7	64x64 icon in JPEG 2000 or PNG format
    { "ic07", 128, 128 },	// varies	128	10.7	128x128 icon in JPEG 2000 or PNG format
    { "ic08", 256, 256 },	// varies	256	10.5	256ֳ—256 icon in JPEG 2000 or PNG format
    { "ic09", 512, 512 },	// varies	512	10.5	512ֳ—512 icon in JPEG 2000 or PNG format
    { "ic10", 1024, 1024 },	// varies	1024	10.7	1024ֳ—1024 in 10.7 (or 512x512@2x "retina" in 10.8) icon in JPEG 2000 or PNG format
    { "ic11", 32, 32 },		// varies	32	10.8	16x16@2x "retina" icon in JPEG 2000 or PNG format
    { "ic12", 64, 64 },		// varies	64	10.8	32x32@2x "retina" icon in JPEG 2000 or PNG format
    { "ic13", 256, 256 },	// varies	256	10.8	128x128@2x "retina" icon in JPEG 2000 or PNG format
    { "ic14", 512, 512 },	// varies	512	10.8	256x256@2x "retina" icon in JPEG 2000 or PNG format
    { "----", 0, 0 },		// end marker for search failure
};

+ (CGSize)sizeOfImageFileAtPath_ICNS:(FILE *)file
{
    CGSize size = CGSizeZero;
    bool littleEndian = false;
    uint8_t buffer[4];
    
    // Attempt to read ICNS header
    // Read ICNS magic number (always "icns")
    if (fread(buffer, 1, 4, file) != 4 ||
        memcmp(buffer, ICNS_HEADER, 4) != 0)
    {
        return CGSizeZero;
    }
    
    // Read the length of the file in bytes
    if (!READ_UINT32) return CGSizeZero;
    uint32_t fileSize = LAST_UINT32;
    
    uint32_t dataLength = 0;
    uint32_t filepos = 8;
    int width = 0;
    int height = 0;
    int i;
    
    do
    {
        // Read the icon type
        if (!READ_UINT32) return CGSizeZero;
        char iconType[5];
        memcpy(iconType, buffer, 4);
        iconType[4] = '\0';
        
        // Read the Length of data, in bytes (including type and length), msb first
        if (!READ_UINT32) return CGSizeZero;
        dataLength = LAST_UINT32;
        
        for (i = 0; appleIconInfoTable[i].width > 0; ++i)
        {
            if (strcmp(iconType, appleIconInfoTable[i].osType) == 0)
            {
                if (appleIconInfoTable[i].width > width)
                {
                    width = appleIconInfoTable[i].width;
                }
                if (appleIconInfoTable[i].height > height)
                {
                    height = appleIconInfoTable[i].height;
                }
                break;
            }
        }
        
        if (appleIconInfoTable[i].width <= 0 &&
            strcmp(iconType, "icnV") != 0 &&
            strcmp(iconType, "TOC ") != 0)
        {
            NSLog(@"sizeOfImageFileAtPath_ICNS failed: OSType '%s' not found in the table", iconType);
        }
        
        filepos += dataLength;
    } while (filepos < fileSize && fseek(file, dataLength - 8, SEEK_CUR) == 0);
    
    if (width > 0 && height > 0)
    {
        size = CGSizeMake( (CGFloat) width, (CGFloat) height );
    }
    return size;
}

@end
