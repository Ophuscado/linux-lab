// smc-dump: every key of the System Management Controller with its type, size and value, read through AppleSMC's
// user client as monitoring tools do (read only). Run once idle and once under load to see which keys are
// temperatures, powers, currents, voltages and fans on this Mac: the map Linux's macsmc hwmon driver needs.
// Text keys (type ch8*) are printed as "<text>" only: some hold identifiers of the machine.
// Build: clang -O2 smc-dump.c -o smc-dump -framework IOKit -framework CoreFoundation
// Run:   ./smc-dump > smc.tsv      (key, type, size, value, hex)
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } smc_vers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } smc_plimit;
typedef struct { uint32_t size, type; uint8_t attributes; } smc_keyinfo;
typedef struct {
    uint32_t key;
    smc_vers vers;
    smc_plimit plimit;
    smc_keyinfo info;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} smc_data;
_Static_assert(sizeof(smc_data) == 80, "AppleSMC expects 80-byte calls");

enum { SMC_READ_BYTES = 5, SMC_READ_INDEX = 8, SMC_READ_KEYINFO = 9, SMC_SELECTOR = 2 };

static io_connect_t conn;

static int call(smc_data *in, smc_data *out) {
    size_t n = sizeof *out;
    memset(out, 0, sizeof *out);
    kern_return_t r = IOConnectCallStructMethod(conn, SMC_SELECTOR, in, sizeof *in, out, &n);
    return r == KERN_SUCCESS && out->result == 0 ? 0 : -1;
}

static void fourcc(uint32_t v, char *s) { s[0] = v >> 24; s[1] = v >> 16; s[2] = v >> 8; s[3] = v; s[4] = 0; }
static uint32_t key_of(const char *s) { return (uint32_t)s[0] << 24 | (uint32_t)s[1] << 16 | (uint32_t)s[2] << 8 | (uint8_t)s[3]; }

static int read_key(uint32_t key, smc_keyinfo *info, uint8_t *bytes) {
    smc_data in = {0}, out;
    in.key = key; in.data8 = SMC_READ_KEYINFO;
    if (call(&in, &out)) return -1;
    *info = out.info;
    memset(&in, 0, sizeof in);
    in.key = key; in.info.size = info->size; in.data8 = SMC_READ_BYTES;
    if (call(&in, &out)) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

int main(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn) != KERN_SUCCESS) { fprintf(stderr, "AppleSMC not opened\n"); return 1; }
    smc_keyinfo info; uint8_t b[32];
    if (read_key(key_of("#KEY"), &info, b)) { fprintf(stderr, "#KEY not readable\n"); return 1; }
    uint32_t count = (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 | (uint32_t)b[2] << 8 | b[3];
    printf("# %u keys\nkey\ttype\tsize\tvalue\thex\n", count);
    for (uint32_t i = 0; i < count; i++) {
        smc_data in = {0}, out;
        in.data8 = SMC_READ_INDEX; in.data32 = i;
        if (call(&in, &out)) continue;
        char k[5], t[5];
        fourcc(out.key, k);
        if (read_key(out.key, &info, b)) { printf("%s\t?\t?\tunreadable\t\n", k); continue; }
        fourcc(info.type, t);
        char v[64] = "";
        if (!strcmp(t, "flt ") && info.size == 4) { float f; memcpy(&f, b, 4); snprintf(v, sizeof v, "%g", f); }
        else if (!strcmp(t, "ui8 ") || !strcmp(t, "flag")) snprintf(v, sizeof v, "%u", b[0]);
        else if (!strcmp(t, "ui16")) snprintf(v, sizeof v, "%u", (unsigned)(b[0] << 8 | b[1]));
        else if (!strcmp(t, "ui32")) snprintf(v, sizeof v, "%u", (unsigned)((uint32_t)b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]));
        else if (!strcmp(t, "si8 ")) snprintf(v, sizeof v, "%d", (int8_t)b[0]);
        else if (!strcmp(t, "si16")) snprintf(v, sizeof v, "%d", (int16_t)(b[0] << 8 | b[1]));
        else if (!strcmp(t, "ioft") && info.size == 8) { uint64_t x; memcpy(&x, b, 8); snprintf(v, sizeof v, "%g", x / 65536.0); }
        else if (!strncmp(t, "ch8", 3)) { printf("%s\t%s\t%u\t<text>\t\n", k, t, info.size); continue; }
        printf("%s\t%s\t%u\t%s\t", k, t, info.size, v);
        for (uint32_t j = 0; j < info.size && j < 32; j++) printf("%02x", b[j]);
        putchar('\n');
    }
    IOServiceClose(conn);
    return 0;
}
