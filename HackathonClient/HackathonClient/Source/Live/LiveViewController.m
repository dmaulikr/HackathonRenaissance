//
//  LiveViewController.m
//  HackathonClient
//
//  Created by 孙恺 on 16/6/25.
//  Copyright © 2016年 AboutBlack. All rights reserved.
//

#import "LiveViewController.h"
#import <AFNetworking/AFNetworking.h>
#import <Wilddog/Wilddog.h>
#import "TLTagsControl.h"
#import <SVProgressHUD/SVProgressHUD.h>

@interface LiveViewController () {
    __block AgoraRtcStats *lastStat_;
}

@property (weak, nonatomic) IBOutlet TLTagsControl *tagsControl;
@property (weak, nonatomic) IBOutlet UITextField *titleField;
@property (weak, nonatomic) IBOutlet UITextField *priceField;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *bottomConstraint;
@property (strong, nonatomic) IBOutletCollection(UIButton) NSArray *speakerControlButtons;
@property (strong, nonatomic) IBOutletCollection(UIButton) NSArray *audioMuteControlButtons;
@property (weak, nonatomic) IBOutlet UIButton *cameraControlButton;

@property (weak, nonatomic) IBOutlet UIView *audioControlView;
@property (weak, nonatomic) IBOutlet UIView *videoControlView;

@property (weak, nonatomic) IBOutlet UIView *videoMainView;

@property (weak, nonatomic) IBOutlet UILabel *talkTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *dataTrafficLabel;
@property (weak, nonatomic) IBOutlet UILabel *alertLabel;

@property (strong, nonatomic) AgoraRtcEngineKit *agoraKit;

@property (strong, nonatomic) NSMutableArray *uids;
@property (strong, nonatomic) NSMutableDictionary *videoMuteForUids;

//
@property (assign, nonatomic) AGDChatType type;
@property (strong, nonatomic) NSString *channel;
@property (strong, nonatomic) NSString *vendorKey;
@property (assign, nonatomic) BOOL agoraVideoEnabled;
@property (strong, nonatomic) NSTimer *durationTimer;
@property (nonatomic) NSUInteger duration;

@property (strong, nonatomic) UIAlertView *errorKeyAlert;

@end

@implementation LiveViewController

#pragma mark - keyboard

- (void)dealloc {
    
    // 移除键盘通知
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 键盘改变高度通知处理
- (void)keyboardWillChangeFrameNotification:(NSNotification *)notification {

    NSDictionary *userInfo = [notification userInfo];
    CGRect rect = [userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = CGRectGetHeight(rect);
    CGFloat keyboardDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    // 修改下边距约束
    self.bottomConstraint.constant = keyboardHeight;
    
    // 更新约束
    [UIView animateWithDuration:keyboardDuration animations:^{
        
        [self.view layoutIfNeeded];
    }];
}

// 键盘隐藏通知处理
- (void)keyboardWillHideNotification:(NSNotification *)notification {
    // 获得键盘动画时长
    NSDictionary *userInfo = [notification userInfo];
    CGFloat keyboardDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    // 修改为以前的约束（距下边距20）
    self.bottomConstraint.constant = 0;
    
    // 更新约束
    [UIView animateWithDuration:keyboardDuration animations:^{
        
        [self.view layoutIfNeeded];
    }];
    
}

- (void)packupKeyboard:(UITapGestureRecognizer *)sender {
    [self.titleField resignFirstResponder];
    [self.priceField resignFirstResponder];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tagsControl.mode = TLTagsControlModeList;
    [self.tagsControl setBackgroundColor:[UIColor clearColor]];
    
    UITapGestureRecognizer *tapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(packupKeyboard:)];
    [self.videoMainView addGestureRecognizer:tapGR];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrameNotification:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHideNotification:) name:UIKeyboardWillHideNotification object:nil];
    
    self.dictionary = @{AGDKeyChannelKey: AGDKeyChannelValue,
                        AGDKeyVendorKey: AGDKeyVendorValue};

    self.chatType = AGDChatTypeVideo;
    
//    [self.collectionView registerClass:[AGDChatCell class] forCellWithReuseIdentifier:@"CollectionViewCell"];
    
    self.uids = [NSMutableArray array];
    self.videoMuteForUids = [NSMutableDictionary dictionary];
    
    self.channel = [self.dictionary objectForKey:AGDKeyChannelKey];
    self.vendorKey = [self.dictionary objectForKey:AGDKeyVendorKey];
    self.type = self.chatType;
    
    self.title = [NSString stringWithFormat:@"%@ %@",NSLocalizedString(@"room", nil), self.channel];
//    [self selectSpeakerButtons:YES];
    [self initAgoraKit];
    NSLog(@"self: %@", self);
    
    NSString *url = @"https://aboutblank-hackathonclient.wilddogio.com/goods";
    Wilddog *goodsRef = [[Wilddog alloc] initWithUrl:url];
    [goodsRef observeEventType:WEventTypeValue withBlock:^(WDataSnapshot *snapshot) {
        //        NSLog(@"商品发布：%@ -> %@", snapshot.key, snapshot.value);
        NSDictionary *dic = (NSDictionary *)snapshot.value;
        
        for (NSString *key in dic.allKeys) {
            NSLog(@"%@,%@\n", dic[key][@"name"], dic[key][@"price"]);
            [self.tagsControl addTag:dic[key][@"name"]];
        }
        
    }];

    
//    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    self.videoMainView.frame = self.videoMainView.superview.bounds; // video view's autolayout cause crash
    [self joinChannel];
    
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    
    NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"user_Name"];
    
    NSString *url = @"http://hack2016.applinzi.com/index.php/Home/Index/livestatus";
    
    [manager POST:url parameters:@{@"user": username, @"status": @"2"} progress:^(NSProgress * _Nonnull uploadProgress) {
        NSLog(@"post success");
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"%@",error);  //这里打印错误信息
    }];
}

#pragma mark - Action
- (IBAction)releaseGood:(id)sender {
    [self.titleField resignFirstResponder];
    [self.priceField resignFirstResponder];
    
    if (self.titleField.text.length != 0 && self.priceField.text.length != 0) {
        
        NSString *url = [NSString stringWithFormat:@"https://aboutblank-hackathonclient.wilddogio.com/goods/%@", self.titleField.text];
        
        NSString *nameURL = [NSString stringWithFormat:@"%@/name", url];
        NSString *priceURL = [NSString stringWithFormat:@"%@/price", url];
        
        Wilddog *nameRef = [[Wilddog alloc] initWithUrl:nameURL];
        Wilddog *priceRef = [[Wilddog alloc] initWithUrl:priceURL];
        
        [nameRef setValue:self.titleField.text];
        [priceRef setValue:self.priceField.text];
        
        self.titleField.text = @"";
        self.priceField.text = @"";
        
        [SVProgressHUD showSuccessWithStatus:@"上架成功"];
    }
}

- (IBAction)didClickBackView:(id)sender
{
    [self showAlertLabelWithString:NSLocalizedString(@"正在退出……", nil)];
    __weak typeof(self) weakSelf = self;
    [self.agoraKit leaveChannel:^(AgoraRtcStats *stat) {
        // Myself leave status
        [weakSelf.durationTimer invalidate];
        [weakSelf.navigationController popViewControllerAnimated:YES];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    }];
}

- (IBAction)didClickAudioMuteButton:(UIButton *)btn
{
    [self selectAudioMuteButtons:!btn.selected];
    [self.agoraKit muteLocalAudioStream:btn.selected];
}

- (IBAction)didClickSpeakerButton:(UIButton *)btn
{
    [self.agoraKit setEnableSpeakerphone:!self.agoraKit.isSpeakerphoneEnabled];
    [self selectSpeakerButtons:!self.agoraKit.isSpeakerphoneEnabled];
}

- (IBAction)didClickVideoMuteButton:(UIButton *)btn
{
    btn.selected = !btn.selected;
    [self.agoraKit muteLocalVideoStream:btn.selected];
    self.videoMainView.hidden = btn.selected;
}

- (IBAction)didClickSwitchButton:(UIButton *)btn
{
//    btn.selected = !btn.selected;
    [self.agoraKit switchCamera];
}

- (IBAction)didClickHungUpButton:(UIButton *)btn
{
    [self showAlertLabelWithString:NSLocalizedString(@"正在退出……", nil)];
    __weak typeof(self) weakSelf = self;
    [self.agoraKit leaveChannel:^(AgoraRtcStats *stat) {
        // Myself leave status
        [weakSelf.durationTimer invalidate];
        [weakSelf.navigationController popViewControllerAnimated:YES];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    }];
}

- (IBAction)didClickAudioButton:(UIButton *)btn
{
    // Start audio chat
    [self.agoraKit disableVideo];
    self.type = AGDChatTypeAudio;
}

- (IBAction)didClickVideoButton:(UIButton *)btn
{
    // Start video chat
    [self.agoraKit enableVideo];
    self.type = AGDChatTypeVideo;
    if (self.cameraControlButton.selected) {
        self.cameraControlButton.selected = NO;
    }
}

- (IBAction)hangUp:(id)sender {
    
    [self showAlertLabelWithString:NSLocalizedString(@"正在退出……", nil)];
    __weak typeof(self) weakSelf = self;
    [self.agoraKit leaveChannel:^(AgoraRtcStats *stat) {
        // Myself leave status
        [weakSelf.durationTimer invalidate];
        
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            
        }];
        
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    }];
    
}

#pragma mark - Agora Settings


- (void)initAgoraKit
{
    // use test key
    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithVendorKey:self.vendorKey delegate:self];
    
    [self setUpVideo];
    [self setUpBlocks];
}

- (void)joinChannel
{
    [self showAlertLabelWithString:NSLocalizedString(@"没人看你直播哦", nil)];
    
    __weak typeof(self) weakSelf = self;
    [self.agoraKit joinChannelByKey:nil channelName:self.channel info:nil uid:999 joinSuccess:^(NSString *channel, NSUInteger uid, NSInteger elapsed) {
        
        [weakSelf.agoraKit setEnableSpeakerphone:YES];
        if (weakSelf.type == AGDChatTypeAudio) {
            [weakSelf.agoraKit disableVideo];
        }
        
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setObject:weakSelf.vendorKey forKey:AGDKeyVendorKey];
    }];
}

- (void)setUpVideo
{
    [self.agoraKit enableVideo];
    AgoraRtcVideoCanvas *videoCanvas = [[AgoraRtcVideoCanvas alloc] init];
    videoCanvas.uid = 0;
    videoCanvas.view = self.videoMainView;
    videoCanvas.renderMode = AgoraRtc_Render_Hidden;
    [self.agoraKit setupLocalVideo:videoCanvas];
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine firstLocalVideoFrameWithSize:(CGSize)size elapsed:(NSInteger)elapsed
{
    NSLog(@"local video display");
    __weak typeof(self) weakSelf = self;
    weakSelf.videoMainView.frame = weakSelf.videoMainView.superview.bounds; // video view's autolayout cause crash
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinedOfUid:(NSUInteger)uid elapsed:(NSInteger)elapsed
{
    __weak typeof(self) weakSelf = self;
    NSLog(@"self: %@", weakSelf);
    NSLog(@"engine: %@", engine);
    [weakSelf hideAlertLabel];
    [weakSelf.uids addObject:@(uid)];
}
- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOfflineOfUid:(NSUInteger)uid reason:(AgoraRtcUserOfflineReason)reason
{
    __weak typeof(self) weakSelf = self;
    NSInteger index = [weakSelf.uids indexOfObject:@(uid)];
    if (index != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [weakSelf.uids removeObjectAtIndex:index];
    }
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didVideoMuted:(BOOL)muted byUid:(NSUInteger)uid
{
    __weak typeof(self) weakSelf = self;
    NSLog(@"user %@ mute video: %@", @(uid), muted ? @"YES" : @"NO");
    
    [weakSelf.videoMuteForUids setObject:@(muted) forKey:@(uid)];
}

- (void)rtcEngineConnectionDidLost:(AgoraRtcEngineKit *)engine
{
    __weak typeof(self) weakSelf = self;
    [weakSelf showAlertLabelWithString:NSLocalizedString(@"no_network", nil)];
    weakSelf.videoMainView.hidden = YES;
    weakSelf.dataTrafficLabel.text = @"0KB/s";
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine reportRtcStats:(AgoraRtcStats*)stats
{
    __weak typeof(self) weakSelf = self;
    // Update talk time
    if (weakSelf.duration == 0 && !weakSelf.durationTimer) {
        weakSelf.talkTimeLabel.text = @"00:00";
        weakSelf.durationTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:weakSelf selector:@selector(updateTalkTimeLabel) userInfo:nil repeats:YES];
    }
    
    NSUInteger traffic = (stats.txBytes + stats.rxBytes - lastStat_.txBytes - lastStat_.rxBytes) / 1024;
    NSUInteger speed = traffic / (stats.duration - lastStat_.duration);
    NSString *trafficString = [NSString stringWithFormat:@"%@KB/s", @(speed)];
    weakSelf.dataTrafficLabel.text = trafficString;
    
    lastStat_ = stats;
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOccurError:(AgoraRtcErrorCode)errorCode
{
    __weak typeof(self) weakSelf = self;
    if (errorCode == AgoraRtc_Error_InvalidVendorKey) {
        [weakSelf.agoraKit leaveChannel:nil];
        [weakSelf.errorKeyAlert show];
    }
}

- (void)setUpBlocks
{
    //    [self.agoraKit rtcStatsBlock:^(AgoraRtcStats *stat) {
    //        // Update talk time
    //        if (self.duration == 0 && !self.durationTimer) {
    //            self.talkTimeLabel.text = @"00:00";
    //            self.durationTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateTalkTimeLabel) userInfo:nil repeats:YES];
    //        }
    //
    //        NSUInteger traffic = (stat.txBytes + stat.rxBytes - lastStat_.txBytes - lastStat_.rxBytes) / 1024;
    //        NSUInteger speed = traffic / (stat.duration - lastStat_.duration);
    //        NSString *trafficString = [NSString stringWithFormat:@"%@KB/s", @(speed)];
    //        self.dataTrafficLabel.text = trafficString;
    //
    //        lastStat_ = stat;
    //    }];
    
    //    [self.agoraKit userJoinedBlock:^(NSUInteger uid, NSInteger elapsed) {
    //        [self hideAlertLabel];
    //        [self.uids addObject:@(uid)];
    //
    //        [self.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.uids.count-1 inSection:0]]];
    //    }];
    
    //    [self.agoraKit userOfflineBlock:^(NSUInteger uid) {
    //        NSInteger index = [self.uids indexOfObject:@(uid)];
    //        if (index != NSNotFound) {
    //            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    //            [self.uids removeObjectAtIndex:index];
    //            [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
    //        }
    //    }];
    
    
    
    //    [self.agoraKit connectionLostBlock:^{
    //        [self showAlertLabelWithString:NSLocalizedString(@"no_network", nil)];
    //        self.videoMainView.hidden = YES;
    //        self.dataTrafficLabel.text = @"0KB/s";
    //    }];
    
    //    [self.agoraKit userMuteVideoBlock:^(NSUInteger uid, BOOL muted) {
    //        NSLog(@"user %@ mute video: %@", @(uid), muted ? @"YES" : @"NO");
    //
    //        [self.videoMuteForUids setObject:@(muted) forKey:@(uid)];
    //        [self.collectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForRow:[self.uids indexOfObject:@(uid)] inSection:0]]];
    //    }];
    //
    //    [self.agoraKit firstLocalVideoFrameBlock:^(NSInteger width, NSInteger height, NSInteger elapsed) {
    //        NSLog(@"local video display");
    //        self.videoMainView.frame = self.videoMainView.superview.bounds; // video view's autolayout cause crash
    //    }];
}

#pragma mark - Utils

- (void)showAlertLabelWithString:(NSString *)text;
{
    self.alertLabel.hidden = NO;
    self.alertLabel.text = text;
}

- (void)hideAlertLabel
{
    self.alertLabel.hidden = YES;
}

- (void)updateTalkTimeLabel
{
    self.duration++;
    NSUInteger seconds = self.duration % 60;
    NSUInteger minutes = (self.duration - seconds) / 60;
    self.talkTimeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (unsigned long)minutes, (unsigned long)seconds];
}

#pragma mark - State states

- (void)setType:(AGDChatType)type
{
    _type = type;
    if (type == AGDChatTypeVideo) {
        // Control buttons
        self.videoControlView.hidden = NO;
        self.audioControlView.hidden = YES;
        
        //
        self.videoMainView.hidden = NO;
    } else {
        // Control buttons
        self.videoControlView.hidden = YES;
        self.audioControlView.hidden = NO;

        //
        self.videoMainView.hidden = YES;
    }
}

- (void)selectSpeakerButtons:(BOOL)selected
{
    for (UIButton *btn in self.speakerControlButtons) {
        btn.selected = selected;
    }
}

- (void)selectAudioMuteButtons:(BOOL)selected
{
    for (UIButton *btn in self.audioMuteControlButtons) {
        btn.selected = selected;
    }
}

- (UIAlertView *)errorKeyAlert
{
    if (!_errorKeyAlert) {
        _errorKeyAlert = [[UIAlertView alloc] initWithTitle:@""
                                                    message:NSLocalizedString(@"wrong_key", nil)
                                                   delegate:self
                                          cancelButtonTitle:NSLocalizedString(@"done", nil)
                                          otherButtonTitles:nil];
    }
    return _errorKeyAlert;
}

#pragma mark - Status Bar

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
    return UIStatusBarAnimationSlide;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
