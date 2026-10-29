// input-log: what macOS gets from the Magic Mouse, Trackpad and Keyboard, and what it makes of it, for the same
// gestures, so the Linux drivers (hid-magicmouse, hid-apple) and libinput settings can be measured against it.
// Three streams, one clock (seconds since the program started), one tab-separated file:
//   hid    every input report of every Apple HID device (vendor 0x05ac USB, 0x004c Bluetooth), in hex
//   mt     the contacts MultitouchSupport (private, loaded with dlopen) decodes from them: per finger its id, state,
//          normalized position and velocity, size, angle, axes, position in mm, density
//   ev     what reaches applications (a listen-only event tap): pointer deltas, scroll deltas (lines, points,
//          continuous flag, phase, momentum phase), gesture, magnify, rotate, swipe and pressure events
// Run:   ./input-log OUT.tsv SECONDS LABEL      (appends; LABEL names the gesture in each line; SECONDS 0: until
//        Ctrl+C, which ends the recording cleanly)
// Build: clang -O2 input-log.c -o input-log -framework CoreFoundation -framework IOKit -framework ApplicationServices
// Keyboard reports carry the keys pressed: type only the keys the prompt asks for while it runs.
// Permissions: macOS asks once for Input Monitoring (raw reports) and may for Accessibility (the event tap);
// a stream that stays empty says which was refused.
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static FILE *out;
static const char *label;
static double t0;
static long n_hid, n_mt, n_ev;

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9 - t0;
}

// ---- raw HID reports
static void on_report(void *ctx, IOReturn res, void *sender, IOHIDReportType type, uint32_t id, uint8_t *r, CFIndex len) {
    (void)res; (void)sender; (void)type;
    fprintf(out, "%.6f\t%s\thid\t%s\t%u\t%ld\t", now(), label, (const char *)ctx, id, (long)len);
    for (CFIndex i = 0; i < len; i++) fprintf(out, "%02x", r[i]);
    fputc('\n', out);
    n_hid++;
}

static long prop_long(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    long x = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &x);
    return x;
}

static void on_device(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)res; (void)sender;
    char name[128] = "?";
    CFTypeRef p = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
    if (p && CFGetTypeID(p) == CFStringGetTypeID()) CFStringGetCString((CFStringRef)p, name, sizeof name, kCFStringEncodingUTF8);
    long vid = prop_long(d, CFSTR(kIOHIDVendorIDKey)), pid = prop_long(d, CFSTR(kIOHIDProductIDKey));
    long page = prop_long(d, CFSTR(kIOHIDPrimaryUsagePageKey)), usage = prop_long(d, CFSTR(kIOHIDPrimaryUsageKey));
    long size = prop_long(d, CFSTR(kIOHIDMaxInputReportSizeKey));
    char *tag = malloc(160);
    snprintf(tag, 160, "%s|%04lx:%04lx|%lx:%lx", name, vid, pid, page, usage);
    fprintf(out, "%.6f\t%s\tdevice\t%s\tmax_report=%ld\n", now(), label, tag, size);
    if (size <= 0) size = 512;
    uint8_t *buf = malloc((size_t)size);
    IOHIDDeviceRegisterInputReportCallback(d, buf, size, on_report, tag);
}

static CFDictionaryRef match_vendor(long vid) {
    CFMutableDictionaryRef m = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberLongType, &vid);
    CFDictionarySetValue(m, CFSTR(kIOHIDVendorIDKey), n);
    CFRelease(n);
    return m;
}

// ---- MultitouchSupport (layout as in OpenMultitouchSupport, unchanged since macOS 10.x)
typedef struct { float x, y; } mt_point;
typedef struct { mt_point pos, vel; } mt_vector;
typedef struct {
    int frame;
    double timestamp;
    int path_index, state, finger_id, hand_id;
    mt_vector normalized;
    float z_total;
    int field9;
    float angle, major_axis, minor_axis;
    mt_vector absolute;
    int field14, field15;
    float z_density;
} mt_touch;
typedef void *mt_device;
typedef void (*mt_callback)(mt_device, mt_touch *, int, double, int);

static void on_frame(mt_device dev, mt_touch *t, int n, double ts, int frame) {
    double tn = now();
    for (int i = 0; i < n; i++) {
        fprintf(out, "%.6f\t%s\tmt\t%p\t%d\t%.6f\t%d\tid=%d hand=%d path=%d state=%d nx=%.4f ny=%.4f nvx=%.4f nvy=%.4f "
                "z=%.4f f9=%d angle=%.4f major=%.3f minor=%.3f mmx=%.3f mmy=%.3f mmvx=%.3f mmvy=%.3f f14=%d f15=%d density=%.4f\n",
                tn, label, dev, frame, ts, n, t[i].finger_id, t[i].hand_id, t[i].path_index, t[i].state,
                t[i].normalized.pos.x, t[i].normalized.pos.y, t[i].normalized.vel.x, t[i].normalized.vel.y, t[i].z_total,
                t[i].field9, t[i].angle, t[i].major_axis, t[i].minor_axis, t[i].absolute.pos.x, t[i].absolute.pos.y,
                t[i].absolute.vel.x, t[i].absolute.vel.y, t[i].field14, t[i].field15, t[i].z_density);
        n_mt++;
    }
    if (n == 0) fprintf(out, "%.6f\t%s\tmt\t%p\t%d\t%.6f\t0\n", tn, label, dev, frame, ts);
}

static void start_mt(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!h) { fprintf(out, "0\t%s\tnote\tMultitouchSupport not loaded: %s\n", label, dlerror()); return; }
    CFArrayRef (*create_list)(void) = (CFArrayRef (*)(void))dlsym(h, "MTDeviceCreateList");
    void (*reg)(mt_device, mt_callback) = (void (*)(mt_device, mt_callback))dlsym(h, "MTRegisterContactFrameCallback");
    void (*start)(mt_device, int) = (void (*)(mt_device, int))dlsym(h, "MTDeviceStart");
    int (*family)(mt_device, int *) = (int (*)(mt_device, int *))dlsym(h, "MTDeviceGetFamilyID");
    int (*dims)(mt_device, int *, int *) = (int (*)(mt_device, int *, int *))dlsym(h, "MTDeviceGetSensorSurfaceDimensions");
    int (*builtin)(mt_device) = (int (*)(mt_device))dlsym(h, "MTDeviceIsBuiltIn");
    if (!create_list || !reg || !start) { fprintf(out, "0\t%s\tnote\tMultitouchSupport symbols missing\n", label); return; }
    CFArrayRef devs = create_list();
    for (CFIndex i = 0; devs && i < CFArrayGetCount(devs); i++) {
        mt_device d = (mt_device)CFArrayGetValueAtIndex(devs, i);
        int fam = -1, w = -1, hh = -1;
        if (family) family(d, &fam);
        if (dims) dims(d, &w, &hh);
        fprintf(out, "%.6f\t%s\tmtdevice\t%p\tfamily=%d surface=%dx%d (1/100 mm) builtin=%d\n", now(), label, d, fam, w, hh,
                builtin ? builtin(d) : -1);
        reg(d, on_frame);
        start(d, 0);
    }
}

// ---- what applications see
static CGEventRef on_event(CGEventTapProxy proxy, CGEventType type, CGEventRef e, void *ctx) {
    (void)proxy; (void)ctx;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) return e;
    fprintf(out, "%.6f\t%s\tev\t%u", now(), label, (unsigned)type);
    switch (type) {
    case kCGEventScrollWheel:
        fprintf(out, "\tscroll lines=%lld,%lld points=%lld,%lld fixed=%.4f,%.4f continuous=%lld phase=%lld momentum=%lld",
                CGEventGetIntegerValueField(e, kCGScrollWheelEventDeltaAxis1), CGEventGetIntegerValueField(e, kCGScrollWheelEventDeltaAxis2),
                CGEventGetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis1), CGEventGetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis2),
                CGEventGetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis1), CGEventGetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis2),
                CGEventGetIntegerValueField(e, kCGScrollWheelEventIsContinuous), CGEventGetIntegerValueField(e, (CGEventField)99),
                CGEventGetIntegerValueField(e, kCGScrollWheelEventMomentumPhase));
        break;
    case kCGEventMouseMoved: case kCGEventLeftMouseDragged: case kCGEventRightMouseDragged: case kCGEventOtherMouseDragged:
    case kCGEventLeftMouseDown: case kCGEventLeftMouseUp: case kCGEventRightMouseDown: case kCGEventRightMouseUp: {
        CGPoint p = CGEventGetLocation(e);
        fprintf(out, "\tmouse dx=%lld dy=%lld x=%.1f y=%.1f clicks=%lld pressure=%.4f", CGEventGetIntegerValueField(e, kCGMouseEventDeltaX),
                CGEventGetIntegerValueField(e, kCGMouseEventDeltaY), p.x, p.y, CGEventGetIntegerValueField(e, kCGMouseEventClickState),
                CGEventGetDoubleValueField(e, kCGMouseEventPressure));
        break;
    }
    default: {
        // Gesture types (29 gesture, 30 magnify, 31 swipe, 18 rotate, 19/20 begin/end, 32 smart magnify, 34 pressure)
        // carry their values in undocumented fields: the raw event, as Core Graphics serializes it.
        CFDataRef d = CGEventCreateData(NULL, e);
        if (d) {
            fputc('\t', out);
            const uint8_t *b = CFDataGetBytePtr(d);
            for (CFIndex i = 0; i < CFDataGetLength(d); i++) fprintf(out, "%02x", b[i]);
            CFRelease(d);
        }
    }
    }
    fputc('\n', out);
    n_ev++;
    return e;
}

static void start_tap(void) {
    CGEventMask mask = 0;
    for (int t = 1; t < 40; t++)
        if (t != kCGEventKeyDown && t != kCGEventKeyUp && t != kCGEventFlagsChanged) mask |= CGEventMaskBit(t);
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, on_event, NULL);
    if (!tap) { fprintf(out, "0\t%s\tnote\tno event tap (Accessibility or Input Monitoring refused)\n", label); return; }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(NULL, tap, 0), kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
}

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: %s OUT.tsv SECONDS LABEL\n", argv[0]); return 2; }
    out = fopen(argv[1], "a");
    if (!out) { perror(argv[1]); return 1; }
    setvbuf(out, NULL, _IOFBF, 1 << 20);
    double secs = atof(argv[2]);
    label = argv[3];
    t0 = 0; t0 = now();

    IOHIDManagerRef m = IOHIDManagerCreate(NULL, kIOHIDOptionsTypeNone);
    CFDictionaryRef ms[2] = { match_vendor(0x05ac), match_vendor(0x004c) };
    CFArrayRef arr = CFArrayCreate(NULL, (const void **)ms, 2, &kCFTypeArrayCallBacks);
    IOHIDManagerSetDeviceMatchingMultiple(m, arr);
    IOHIDManagerRegisterDeviceMatchingCallback(m, on_device, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOReturn r = IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    if (r != kIOReturnSuccess) fprintf(out, "0\t%s\tnote\tIOHIDManagerOpen 0x%x (Input Monitoring refused?)\n", label, r);
    start_mt();
    start_tap();
    // Ctrl+C stops the run loop and the file is closed as after a timed run.
    signal(SIGINT, SIG_IGN);
    dispatch_source_t sig = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(sig, ^{ CFRunLoopStop(CFRunLoopGetMain()); });
    dispatch_resume(sig);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, secs > 0 ? secs : 1e9, false);
    fprintf(out, "%.6f\t%s\tend\thid=%ld mt=%ld ev=%ld\n", now(), label, n_hid, n_mt, n_ev);
    fclose(out);
    printf("%s: %ld HID reports, %ld touches, %ld events\n", label, n_hid, n_mt, n_ev);
    return 0;
}
