#include "Tweak.h"

/**
 * Load Preferences
 */
BOOL noads;
BOOL unlimitedDownload;
BOOL downloadWithoutWatermark;
BOOL autoPlayNextVideo;
BOOL changeRegion;
BOOL showProgressBar;
BOOL canHideUI;
NSDictionary *region;

static void reloadPrefs() {
  NSDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:@PLIST_PATH] ?: [@{} mutableCopy];

  noads = [[settings objectForKey:@"noads"] ?: @(YES) boolValue];
  unlimitedDownload = [[settings objectForKey:@"unlimitedDownload"] ?: @(YES) boolValue];
  downloadWithoutWatermark = [[settings objectForKey:@"downloadWithoutWatermark"] ?: @(YES) boolValue];
  autoPlayNextVideo = [[settings objectForKey:@"autoPlayNextVideo"] ?: @(NO) boolValue];
  changeRegion = [[settings objectForKey:@"changeRegion"] ?: @(NO) boolValue];
  region = [settings objectForKey:@"region"] ?: [@{} mutableCopy];
  showProgressBar = [[settings objectForKey:@"showProgressBar"] ?: @(NO) boolValue];
  canHideUI = [[settings objectForKey:@"canHideUI"] ?: @(YES) boolValue];
}

%group CoreLogic
  %hook AWEAwemeModel
    - (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
      id orig = %orig;
      return noads && self.isAds ? nil : orig;
    }

    - (id)init {
      id orig = %orig;
      return noads && self.isAds ? nil : orig;
    }

    - (BOOL)preventDownload {
      return unlimitedDownload ? FALSE : %orig;
    }

    - (BOOL)disableDownload {
      return unlimitedDownload ? FALSE : %orig;
    }
  %end

  %hook AWEAwemePlayDislikeViewController
    - (BOOL)shouldShowDownload:(id)arg1 {
      return unlimitedDownload ? TRUE : %orig;
    }

    - (AWEAwemeDislikeNewReasonTableViewCell *)tableView:(id)arg1 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
      AWEAwemeDislikeNewReasonTableViewCell *orig = %orig;
      if (downloadWithoutWatermark && orig.model.dislikeType == 1) {
        orig.titleLabel.text = [NSString stringWithFormat:@"%@%@", orig.titleLabel.text, @" - No Watermark"];
      }
      return orig;
    }
  %end

  %hook TIKTOKAwemePlayDislikeViewController
    - (BOOL)shouldShowDownload:(id)arg1 {
      return unlimitedDownload ? TRUE : %orig;
    }

    - (AWEAwemeDislikeNewReasonTableViewCell *)tableView:(id)arg1 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
      AWEAwemeDislikeNewReasonTableViewCell *orig = %orig;
      if (downloadWithoutWatermark && orig.model.dislikeType == 1) {
        orig.titleLabel.text = [NSString stringWithFormat:@"%@%@", orig.titleLabel.text, @" - No Watermark"];
      }
      return orig;
    }
  %end

  // Thanks chenxk-j for this
  // https://github.com/chenxk-j/hookTikTok/blob/master/hooktiktok/hooktiktok.xm#L23
  %hook CTCarrier
    - (NSString *)mobileCountryCode {
      return (changeRegion && region[@"mcc"] != nil) ? region[@"mcc"] : %orig;
    }

    - (NSString *)isoCountryCode {
      return (changeRegion && region[@"code"] != nil) ? region[@"code"] : %orig;
    }

    - (NSString *)mobileNetworkCode {
      return (changeRegion && region[@"mnc"] != nil) ? region[@"mnc"] : %orig;
    }
  %end

  %hook AWEFeedGuideManager
    - (BOOL)enableAutoplay {
      return autoPlayNextVideo;
    }
  %end

  %hook AWEFeedContainerViewController
    static AWEFeedContainerViewController *__weak sharedInstance;
    %property (nonatomic, assign) BOOL isUIHidden;

    - (id)init {
      id orig = %orig;
      self.isUIHidden = FALSE;
      sharedInstance = orig;
      return orig;
    }

    %new
    + (AWEFeedContainerViewController *)sharedInstance {
      return sharedInstance;
    }
  %end

  %hook AWEAwemePlayInteractionViewController
    %property (nonatomic, retain) NSTimer *sliderTimer;
    %property (nonatomic, retain) UISlider *slider;
    %property (nonatomic, retain) UIButton *hideUIButton;

    - (void)viewDidLoad {
      %orig;

      if (showProgressBar) {
        // make circle thumb for slider
        CGFloat radius = 16.0;
        UIView *thumbView = [[UIView alloc] initWithFrame:CGRectMake(0, radius / 2, radius, radius)];
        thumbView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
        thumbView.layer.borderWidth = 0.4;
        thumbView.layer.borderColor = [UIColor whiteColor].CGColor;
        thumbView.layer.cornerRadius = radius / 2;
        UIGraphicsBeginImageContextWithOptions(thumbView.bounds.size, NO, 0.0);
        [thumbView.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *thumbImg = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        // detect iphone with notch
        double yPadding = 54.0;
        if (@available( iOS 11.0, * )) {
          if ([[[UIApplication sharedApplication] keyWindow] safeAreaInsets].bottom > 0) {
            yPadding = 96.0;
          }
        }

        // create slider
        CGRect frame = CGRectMake(0.0, self.view.frame.size.height - yPadding, self.view.frame.size.width, 10.0);
        self.slider = [[UISlider alloc] initWithFrame:frame];
        [self.slider addTarget:self action:@selector(onSliderValChanged:forEvent:) forControlEvents:UIControlEventValueChanged];
        [self.slider setBackgroundColor:[UIColor clearColor]];
        self.slider.minimumValue = 0.0;
        self.slider.maximumValue = 100.0;
        self.slider.continuous = YES;
        self.slider.value = 0.0;
        self.slider.minimumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        self.slider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
        [self.slider setThumbImage:thumbImg forState:UIControlStateNormal];
        self.sliderTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerAction:) userInfo:self.slider repeats:TRUE];
        [self.view addSubview:self.slider];
      }

      if (canHideUI) {
        // add hide/show ui button
        AWEFeedContainerViewController *afcVC = (AWEFeedContainerViewController *)[%c(AWEFeedContainerViewController) sharedInstance];
        self.hideUIButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.hideUIButton addTarget:self action:@selector(hideUIButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self.hideUIButton setTitle:afcVC.isUIHidden?@"Show UI":@"Hide UI" forState:UIControlStateNormal];
        self.hideUIButton.frame = CGRectMake(self.view.frame.size.width - 70 - 10.66, 90.0, 70.0, 40.0);
        [self.view addSubview:self.hideUIButton];
      }
    }

    - (void)playBarrage {
      %orig;
      if (canHideUI) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [self updateShowOrHideUI];
        });
      }
    }

    %new
    - (void)onSliderValChanged:(UISlider *)slider forEvent:(UIEvent *)event {
      UITouch *touchEvent = [[event allTouches] anyObject];
      switch (touchEvent.phase) {
        case UITouchPhaseBegan: {
          if (self.sliderTimer != nil) {
            [self.sliderTimer invalidate];
            self.sliderTimer = nil;
          }
          break;
        }
        case UITouchPhaseMoved: {
          break;
        }
        case UITouchPhaseEnded: {
          double duration = [self.model.video.duration doubleValue] / 1000.0 - 2.3;
          double seekTime = slider.value / 100.0 * (duration);
          [self.videoDelegate setPlayerSeekTime:seekTime completion:nil];
          if (self.sliderTimer == nil) {
            self.sliderTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerAction:) userInfo:slider repeats:TRUE];
          }
          break;
        }
        case UITouchPhaseStationary: {
          if (self.sliderTimer == nil) {
            self.sliderTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerAction:) userInfo:slider repeats:TRUE];
          }
        }
        default:
          break;
      }
    }

    %new
    - (void)timerAction:(NSTimer *)timer {
      UISlider *slider = (UISlider *)timer.userInfo;
      double percent = [self currentPlayerPlaybackTime] / ([self.model.video.duration doubleValue] / 1000.0 - 2.3) * 100.0;
      [slider setValue:percent animated:TRUE];
    }

    %new
    - (void)hideUIButtonPressed:(UIButton *)sender {
      AWEFeedContainerViewController *afcVC = (AWEFeedContainerViewController *)[%c(AWEFeedContainerViewController) sharedInstance];
      afcVC.isUIHidden = !afcVC.isUIHidden;
      [self updateShowOrHideUI];
    }

    %new
    - (void)updateShowOrHideUI {
      AWEFeedContainerViewController *afcVC = (AWEFeedContainerViewController *)[%c(AWEFeedContainerViewController) sharedInstance];
      [self setHide:afcVC.isUIHidden];
      [self.slider setHidden:afcVC.isUIHidden];
      [self.hideUIButton setTitle:afcVC.isUIHidden?@"Show UI":@"Hide UI" forState:UIControlStateNormal];
      [afcVC setAccessoriesHidden:afcVC.isUIHidden];
    }

    - (void)showDislikeOnVideo {
      if (self.sliderTimer == nil) {
        self.sliderTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerAction:) userInfo:self.slider repeats:TRUE];
      }
      %orig;
    }
  %end

  %hook AWEAwemeBaseViewController
    - (BOOL)gestureRecognizer:(id)arg1 shouldReceiveTouch:(UITouch *)arg2 {
      if (!showProgressBar) {
        return %orig;
      }

      if ([arg2.view isKindOfClass:[UISlider class]]) {
        // prevent recognizing touches on the slider
        // currently not working??
        return NO;
      }
      return YES;
    }
  %end

  %hook AWEDownloadShareChannel
    - (void)startDownloadingWithCompletion:(id)arg1 {
      [HDownloadMedia checkPermissionToPhotosAndDownload:self.downloadOptions.awemeModel.video.playURL.originURLList.firstObject appendExtension:@"mp4" mediaType:Video toAlbum:@"TikTok"];
    }
  %end

  %hook AWEAwemePlayInteractionPresenter
    - (void)longPressDownload {
      [HDownloadMedia checkPermissionToPhotosAndDownload:self.model.video.playURL.originURLList.firstObject appendExtension:@"mp4" mediaType:Video toAlbum:@"TikTok"];
      // [[[HDownloadMediaWithProgress alloc] init] checkPermissionToPhotosAndDownload:self.model.video.playURL.originURLList.firstObject appendExtension:@"mp4" mediaType:Video toAlbum:@"TikTok" viewController:self.viewController];
    }
  %end
%end


/**
 * Constructor
 */
%ctor {
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback) reloadPrefs, CFSTR(PREF_CHANGED_NOTIF), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  reloadPrefs();

  %init(CoreLogic);
}

