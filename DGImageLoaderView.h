//
//  DGImageLoaderView.h
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

#import <UIKit/UIKit.h>

typedef enum _DGImageLoaderViewAnimationType
{
	DGImageLoaderViewAnimationTypeNone = 0,
	DGImageLoaderViewAnimationTypeFade = 1
} DGImageLoaderViewAnimationType;

typedef enum _DGImageLoaderViewCropAnchor
{
	DGImageLoaderViewCropAnchorCenterCenter,
	DGImageLoaderViewCropAnchorCenterLeft,
	DGImageLoaderViewCropAnchorCenterRight,
	DGImageLoaderViewCropAnchorTopCenter,
	DGImageLoaderViewCropAnchorTopLeft,
    DGImageLoaderViewCropAnchorTopRight,
    DGImageLoaderViewCropAnchorBottomCenter,
    DGImageLoaderViewCropAnchorBottomLeft,
    DGImageLoaderViewCropAnchorBottomRight
} DGImageLoaderViewCropAnchor;

typedef enum _DGImageLoaderViewLandscapeMode
{
	DGImageLoaderViewLandscapeModeNone,
	DGImageLoaderViewLandscapeModeLeft,
	DGImageLoaderViewLandscapeModeRight
} DGImageLoaderViewLandscapeMode;

IB_DESIGNABLE
@interface DGImageLoaderView : UIView <NSURLConnectionDelegate>

/*! @property hasImageLoaded
    @brief Do we have an image loaded? */
@property (nonatomic, assign, readonly) BOOL hasImageLoaded;

/*! @property defaultImage
    @brief Default image to use when not loaded or after calling reset
    Default: nil
 */
@property (nonatomic, strong) IBInspectable UIImage * _Nullable defaultImage;

/*! @property noCache
 @brief Should we skip local caching?
 Default: NO */
@property (nonatomic, assign) IBInspectable BOOL noCache;

/*! @property defaultImageEnlarge
    @brief Should we enlarge the image if it's smaller than the view?
    Default: NO */
@property (nonatomic, assign) IBInspectable BOOL defaultImageEnlarge;

/*! @property keepAspectRatio
    @brief Should we keep the aspect ration when resizing the image?
    Default: YES
 */
@property (nonatomic, assign) IBInspectable BOOL keepAspectRatio;

/*! @property fitFromOutside
    @brief Should we fit the image from ouside of the bounds of the UIView, so there are not blanks inside?
    Default: NO
 */
@property (nonatomic, assign) IBInspectable BOOL fitFromOutside;

/*! @property enlargeImage
    @brief Should we enlarge the image if it's smaller than the view?
        This does not affect the defaultImage
    Default: YES
 */
@property (nonatomic, assign) IBInspectable BOOL enlargeImage;

/*! @property cropAnchor
    @brief If fitFromOutside is set, this property determines which part you want to be most visible in the image. Or more precisely, which part of the image you want to "crop" to the required size.
    Default: DGImageLoaderViewCropAnchorCenterCenter
 */
@property (nonatomic, assign) DGImageLoaderViewCropAnchor cropAnchor;

/*! @property animationDuration
    @brief The duration of the animation (if there's an animation chosen for displaying the image). Specified in seconds.
    Default: 0.8
 */
@property (nonatomic, assign) float animationDuration;

/*! @property currentVisibleImage
    @brief The currently loaded image, including the default image if loaded. */
@property (nonatomic, strong, readonly) UIImage * _Nullable currentVisibleImage;

/*! @property currentVisibleImageNotDefault
    @brief The currently loaded image, but returning nil if the default image is loaded */
@property (nonatomic, strong, readonly) UIImage * _Nullable currentVisibleImageNotDefault;

/*! @property doNotAnimateFromCache
    @brief Will not animate when loaded completely from cache, and no extra work has to be done.
    Default: NO */
@property (nonatomic, assign) IBInspectable BOOL doNotAnimateFromCache;

/*! @property delayActualLoadUntilDisplay
    @brief Delay the loading from network to the first time that drawRect: is requested.
    This is useful for example when you have a circular gallery with 20 images and you want the first image to load fast, and the others to load only if the user scrolls to them, so you gain good UX and you do not use extra bandwidth that is not needed.
    Default: NO */
@property (nonatomic, assign) IBInspectable BOOL delayActualLoadUntilDisplay;

/*! @property delayImageShowUntilDisplay
    @brief Delay actual showing (or animation) to the first time that drawRect: is requested.
    This prevents extra work for when you have many off-screen images.
    This also causes the Fade animation, if chosen, to always be visible and not happen when off-screen, so you can always achieve that nice effect.
    Default: YES */
@property (nonatomic, assign) IBInspectable BOOL delayImageShowUntilDisplay;

/*! @property asyncLoadImages
    @brief Do the image loading (reading or writing to cached files) on a separate queue.
    Default: YES */
@property (nonatomic, assign) IBInspectable BOOL asyncLoadImages;

/*! @property resizeImages
    @brief Post process images to resize to requested size.
    Disable this if images are known to always come in the correct size.
    Default: YES */
@property (nonatomic, assign) IBInspectable BOOL resizeImages;

/*! @property detectScaleFromFileName
    @brief Set this to YES if you want to specify urls that contain the @2x for scale. Otherwise, scale will be set according to current screen.
    Default: YES */
@property (nonatomic, assign) IBInspectable BOOL detectScaleFromFileName;

/*! @property autoFindScaledUrlForFileUrls
    @brief If set to YES, then the behavior is similar to UIImage - looking for an @2x version of the file first if exists.
    Default: YES */
@property (nonatomic, assign) IBInspectable BOOL autoFindScaledUrlForFileUrls;

/*! @property landscapeMode
    @brief If set, will automatically rotate landscape images.
    Default: DGImageLoaderViewLandscapeModeNone */
@property (nonatomic, assign) DGImageLoaderViewLandscapeMode landscapeMode;

/*! @property onImageSizeKnown
 @brief When the size of an image is finally known (i.e. after loading from the web),
 This is a chance to resize the view to match whatever relation to the image you want. */
@property (nonatomic, strong) void (^ _Nullable onImageSizeKnown)(CGSize size);

/*! @property onError
 @brief When we failed to load the image. */
@property (nonatomic, strong) void (^ _Nullable onError)(void);

/*! @property imageBounds
 @brief If either `width` or `height` are specified (!= 0.0), `imageBounds` will behave as an alternative to `bounds` in determinining image outer box.
 Default: {0.0, 0.0} */
@property (nonatomic, assign) IBInspectable CGSize imageBounds;

/*! @property enableIntrinsicContentSize
 @brief If `true` and `imageBounds` has at least one value - then intrinsic content size will be automatically calculated.
 Default: NO */
@property (nonatomic, assign) IBInspectable BOOL enableIntrinsicContentSize;

/*! Load the image from an URL
    @param url  The URL of the image to load
    @param animationType  The kind of animation to use when displaying the image. */
- (void)loadImageFromURL:(NSURL * _Nullable)url
        andAnimationType:(DGImageLoaderViewAnimationType)animationType;

/*! Load the image from an URL
    @param url  The URL of the image to load
    @param animationType  The kind of animation to use when displaying the image.
    @param immediate  If set to YES, will override any delaying of loading or displaying, and will immediately load and display the image. */
- (void)loadImageFromURL:(NSURL * _Nullable)url
        andAnimationType:(DGImageLoaderViewAnimationType)animationType immediate:(BOOL)immediate;

/*! Load the image from an URL
    @param url  The URL of the image to load
    @param headers  Headers for the request
    @param animationType  The kind of animation to use when displaying the image. */
- (void)loadImageFromURL:(NSURL * _Nullable)url
                 headers:(NSDictionary * _Nullable)headers
           animationType:(DGImageLoaderViewAnimationType)animationType;

/*! Load the image from an URL
    @param url  The URL of the image to load
    @param headers  Headers for the request
    @param animationType  The kind of animation to use when displaying the image.
    @param immediate  If set to YES, will override any delaying of loading or displaying, and will immediately load and display the image. */
- (void)loadImageFromURL:(NSURL * _Nullable)url
                 headers:(NSDictionary * _Nullable)headers
           animationType:(DGImageLoaderViewAnimationType)animationType
               immediate:(BOOL)immediate;

/*! Load the image from an UIImage
    This is useful when you want to use the "resize" feature on an available UIImage
    @param animationType  The kind of animation to use when displaying the image. */
- (void)loadImage:(UIImage * _Nullable)image
withAnimationType:(DGImageLoaderViewAnimationType)animationType;

/*! Stops any loading of image in progress */
- (void)stop;

/*! Stops any loading of image in progress, and resets to the defaultImage if present */
- (void)reset;

/*! Remove a specific URL from the cache
 @param url  The URL of the image to clear
 @return count of cache files deleted */
+ (int)removeImageFromCache:(NSURL * _Nullable)url;

/*! Removes all images and thumbnails from cache */
+ (void)clearCache;

/*! Get url for the full-size cached version of the supplied image url.
 This function does not guarantee that the file exists locally; But it would exist if the loadedr has finished downloading.
 The path is derived based on the settings of the class, mainly detectScaleFromFileName
 @param url  Source image url
 @return The URL of the cached image */
- (NSString * _Nullable)localCachePathForUrl:(NSURL * _Nullable)url;

/*! Get url for the thumbnail cached version of the supplied image url.
 This function does not guarantee that the file exists locally; But it would exist if the loadedr has finished downloading.
 The path is derived based on the settings of the class, mainly detectScaleFromFileName
 @param url  Source image url
 @param thumbnailSize  Thumbnail size
 @return The URL of the cached image */
- (NSString * _Nullable)localCachePathForUrl:(NSURL * _Nullable)url
                 withThumbnailSize:(CGSize)thumbnailSize;

/*! Maximum asynchronous connections that can be used to load images.
    This affects this class overall in the app.
    The default is 8.
    @return The max connections */
+ (NSUInteger)maxAsyncConnections;

/*! Maximum asynchronous connections that can be used to load images
    @param int The max connections */
+ (void)setMaxAsyncConnections:(NSUInteger)max;

/*! Current active connections used by this class overall in the app
    @param int The active connections count */
+ (NSUInteger)activeConnections;

/*! Total connections which include active + pending connections, used by this class overall in the app
    @param int The total connections count */
+ (NSUInteger)totalConnections;

@end
