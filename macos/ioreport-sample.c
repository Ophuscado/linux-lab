// ioreport-sample.c: what macOS's own power management reports through IOReport, as one delta over SECONDS: the
// state residencies (the memory and fabric performance states the PMP reports, the GPU's performance states) and the
// simple counters (energy, bandwidth) of the groups named. It is the reference for what Linux's power controller
// should be doing on this Mac, and for the GPU clock Metal gets.
//
// The API is private (libIOReport, the one powermetrics uses); the signatures are those open tools such as macmon
// declare. A wrong one fails the build or this program, nothing else: collect.sh treats it as a skipped step.
//
// Build: clang -O2 ioreport-sample.c -o ioreport-sample -framework CoreFoundation -lIOReport
// Run:   ./ioreport-sample --list GROUP...         the channels only: group, subgroup, channel, unit, kind
//        ./ioreport-sample SECONDS GROUP...        one delta over SECONDS: the same columns, then the values
//                                                  (state: name=residency,...; simple: the integer)
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct IOReportSubscription *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a, uint64_t b, uint64_t c);
extern void IOReportMergeChannels(CFDictionaryRef into, CFDictionaryRef from, CFTypeRef unused);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef desired,
                                                          CFMutableDictionaryRef *subscribed, uint64_t channel_id, CFTypeRef b);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFMutableDictionaryRef channels, CFTypeRef a);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef a);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef ch);
extern uint8_t IOReportChannelGetFormat(CFDictionaryRef ch);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef ch, int32_t unused);
extern int32_t IOReportStateGetCount(CFDictionaryRef ch);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef ch, int32_t i);
extern int64_t IOReportStateGetResidency(CFDictionaryRef ch, int32_t i);

enum { FORMAT_SIMPLE = 1, FORMAT_STATE = 2, FORMAT_HISTOGRAM = 3, FORMAT_SIMPLE_ARRAY = 4 };

// A CFString as UTF-8 in buf ("-" for none), tabs and newlines replaced so the TSV stays one record a line.
static const char *str(CFStringRef s, char *buf, size_t n) {
    if (!s || !CFStringGetCString(s, buf, (CFIndex)n, kCFStringEncodingUTF8)) return "-";
    for (char *p = buf; *p; p++)
        if (*p == '\t' || *p == '\n') *p = ' ';
    return buf;
}

static const char *kind(uint8_t f) {
    switch (f) {
    case FORMAT_SIMPLE: return "simple";
    case FORMAT_STATE: return "state";
    case FORMAT_HISTOGRAM: return "histogram";
    case FORMAT_SIMPLE_ARRAY: return "array";
    default: return "other";
    }
}

static CFArrayRef channels_of(CFDictionaryRef d) {
    CFTypeRef a = d ? CFDictionaryGetValue(d, CFSTR("IOReportChannels")) : NULL;
    return a && CFGetTypeID(a) == CFArrayGetTypeID() ? (CFArrayRef)a : NULL;
}

static void row(CFDictionaryRef ch, int values) {
    char g[128], s[128], c[160], u[64];
    uint8_t f = IOReportChannelGetFormat(ch);
    printf("%s\t%s\t%s\t%s\t%s", str(IOReportChannelGetGroup(ch), g, sizeof g), str(IOReportChannelGetSubGroup(ch), s, sizeof s),
           str(IOReportChannelGetChannelName(ch), c, sizeof c), str(IOReportChannelGetUnitLabel(ch), u, sizeof u), kind(f));
    if (values && f == FORMAT_SIMPLE) {
        printf("\t%lld", (long long)IOReportSimpleGetIntegerValue(ch, 0));
    } else if (values && f == FORMAT_STATE) {
        int32_t n = IOReportStateGetCount(ch);
        putchar('\t');
        for (int32_t i = 0; i < n; i++) {
            char name[96];
            printf("%s%s=%lld", i ? "," : "", str(IOReportStateGetNameForIndex(ch, i), name, sizeof name),
                   (long long)IOReportStateGetResidency(ch, i));
        }
    }
    putchar('\n');
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s --list GROUP... | %s SECONDS GROUP...\n", argv[0], argv[0]);
        return 2;
    }
    int list = !strcmp(argv[1], "--list");
    int seconds = list ? 0 : atoi(argv[1]);
    if (!list && seconds <= 0) { fprintf(stderr, "SECONDS must be a positive number\n"); return 2; }

    CFMutableDictionaryRef desired = NULL;
    for (int i = 2; i < argc; i++) {
        CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
        CFDictionaryRef ch = IOReportCopyChannelsInGroup(name, NULL, 0, 0, 0);
        CFRelease(name);
        if (!ch) { fprintf(stderr, "no channels in group %s\n", argv[i]); continue; }
        if (!desired) desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, ch);
        else IOReportMergeChannels(desired, ch, NULL);
        CFRelease(ch);
    }
    if (!desired || !channels_of(desired)) { fprintf(stderr, "no channels in any group named\n"); return 1; }

    if (list) {
        CFArrayRef a = channels_of(desired);
        for (CFIndex i = 0; i < CFArrayGetCount(a); i++) row((CFDictionaryRef)CFArrayGetValueAtIndex(a, i), 0);
        return 0;
    }

    CFMutableDictionaryRef subscribed = NULL;
    IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, desired, &subscribed, 0, NULL);
    if (!sub) { fprintf(stderr, "IOReportCreateSubscription failed\n"); return 1; }
    CFDictionaryRef a = IOReportCreateSamples(sub, desired, NULL);
    sleep((unsigned)seconds);
    CFDictionaryRef b = IOReportCreateSamples(sub, desired, NULL);
    CFDictionaryRef d = a && b ? IOReportCreateSamplesDelta(a, b, NULL) : NULL;
    CFArrayRef rows = channels_of(d);
    if (!rows) { fprintf(stderr, "no samples\n"); return 1; }
    printf("# %d s\n", seconds);
    for (CFIndex i = 0; i < CFArrayGetCount(rows); i++) row((CFDictionaryRef)CFArrayGetValueAtIndex(rows, i), 1);
    return 0;
}
