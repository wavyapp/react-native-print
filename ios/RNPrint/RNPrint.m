
//  Created by Alex Levy on 16 May 19.

#import "RNPrint.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

@implementation RNPrint

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE();

-(void)launchPrint:(NSData *) data
        resolver:(RCTPromiseResolveBlock)resolve
        rejecter:(RCTPromiseRejectBlock)reject {
    if(!_htmlString && ![UIPrintInteractionController canPrintData:data]) {
        reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"Unable to print this filePath"));
        return;
    }
    
    UIPrintInteractionController *printInteractionController = [UIPrintInteractionController sharedPrintController];
    printInteractionController.delegate = self;
    
    // Create printing info
    UIPrintInfo *printInfo = [UIPrintInfo printInfo];
    
    printInfo.outputType = UIPrintInfoOutputGeneral;
    printInfo.jobName = [_filePath lastPathComponent];
    printInfo.duplex = UIPrintInfoDuplexLongEdge;
    printInfo.orientation = _isLandscape? UIPrintInfoOrientationLandscape: UIPrintInfoOrientationPortrait;
    
    printInteractionController.printInfo = printInfo;
    printInteractionController.showsPageRange = YES;
    
    if (_htmlString) {
        UIMarkupTextPrintFormatter *formatter = [[UIMarkupTextPrintFormatter alloc] initWithMarkupText:_htmlString];
        printInteractionController.printFormatter = formatter;
    } else {
        printInteractionController.printingItem = data;
    }
    
    // Completion handler
    void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) =
    ^(UIPrintInteractionController *printController, BOOL completed, NSError *error) {
        if (!completed && error) {
            NSLog(@"Printing could not complete because of error: %@", error);
            reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(error.description));
        } else {
            resolve(completed ? printInfo.jobName : nil);
        }
    };
    
    if (_pickedPrinter) {
        [printInteractionController printToPrinter:_pickedPrinter completionHandler:completionHandler];
    } else if([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) { // iPad
        UIView *view = [[UIApplication sharedApplication] keyWindow].rootViewController.view;
        [printInteractionController presentFromRect:view.frame inView:view animated:YES completionHandler:completionHandler];
        // UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
        // while (rootViewController.presentedViewController != nil) {
        //     rootViewController = rootViewController.presentedViewController;
        // }
        // CGRect rect = CGRectMake(rootViewController.view.bounds.size.width/2, rootViewController.view.bounds.size.height/2, 1, 1);
        // [printInteractionController presentFromRect:rect inView:rootViewController.view animated:YES completionHandler:completionHandler];
    } else { // iPhone
        [printInteractionController presentAnimated:YES completionHandler:completionHandler];
    }
}

RCT_EXPORT_METHOD(print:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    if (options[@"filePath"]){
        _filePath = [RCTConvert NSString:options[@"filePath"]];
    } else {
        _filePath = nil;
    }
    
    if (options[@"html"]){
        _htmlString = [RCTConvert NSString:options[@"html"]];
    } else {
        _htmlString = nil;
    }
    
    if (options[@"printerURL"]){
        _printerURL = [NSURL URLWithString:[RCTConvert NSString:options[@"printerURL"]]];
        if (@available(iOS 8.0, *)) {
            _pickedPrinter = [UIPrinter printerWithURL:_printerURL];
        } else {
            // Fallback on earlier versions
        }
    }
    
    if(options[@"isLandscape"]) {
        _isLandscape = [[RCTConvert NSNumber:options[@"isLandscape"]] boolValue];
    }
    
    if ((_filePath && _htmlString) || (_filePath == nil && _htmlString == nil)) {
        reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"Must provide either `html` or `filePath`. Both are either missing or passed together"));
    }
    
    __block NSData *printData;
    BOOL isValidURL = NO;
    NSURL *candidateURL = [NSURL URLWithString: _filePath];
    if (candidateURL && candidateURL.scheme && candidateURL.host)
        isValidURL = YES;
    
    if (isValidURL) {
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *dataTask = [session dataTaskWithURL:[NSURL URLWithString:_filePath] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self launchPrint:data resolver:resolve rejecter:reject];
            });
        }];
        [dataTask resume];
    } else {
        printData = [NSData dataWithContentsOfFile: _filePath];
        [self launchPrint:printData resolver:resolve rejecter:reject];
    }
}

RCT_EXPORT_METHOD(selectPrinter:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    if (@available(iOS 8.0, *)) {
        UIPrinterPickerController *printPicker = [UIPrinterPickerController printerPickerControllerWithInitiallySelectedPrinter: _pickedPrinter];
        
        printPicker.delegate = self;
        
        void (^completionHandler)(UIPrinterPickerController *, BOOL, NSError *) =
        ^(UIPrinterPickerController *printerPicker, BOOL userDidSelect, NSError *error) {
            if (!userDidSelect && error) {
                NSLog(@"Printing could not complete because of error: %@", error);
                reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(error.description));
            } else {
                [UIPrinterPickerController printerPickerControllerWithInitiallySelectedPrinter:printerPicker.selectedPrinter];
                if (userDidSelect) {
                    self->_pickedPrinter = printerPicker.selectedPrinter;
                    NSDictionary *printerDetails = @{
                        @"name" : self->_pickedPrinter.displayName,
                        @"url" : self->_pickedPrinter.URL.absoluteString,
                    };
                    resolve(printerDetails);
                }
            }
        };
        
        if([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) { // iPad
             UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
             while (rootViewController.presentedViewController != nil) {
                 rootViewController = rootViewController.presentedViewController;
             }
            CGFloat _x = rootViewController.view.bounds.size.width/2;
            CGFloat _y = rootViewController.view.bounds.size.height/2;
            CGFloat _width = 1;
            CGFloat _height = 1;
            if (options[@"x"]){
                _x = [RCTConvert CGFloat:options[@"x"]];
            }
            if (options[@"y"]){
                _y = [RCTConvert CGFloat:options[@"y"]];
            }
            if (options[@"width"]){
                _width= [RCTConvert CGFloat:options[@"width"]];
            }
            if (options[@"height"]){
                _height = [RCTConvert CGFloat:options[@"height"]];
            }
            CGRect rect = CGRectMake(_x, _y, _width, _height);
            if ([printPicker presentFromRect:rect inView:rootViewController.view animated:YES completionHandler:completionHandler]){
                RCTLogInfo(@"selectPrinter -> %@", @"Open");
            } else {
                RCTLogInfo(@"selectPrinter -> %@", @"Error open");
            }
        } else { // iPhone
            [printPicker presentAnimated:YES completionHandler:completionHandler];
        }
    } else {
        // Fallback on earlier versions
    }
}

#pragma mark - UIPrintInteractionControllerDelegate

-(UIViewController*)printInteractionControllerParentViewController:(UIPrintInteractionController*)printInteractionController  {
    UIViewController *result = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (result.presentedViewController) {
        result = result.presentedViewController;
    }
    return result;
}

-(void)printInteractionControllerWillDismissPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidDismissPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerWillPresentPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidPresentPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerWillStartJob:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidFinishJob:(UIPrintInteractionController*)printInteractionController {}

+(BOOL)requiresMainQueueSetup
{
  return YES;
}

@end
