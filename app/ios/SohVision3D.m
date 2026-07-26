// SohVision3D.m — visionOS-only shell machinery for Starship (compiled ONLY on
// visionOS via SOH_VISIONOS in overlay 0012). Keeps Starship's iOS SohIosShell.m
// minimally diverged: the window helpers, the deterministic post-3D restore
// controller, the vision render-scale (SohIos_VisionLongEdge, consumed by the
// SDL2 visionOS metal-view patch 0030), the 3D perf-HUD text, and the `geom`
// telemetry all live here. The 3D bridge GLOBALS (gSoh3DMode, eye textures,
// camera basis) live in SohIosShell.m instead — the __IOS__ stereo overlay
// externs them and is compiled on BOTH iOS and visionOS. Machinery ported from
// the proven sibling shells (SpaghettiKart/reference); §1.5/§2.8 of the playbook.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <math.h>

// --- shell-provided symbols (SohIosShell.m, compiled on both platforms) ------
extern int CVarGetInteger(const char* name, int defaultValue);
extern void SohIos_HudStats(float* fps);
extern int SohIos_ThermalState(void);
extern volatile int gSoh3DMode;
extern volatile int gSoh3DDbg2DW, gSoh3DDbg2DH; // engine 2D dims (0 until stereo overlay sets them)

// --- vision render scale (consumed by the SDL2 visionOS metal-view patch) -----
// VP first-run default: 3840 px long edge (~4K panel; §1.4). A CVar knob so a
// device round can A/B it without a rebuild.
volatile float gSohIosVisionLongEdge = 3840.0f;
float SohIos_VisionLongEdge(void) {
    float v = (float)CVarGetInteger("gSohIos.VisionLongEdge", 0);
    if (v >= 1024.0f && v <= 8192.0f) {
        gSohIosVisionLongEdge = v;
    }
    return gSohIosVisionLongEdge;
}

// --- window helpers ----------------------------------------------------------
UIView* SohIos_FindMetalViewIn(UIView* v) {
    if ([v.layer isKindOfClass:NSClassFromString(@"CAMetalLayer")]) {
        return v;
    }
    for (UIView* c in v.subviews) {
        UIView* r = SohIos_FindMetalViewIn(c);
        if (r != nil) {
            return r;
        }
    }
    return nil;
}
UIView* SohIos_FindMetalView(UIWindow* w) {
    return w ? SohIos_FindMetalViewIn(w) : nil;
}

// Size the game window to its scene + give it the system window treatment
// (visionOS windows are continuously rounded; a raw UIWindow over the SwiftUI
// hosting window shows square corners otherwise). Idempotent.
void SohIos_GlueWindowToScene(UIWindow* w, UIWindowScene* scene) {
    if (w == nil || scene == nil) {
        return;
    }
    w.layer.cornerRadius = 46.0;
    w.layer.cornerCurve = kCACornerCurveContinuous;
    w.layer.masksToBounds = YES;
    CGRect sb = scene.coordinateSpace.bounds;
    if (sb.size.width > 1 && !CGRectEqualToRect(w.frame, sb)) {
        w.frame = sb;
        [w setNeedsLayout];
        [w layoutIfNeeded];
    }
}

static UIWindow* SohIos_GameWindowWithMetal(UIView** outMv) {
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        UIView* mv = SohIos_FindMetalView(w);
        if (mv != nil) {
            if (outMv != NULL) {
                *outMv = mv;
            }
            return w;
        }
    }
    if (outMv != NULL) {
        *outMv = nil;
    }
    return nil;
}

// --- 3D perf-HUD text (ASCII only — ImGui's atlas has no U+2022, §2.7) --------
int SohIos_PerfHud3DText(char* buf, int cap) {
    if (buf == NULL || cap < 8) {
        return -1;
    }
    buf[0] = 0;
    if (!CVarGetInteger("gSohIos.PerfHud", 0)) {
        return -1;
    }
    float fps = 0;
    SohIos_HudStats(&fps);
    int th = SohIos_ThermalState();
    if (th >= 2) {
        snprintf(buf, cap, "%.0f - HOT", fps);
    } else if (th == 1) {
        snprintf(buf, cap, "%.0f - warm", fps);
    } else {
        snprintf(buf, cap, "%.0f", fps);
    }
    return th;
}

// --- deterministic post-3D window restore (§2.8) -----------------------------
static CGSize soh_restoreTarget = { 0, 0 };
static int soh_restoreTicks = 0;
static NSTimer* soh_restoreTimer = nil;
static const char* soh_restoreState = "idle";

static void SohIos_RestoreTick(void) {
    soh_restoreTicks++;
    UIView* mv = nil;
    UIWindow* w = SohIos_GameWindowWithMetal(&mv);
    if (w == nil) {
        soh_restoreState = "no-window";
        if (soh_restoreTicks > 24) {
            [soh_restoreTimer invalidate];
            soh_restoreTimer = nil;
        }
        return;
    }
    UIWindowScene* scene = w.windowScene;
    CGSize sb = scene ? scene.coordinateSpace.bounds.size : CGSizeZero;
    CGSize goal = (soh_restoreTarget.width >= 1) ? soh_restoreTarget : sb;
    BOOL sceneAtGoal = sb.width > 1 && fabs(sb.width - goal.width) <= 2 && fabs(sb.height - goal.height) <= 2;
    if (!sceneAtGoal && soh_restoreTicks < 16) {
        if (soh_restoreTicks == 1 || soh_restoreTicks == 8) {
            extern void Soh_RequestWindowSize(CGSize size);
            Soh_RequestWindowSize(goal);
        }
        soh_restoreState = "waiting-scene";
        return;
    }
    SohIos_GlueWindowToScene(w, scene);
    for (UIView* v = mv; v != nil && v != (UIView*)w; v = v.superview) {
        v.frame = w.bounds;
    }
    [w.rootViewController.view setNeedsLayout];
    [w.rootViewController.view layoutIfNeeded];
    CGSize vb = mv.bounds.size;
    BOOL engineOk = gSoh3DDbg2DW > 0 && vb.width > 1 &&
                    fabs((float)gSoh3DDbg2DW - vb.width) <= vb.width * 0.02f &&
                    fabs((float)gSoh3DDbg2DH - vb.height) <= vb.height * 0.02f;
    if (engineOk) {
        soh_restoreState = "done";
        [soh_restoreTimer invalidate];
        soh_restoreTimer = nil;
        return;
    }
    soh_restoreState = "engine-stale";
    if (soh_restoreTicks >= 4 && (soh_restoreTicks % 2) == 0) {
        // SDL's debounce ate the resize: force a REAL bounds change so the
        // final size definitely reaches the engine.
        mv.frame = CGRectMake(0, 0, w.bounds.size.width - 1, w.bounds.size.height - 1);
        [mv setNeedsLayout];
        [mv layoutIfNeeded];
        mv.frame = CGRectMake(0, 0, w.bounds.size.width, w.bounds.size.height);
        [mv setNeedsLayout];
        [mv layoutIfNeeded];
    }
    if (soh_restoreTicks > 24) {
        soh_restoreState = "gave-up";
        [soh_restoreTimer invalidate];
        soh_restoreTimer = nil;
    }
}

CGSize SohIos_RestorePendingTarget(void) {
    return (soh_restoreTimer != nil) ? soh_restoreTarget : CGSizeZero;
}
void SohIos_RestoreCancel(void) {
    if (soh_restoreTimer != nil) {
        [soh_restoreTimer invalidate];
        soh_restoreTimer = nil;
        soh_restoreState = "cancelled";
    }
}
void SohIos_RestoreWindowTo(CGSize target) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SohIos_RestoreWindowTo(target); });
        return;
    }
    soh_restoreTarget = target;
    soh_restoreTicks = 0;
    soh_restoreState = "running";
    [soh_restoreTimer invalidate];
    soh_restoreTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                       repeats:YES
                                                         block:^(NSTimer* t) { SohIos_RestoreTick(); }];
}

// Full geometry snapshot for the bridge `geom` command. MAIN THREAD ONLY.
int SohIos_GeomReport(char* buf, int cap) {
    UIView* mv = nil;
    UIWindow* w = SohIos_GameWindowWithMetal(&mv);
    if (w == nil) {
        snprintf(buf, cap, "no game window");
        return 0;
    }
    UIWindowScene* scene = w.windowScene;
    CGRect sb = scene ? scene.coordinateSpace.bounds : CGRectZero;
    CGRect wf = w.frame;
    CGRect mf = mv != nil ? mv.frame : CGRectZero;
    CGSize ds = mv != nil ? ((CAMetalLayer*)mv.layer).drawableSize : CGSizeZero;
    CGFloat cs = mv != nil ? mv.layer.contentsScale : 0;
    snprintf(buf, cap,
             "restore=%s ticks=%d target=%.0fx%.0f scene=%.0fx%.0f win=%.0fx%.0f "
             "mv=%.0fx%.0f drawable=%.0fx%.0f scale=%.2f engine2d=%dx%d mode3d=%d",
             soh_restoreState, soh_restoreTicks, soh_restoreTarget.width, soh_restoreTarget.height,
             sb.size.width, sb.size.height, wf.size.width, wf.size.height, mf.size.width, mf.size.height,
             ds.width, ds.height, (float)cs, gSoh3DDbg2DW, gSoh3DDbg2DH, gSoh3DMode);
    return 1;
}
