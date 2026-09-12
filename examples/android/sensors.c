typedef struct ASensorManager ASensorManager;
typedef struct ASensor ASensor;
typedef const ASensor *const *ASensorList;

extern ASensorManager *ASensorManager_getInstance(void);
extern int ASensorManager_getSensorList(ASensorManager *, ASensorList *);
extern const char *ASensor_getName(const ASensor *);
extern const char *ASensor_getVendor(const ASensor *);
extern int ASensor_getType(const ASensor *);
extern int ASensor_getMinDelay(const ASensor *);

static long write_bytes(int fd, const char *data, unsigned int count) {
    register long r0 __asm__("r0") = fd;
    register long r1 __asm__("r1") = (long)data;
    register long r2 __asm__("r2") = count;
    register long r7 __asm__("r7") = 4;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory");
    return r0;
}

__attribute__((noreturn)) static void exit_process(int status) {
    register long r0 __asm__("r0") = status;
    register long r7 __asm__("r7") = 1;
    __asm__ volatile("svc 0" : : "r"(r0), "r"(r7) : "memory");
    for (;;) { }
}

static unsigned int text_length(const char *text) {
    unsigned int n = 0;
    if (!text) return 0;
    while (text[n]) ++n;
    return n;
}

static void write_text(const char *text) {
    if (text) write_bytes(1, text, text_length(text));
}

static void write_hex(unsigned int value) {
    char out[10];
    static const char digits[] = "0123456789abcdef";
    out[0] = '0'; out[1] = 'x';
    for (unsigned int i = 0; i < 8; ++i) {
        unsigned int shift = 28 - i * 4;
        out[2 + i] = digits[(value >> shift) & 15u];
    }
    write_bytes(1, out, 10);
}

static int run(void) {
    ASensorManager *manager = ASensorManager_getInstance();
    if (!manager) {
        write_text("sensor manager unavailable\n");
        return 2;
    }

    ASensorList list = 0;
    int count = ASensorManager_getSensorList(manager, &list);
    if (count < 0 || !list) {
        write_text("sensor list unavailable\n");
        return 3;
    }

    write_text("count\t"); write_hex((unsigned int)count); write_text("\n");
    write_text("index\ttype\tmin_delay_us\tname\tvendor\n");
    for (int i = 0; i < count; ++i) {
        const ASensor *sensor = list[i];
        write_hex((unsigned int)i); write_text("\t");
        write_hex((unsigned int)ASensor_getType(sensor)); write_text("\t");
        write_hex((unsigned int)ASensor_getMinDelay(sensor)); write_text("\t");
        write_text(ASensor_getName(sensor)); write_text("\t");
        write_text(ASensor_getVendor(sensor)); write_text("\n");
    }
    return 0;
}

void _start(void) {
    exit_process(run());
}
