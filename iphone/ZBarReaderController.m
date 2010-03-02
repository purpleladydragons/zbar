//------------------------------------------------------------------------
//  Copyright 2009 (c) Jeff Brown <spadix@users.sourceforge.net>
//
//  This file is part of the ZBar Bar Code Reader.
//
//  The ZBar Bar Code Reader is free software; you can redistribute it
//  and/or modify it under the terms of the GNU Lesser Public License as
//  published by the Free Software Foundation; either version 2.1 of
//  the License, or (at your option) any later version.
//
//  The ZBar Bar Code Reader is distributed in the hope that it will be
//  useful, but WITHOUT ANY WARRANTY; without even the implied warranty
//  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser Public License for more details.
//
//  You should have received a copy of the GNU Lesser Public License
//  along with the ZBar Bar Code Reader; if not, write to the Free
//  Software Foundation, Inc., 51 Franklin St, Fifth Floor,
//  Boston, MA  02110-1301  USA
//
//  http://sourceforge.net/projects/zbar
//------------------------------------------------------------------------

#import <zbar/ZBarReaderController.h>
#import "ZBarHelpController.h"
#import "debug.h"

#ifndef MIN_QUALITY
# define MIN_QUALITY 10
#endif

NSString* const ZBarReaderControllerResults = @"ZBarReaderControllerResults";

// expose undocumented API
CGImageRef UIGetScreenImage(void);

@implementation ZBarReaderController

@synthesize scanner, readerDelegate, cameraMode, scanCrop, maxScanDimension,
    showsHelpOnFail, takesPicture, enableCache;
@dynamic showsZBarControls;

- (id) init
{
    if(self = [super init]) {
        showsHelpOnFail = YES;
        hasOverlay = showsZBarControls =
            [self respondsToSelector: @selector(cameraOverlayView)];
        enableCache = YES;
        scanCrop = CGRectMake(0, 0, 1, 1);
        maxScanDimension = 640;

        scanner = [ZBarImageScanner new];
        [scanner setSymbology: 0
                 config: ZBAR_CFG_X_DENSITY
                 to: 2];
        [scanner setSymbology: 0
                 config: ZBAR_CFG_Y_DENSITY
                 to: 2];

        if([UIImagePickerController
               isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera])
            self.sourceType = UIImagePickerControllerSourceTypeCamera;
        cameraMode = ZBarReaderControllerCameraModeSampling;
    }
    return(self);
}

- (void) showHelpOverlay
{
    if(!help) {
        help = [[ZBarHelpController alloc]
                   initWithTitle: @"Barcode Reader"];
        help.delegate = self;
    }
    help.wantsFullScreenLayout = YES;
    help.view.alpha = 0;
    [[self cameraOverlayView] addSubview: help.view];
    [UIView beginAnimations: @"ZBarHelp"
            context: nil];
    help.view.alpha = 1;
    [UIView commitAnimations];
}

- (void) initOverlay
{
    CGRect bounds = self.view.bounds;
    overlay = [[UIView alloc] initWithFrame: bounds];
    overlay.backgroundColor = [UIColor clearColor];

    CGRect r = bounds;
    r.size.height -= 54;
    boxView = [[UIView alloc] initWithFrame: r];

    boxLayer = [CALayer new];
    boxLayer.frame = r;
    boxLayer.borderWidth = 1;
    boxLayer.borderColor = [UIColor greenColor].CGColor;
    [boxView.layer addSublayer: boxLayer];

    toolbar = [UIToolbar new];
    toolbar.barStyle = UIBarStyleBlackOpaque;
    r.origin.y = r.size.height;
    r.size.height = 54;
    toolbar.frame = r;

    cancelBtn = [[UIBarButtonItem alloc]
                    initWithBarButtonSystemItem: UIBarButtonSystemItemCancel
                    target: self
                    action: @selector(cancel)];
    cancelBtn.width = r.size.width / 4 - 16;

    scanBtn = [[UIBarButtonItem alloc]
                  initWithTitle: @"Scan!"
                  style: UIBarButtonItemStyleDone
                  target: self
                  action: @selector(scan)];
    scanBtn.width = r.size.width / 2 - 16;

    for(int i = 0; i < 2; i++)
        space[i] = [[UIBarButtonItem alloc]
                       initWithBarButtonSystemItem:
                           UIBarButtonSystemItemFlexibleSpace
                       target: nil
                       action: nil];

    space[2] = [[UIBarButtonItem alloc]
                    initWithBarButtonSystemItem:
                        UIBarButtonSystemItemFixedSpace
                    target: nil
                    action: nil];
    space[2].width = r.size.width / 4 - 16;

    infoBtn = [[UIButton buttonWithType: UIButtonTypeInfoLight] retain];
    r.origin.x = r.size.width - 54;
    r.size.width = 54;
    infoBtn.frame = r;
    [infoBtn addTarget: self
             action: @selector(showHelpOverlay)
             forControlEvents: UIControlEventTouchUpInside];
}

- (void) viewDidLoad
{
    [super viewDidLoad];
    [super setDelegate: self];
    if(hasOverlay)
        [self initOverlay];
}

- (void) cleanup
{
    [overlay release];
    overlay = nil;
    [boxView release];
    boxView = nil;
    [boxLayer release];
    boxLayer = nil;
    [toolbar release];
    toolbar = nil;
    [cancelBtn release];
    cancelBtn = nil;
    [scanBtn release];
    scanBtn = nil;
    for(int i = 0; i < 3; i++) {
        [space[i] release];
        space[i] = nil;
    }
    [infoBtn release];
    infoBtn = nil;
    [help release];
    help = nil;
}

- (void) viewDidUnload
{
    [self cleanup];
    [super viewDidUnload];
}

- (void) dealloc
{
    [self cleanup];
    [scanner release];
    scanner = nil;
    [super dealloc];
}

- (void) scan
{
    scanBtn.enabled = NO;
    self.view.userInteractionEnabled = NO;
    [self takePicture];
}

- (void) cancel
{
    [self performSelector: @selector(imagePickerControllerDidCancel:)
          withObject: self
          afterDelay: 0.1];
}

- (void) reenable
{
    scanBtn.enabled = YES;
    self.view.userInteractionEnabled = YES;
}

- (void) viewWillAppear: (BOOL) animated
{
    if(help) {
        [help.view removeFromSuperview];
        [help release];
        help = nil;
    }

    if(hasOverlay &&
       self.sourceType == UIImagePickerControllerSourceTypeCamera) {
        if(showsZBarControls || ![self cameraOverlayView])
            [self setCameraOverlayView: overlay];

        UIView *activeOverlay = [self cameraOverlayView];

        if(showsZBarControls) {
            if(!toolbar.superview) {
                [overlay addSubview: toolbar];
                [overlay addSubview: infoBtn];
            }
            [self setShowsCameraControls: NO];
        }
        else {
            [toolbar removeFromSuperview];
            [infoBtn removeFromSuperview];
            if(activeOverlay == overlay)
                [self setShowsCameraControls: YES];
        }

        self.view.userInteractionEnabled = YES;

        sampling = (cameraMode == ZBarReaderControllerCameraModeSampling ||
                    cameraMode == ZBarReaderControllerCameraModeSequence);

        if(sampling) {
            toolbar.items = [NSArray arrayWithObjects:
                                cancelBtn, space[0], nil];

            t_frame = timer_now();
            dt_frame = 0;
            boxLayer.opacity = 0;
            if(boxView.superview != activeOverlay)
                [boxView removeFromSuperview];
            if(!boxView.superview)
                [activeOverlay insertSubview: boxView atIndex:0];
            scanner.enableCache = enableCache;

            SEL meth = nil;
            if(cameraMode == ZBarReaderControllerCameraModeSampling) {
                // ensure crop rect does not include controls
                if(scanCrop.origin.x + scanCrop.size.width > .8875)
                    scanCrop.size.width = .8875 - scanCrop.origin.x;

                meth = @selector(scanScreen);
            }
            else
                meth = @selector(takePicture);

            [self performSelector: meth
                  withObject: nil
                  afterDelay: 2];
#ifdef DEBUG_OBJC
            [self performSelector: @selector(dumpFPS)
                  withObject: nil
                  afterDelay: 4];
#endif
        }
        else {
            scanBtn.enabled = NO;
            toolbar.items = [NSArray arrayWithObjects:
                        cancelBtn, space[0], scanBtn, space[1], space[2], nil];

            [self performSelector: @selector(reenable)
                  withObject: nil
                  afterDelay: .5];

            [boxView removeFromSuperview];
        }
    }

    [super viewWillAppear: animated];
}

- (void) viewWillDisappear: (BOOL) animated
{
    sampling = NO;
    scanner.enableCache = NO;
    [super viewWillDisappear: animated];
}


- (BOOL) showsZBarControls
{
    return(showsZBarControls);
}

- (void) setShowsZBarControls: (BOOL) show
{
    if(show && !hasOverlay)
        [NSException raise: NSInvalidArgumentException
            format: @"ZBarReaderController cannot set showsZBarControls=YES for OS<3.1"];

    showsZBarControls = show;
}

// intercept delegate as readerDelegate

- (void) setDelegate: (id <UINavigationControllerDelegate,
                           UIImagePickerControllerDelegate>) delegate
{
    self.readerDelegate = (id <ZBarReaderDelegate>)delegate;
}


#ifdef DEBUG_OBJC
- (void) dumpFPS
{
    if(!sampling)
        return;
    [self performSelector: @selector(dumpFPS)
          withObject: nil
          afterDelay: 2];
    zlog(@"fps=%g", 1 / dt_frame);
}
#endif

- (NSInteger) scanImage: (CGImageRef) image
            withScaling: (CGFloat) scale
{
    uint64_t now = timer_now();
    if(dt_frame)
        dt_frame = (dt_frame + timer_elapsed(t_frame, now)) / 2;
    else
        dt_frame = timer_elapsed(t_frame, now);
    t_frame = now;

    int w = CGImageGetWidth(image);
    int h = CGImageGetHeight(image);
    CGRect crop;
    if(w >= h)
        crop = CGRectMake(scanCrop.origin.x * w, scanCrop.origin.y * h,
                          scanCrop.size.width * w, scanCrop.size.height * h);
    else
        crop = CGRectMake(scanCrop.origin.y * w, scanCrop.origin.x * h,
                          scanCrop.size.height * w, scanCrop.size.width * h);

    CGSize size;
    if(crop.size.width >= crop.size.height &&
       crop.size.width > maxScanDimension)
        size = CGSizeMake(maxScanDimension,
                          crop.size.height * maxScanDimension / crop.size.width);
    else if(crop.size.height > maxScanDimension)
        size = CGSizeMake(crop.size.width * maxScanDimension / crop.size.height,
                          maxScanDimension);
    else
        size = crop.size;

    if(scale) {
        size.width *= scale;
        size.height *= scale;
    }

    if(self.sourceType != UIImagePickerControllerSourceTypeCamera ||
       cameraMode == ZBarReaderControllerCameraModeDefault) {
        // limit the maximum number of scan passes
        int density;
        if(size.width > 720)
            density = (size.width / 240 + 1) / 2;
        else
            density = 1;
        [scanner setSymbology: 0
                 config: ZBAR_CFG_X_DENSITY
                 to: density];

        if(size.height > 720)
            density = (size.height / 240 + 1) / 2;
        else
            density = 1;
        [scanner setSymbology: 0
                 config: ZBAR_CFG_Y_DENSITY
                 to: density];
    }

    ZBarImage *zimg = [[ZBarImage alloc]
                          initWithCGImage: image
                          crop: crop
                          size: size];
    int nsyms = [scanner scanImage: zimg];
    [zimg release];

    return(nsyms);
}

- (ZBarSymbol*) extractBestResult: (BOOL) filter
{
    ZBarSymbol *sym = nil;
    ZBarSymbolSet *results = scanner.results;
    results.filterSymbols = filter;
    for(ZBarSymbol *s in results)
        if(!sym || sym.quality < s.quality)
            sym = s;
    return(sym);
}

- (void) updateBox: (ZBarSymbol*) sym
{
    [CATransaction begin];
    [CATransaction setAnimationDuration: .3];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:
            kCAMediaTimingFunctionLinear]];

    CGFloat alpha = boxLayer.opacity;
    if(sym) {
        CGRect r = sym.bounds;
        // FIXME reverse image scaling
        //r = crop.origin + ;
        if(r.size.width > 16 && r.size.height > 16) {
            r = CGRectInset(r, -16, -16);
            if(alpha > .25) {
                CGRect frame = boxLayer.frame;
                r.origin.x = (r.origin.x * 3 + frame.origin.x) / 4;
                r.origin.y = (r.origin.y * 3 + frame.origin.y) / 4;
                r.size.width = (r.size.width * 3 + frame.size.width) / 4;
                r.size.height = (r.size.height * 3 + frame.size.height) / 4;
            }
            boxLayer.frame = r;
            boxLayer.opacity = 1;
        }
    }
    else {
        if(alpha > .1)
            boxLayer.opacity = alpha / 2;
        else if(alpha)
            boxLayer.opacity = 0;
    }
    [CATransaction commit];
}

- (void) scanScreen
{
    if(!sampling)
        return;

    // FIXME ugly hack: use private API to sample screen
    CGImageRef image = UIGetScreenImage();

    int nsyms = [self scanImage: image
                      withScaling: 0];
    CGImageRelease(image);

    ZBarSymbol *sym = nil;
    if(nsyms)
        sym = [self extractBestResult: NO];

    if(sym && !sym.count) {
        SEL cb = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
        if(takesPicture) {
            symbol = [sym retain];
            [self takePicture];
        }
        else if([readerDelegate respondsToSelector: cb]) {
            symbol = [sym retain];

            [CATransaction begin];
            [CATransaction setDisableActions: YES];
            boxLayer.opacity = 0;
            [CATransaction commit];

            // capture preview image and send to delegate
            // after box has been hidden
            [self performSelector: @selector(captureScreen)
                  withObject: nil
                  afterDelay: 0.001];
            return;
        }
    }

    // reschedule
    [self performSelector: @selector(scanScreen)
          withObject: nil
          afterDelay: 0.001];

    [self updateBox: sym];
}

- (void) captureScreen
{
    CGImageRef screen = UIGetScreenImage();
    CGRect r = CGRectMake(0, 0,
                          CGImageGetWidth(screen), CGImageGetHeight(screen));
    if(r.size.width > r.size.height)
        r.size.width -= 54;
    else
        r.size.height -= 54;
    CGImageRef preview = CGImageCreateWithImageInRect(screen, r);
    CGImageRelease(screen);

    UIImage *image = [UIImage imageWithCGImage: preview];
    CGImageRelease(preview);

    [readerDelegate
        imagePickerController: self
        didFinishPickingMediaWithInfo:
            [NSDictionary dictionaryWithObjectsAndKeys:
                image, UIImagePickerControllerOriginalImage,
                [NSArray arrayWithObject: symbol],
                    ZBarReaderControllerResults,
                nil]];
    [symbol release];
    symbol = nil;

    // continue scanning until dismissed
    [self performSelector: @selector(scanScreen)
          withObject: nil
          afterDelay: 0.001];
}

- (void) scanSequence: (UIImage*) image
{
    if(!sampling) {
        [image release];
        return;
    }

    int nsyms = [self scanImage: image.CGImage
                      withScaling: 0];

    ZBarSymbol *sym = nil;
    if(nsyms)
        sym = [self extractBestResult: NO];

    SEL cb = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
    if(sym && !sym.count &&
       [readerDelegate respondsToSelector: cb])
        [readerDelegate
            imagePickerController: self
            didFinishPickingMediaWithInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:
                    image, UIImagePickerControllerOriginalImage,
                    [NSArray arrayWithObject: sym],
                        ZBarReaderControllerResults,
                    nil]];
    [image release];

    // reschedule
    [self performSelector: @selector(takePicture)
          withObject: nil
          afterDelay: 0.001];

    [self updateBox: sym];
}

- (void)  imagePickerController: (UIImagePickerController*) picker
  didFinishPickingMediaWithInfo: (NSDictionary*) info
{
    UIImage *img = [info objectForKey: UIImagePickerControllerOriginalImage];

    id results = nil;
    if(!sampling)
        results = [self scanImage: img.CGImage];
    else if(cameraMode == ZBarReaderControllerCameraModeSampling) {
        results = [NSArray arrayWithObject: symbol];
        [symbol release];
        symbol = nil;
    }
    else {
        [self performSelector: @selector(scanSequence:)
              withObject: [img retain]
              afterDelay: 0.001];
        return;
    }

    [self performSelector: @selector(reenable)
         withObject: nil
         afterDelay: .25];

    if(results) {
        NSMutableDictionary *newinfo = [info mutableCopy];
        [newinfo setObject: results
                 forKey: ZBarReaderControllerResults];
        SEL cb = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
        if([readerDelegate respondsToSelector: cb])
            [readerDelegate imagePickerController: self
                            didFinishPickingMediaWithInfo: newinfo];
        else
            [self dismissModalViewControllerAnimated: YES];
        [newinfo release];
        return;
    }

    BOOL camera = (self.sourceType == UIImagePickerControllerSourceTypeCamera);
    BOOL retry = !camera || (hasOverlay && ![self showsCameraControls]);
    if(showsHelpOnFail && retry) {
        help = [[ZBarHelpController alloc]
                   initWithTitle: @"No Barcode Found"];
        help.delegate = self;
        if(camera)
            [self showHelpOverlay];
        else
            [self presentModalViewController: help
                  animated: YES];
    }

    SEL cb = @selector(readerControllerDidFailToRead:withRetry:);
    if([readerDelegate respondsToSelector: cb])
        // assume delegate dismisses controller if necessary
        [readerDelegate readerControllerDidFailToRead: self
                        withRetry: retry];
    else if(!retry)
        // must dismiss stock controller
        [self dismissModalViewControllerAnimated: YES];
}

- (void) imagePickerControllerDidCancel: (UIImagePickerController*) picker
{
    SEL cb = @selector(imagePickerControllerDidCancel:);
    if([readerDelegate respondsToSelector: cb])
        [readerDelegate imagePickerControllerDidCancel: self];
    else
        [self dismissModalViewControllerAnimated: YES];
}

- (void) helpController: (ZBarHelpController*) hlp
   clickedButtonAtIndex: (NSInteger) idx
{
    if(self.sourceType == UIImagePickerControllerSourceTypeCamera) {
        [UIView beginAnimations: @"ZBarHelp"
                context: nil];
        hlp.view.alpha = 0;
        [UIView commitAnimations];
    }
    else
        [hlp dismissModalViewControllerAnimated: YES];
}

- (id <NSFastEnumeration>) scanImage: (CGImageRef) image
{
    timer_start;

    int nsyms = [self scanImage: image
                      withScaling: 0];

    if(!nsyms &&
       CGImageGetWidth(image) >= 640 &&
       CGImageGetHeight(image) >= 640)
        // make one more attempt for close up, grainy images
        nsyms = [self scanImage: image
                      withScaling: .5];

    NSMutableArray *syms = nil;
    if(nsyms) {
        // quality/type filtering
        int max_quality = MIN_QUALITY;
        for(ZBarSymbol *sym in scanner.results) {
            zbar_symbol_type_t type = sym.type;
            int quality;
            if(type == ZBAR_QRCODE)
                quality = INT_MAX;
            else
                quality = sym.quality;

            if(quality < max_quality) {
                zlog(@"    type=%d quality=%d < %d\n",
                     type, quality, max_quality);
                continue;
            }

            if(max_quality < quality) {
                max_quality = quality;
                if(syms)
                    [syms removeAllObjects];
            }
            zlog(@"    type=%d quality=%d\n", type, quality);
            if(!syms)
                syms = [NSMutableArray arrayWithCapacity: 1];

            [syms addObject: sym];
        }
    }

    zlog(@"read %d filtered symbols in %gs total\n",
          (!syms) ? 0 : [syms count], timer_elapsed(t_start, timer_now()));
    return(syms);
}

@end
