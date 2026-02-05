//  weibo:   https://weibo.com/u/2738662791
//  twitter: https://twitter.com/u0x01
//
//  bluedhook.mm (Enhanced with Auto-Save)
//
//  本代码由 AI 协作优化，适配 iOS 16.3 Rootless 环境

#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif

// 基础头文件
#import "substrate.h"
#import <UIKit/UIkit.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h> // [新增] 用于操作相册
#import "CaptainHook/CaptainHook.h"

// 项目自定义头文件 (请确保 GitHub 仓库中包含这些 .h 文件)
#import "PushPackage.h"
#import "GJIMMessageModel.h"
#import "GJIMSessionService.h"
#import "GJIMMessageService.h"
#import "BDEncrypt.h"
#import "BDChatBasicCell.h"
#import "GJIMDBService.h"
#import "GJIMSessionToken.h"

// 声明 Hook 的类
CHDeclareClass(UITableViewCell);
CHDeclareClass(GJIMSessionService);

// --- [新增辅助函数]：异步下载并保存图片 ---
static void saveImageToAlbum(NSString *urlStr) {
    if (!urlStr || ![urlStr hasPrefix:@"http"]) return;

    NSURL *url = [NSURL URLWithString:urlStr];
    // 异步执行，避免卡住 App 接收消息的 UI 线程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *image = [UIImage imageWithData:data];
        if (image) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            } completionHandler:^(BOOL success, NSError *error) {
                if (success) {
                    NSLog(@"[BLUEDHOOK] 闪照自动保存成功！");
                } else {
                    NSLog(@"[BLUEDHOOK] 保存失败，请检查设置中的相册权限: %@", error.localizedDescription);
                }
            }];
        }
    });
}

// --- Hook 消息接收逻辑 ---
CHOptimizedMethod1(self, id, GJIMSessionService, p_handlePushPackage, PushPackage*, pkg) {
    switch (pkg.messageType) {
        case 55: // 拦截撤回消息
        {
            NSLog(@"[BLUEDHOOK] %@ 尝试撤回消息，已被拦截。", pkg.name);
            GJIMSessionToken *sessionToken = [objc_getClass("GJIMSessionToken") gji_sessionTokenWithId: pkg.sessionId type:2];
            [objc_getClass("GJIMDBService") gji_getMessagesWithToken:sessionToken complete:^(id data) {
                GJIMMessageModel *targetMsg;
                for (GJIMMessageModel *msg in data) {
                    if (msg.msgId == pkg.messageId) {
                        targetMsg = msg;
                        break;
                    }
                }
                
                if (targetMsg == nil) {
                    NSLog(@"[BLUEDHOOK] Warning: 无法找到原始消息 ID %llu", pkg.messageId);
                    // 容错处理
                    for (GJIMMessageModel *msg in data) {
                        if (msg.fromId == pkg.from) {
                            targetMsg = msg;
                            break;
                        }
                    }
                    targetMsg.type = 1;
                    targetMsg.msgId = pkg.messageId;
                    targetMsg.sendTime = pkg.timestamp;
                    targetMsg.msgExtra = @{@"BLUED_HOOK_IS_RECALLED": @1};
                    targetMsg.content = @"对方撤回了一条消息，但已错过接收原始消息无法复原。";
                    [self addMessage:targetMsg];
                    return;
                }
                
                targetMsg.msgExtra = @{@"BLUED_HOOK_IS_RECALLED": @1};
                [self updateMessage:targetMsg];
            }];
            return nil;
        }
        break;

        case 24: // 关键点：拦截并破解闪照
        {
            NSLog(@"[BLUEDHOOK] 检测到实时闪照推送，正在破解并保存...");
            pkg.messageType = 2; // 将闪照转换为普通图片类型
            pkg.contents = [objc_getClass("BDEncrypt") decryptVideoUrl:pkg.contents]; // 解密 URL
            pkg.msgExtra = @{@"BLUEDHOOK_IS_SNAPIMG": @1}; // 打上标记
            
            // [核心新增]：调用自动保存
            saveImageToAlbum(pkg.contents);
        }
        break;

        default:
            break;
    }
    
    return CHSuper1(GJIMSessionService, p_handlePushPackage, pkg);
}

// --- Hook UI 渲染逻辑 ---
CHOptimizedMethod0(self, id, UITableViewCell, contentView){
    NSString *cellClassName = [NSString stringWithFormat:@"%@", ((UIView*)self).class];
    if (![cellClassName containsString:@"PrivateOther"]) {
        return CHSuper0(UITableViewCell, contentView);
    }
    
    UIView *contentView = CHSuper0(UITableViewCell, contentView);
    GJIMMessageModel *msg = [[(BDChatBasicCell*)self message] copy];
    if (msg == nil) return contentView;

    // 如果渲染时发现是未处理的闪照（如加载历史记录）
    if (msg.type == 24) {
        msg.type = 2;
        msg.content = [objc_getClass("BDEncrypt") decryptVideoUrl:msg.content];
        msg.msgExtra = @{@"BLUEDHOOK_IS_SNAPIMG": @1};
        GJIMSessionService * sessionService = [objc_getClass("GJIMSessionService") sharedInstance];
        [sessionService updateMessage:msg];
        return contentView;
    }
    
    // UI 提示标签逻辑
    NSInteger labelTag = 1069;
    CGFloat labelPosTop = contentView.frame.size.height-12;
    CGFloat labelPosLeft = [contentView subviews][2].frame.origin.x;
    
    switch (msg.type) {
        case 1: labelPosTop -= 8; labelPosLeft += 12; break;
        case 3: labelPosLeft += 12; break;
        default: break;
    }
    
    UILabel *label = [self viewWithTag:labelTag];
    if (label == nil) {
        label = [[UILabel alloc] init];
    }
    [label setFrame:CGRectMake(labelPosLeft, labelPosTop, contentView.frame.size.width, 12)];
    
    NSArray *keys = [msg.msgExtra allKeys];
    if (msg.msgId == 0 || [keys count] == 0) return contentView;
    
    NSString *labelText = @"";
    if ([keys containsObject:@"BLUEDHOOK_IS_SNAPIMG"]) {
        labelText = @"该照片由闪照转换而成，已尝试自动保存。";
    } else if([keys containsObject:@"BLUED_HOOK_IS_RECALLED"]) {
        labelText = @"对方尝试撤回此消息，已被阻止。";
        if ([msg.content containsString:@"burn-chatfiles"]) {
            labelText = @"该闪照已被对方撤回。";
        }
    }

    [label setFont:[UIFont systemFontOfSize:9]];
    label.textColor = [UIColor grayColor];
    label.tag = labelTag;
    label.text = labelText;
    label.numberOfLines = 1;
    [self addSubview:label];

    return contentView;
}

// --- 构造器：完成加载 ---
CHConstructor {
    @autoreleasepool {
        CHLoadLateClass(GJIMSessionService);
        CHClassHook1(GJIMSessionService, p_handlePushPackage);
        
        CHLoadLateClass(UITableViewCell);
        CHHook0(UITableViewCell, contentView);
    }
}