#include <android/native_activity.h>
#include <android/native_window.h>
#include <android/window.h>
#include <stdint.h>
#include <time.h>

extern void fill_red_8888(void *bits, int32_t width, int32_t height, int32_t stride_pixels);
extern void fill_red_565(void *bits, int32_t width, int32_t height, int32_t stride_pixels);

static int paint_red(ANativeWindow *window)
{
    ANativeWindow_Buffer buffer;
    int painted = 0;

    /* Ask Android for a simple CPU-writable 32-bit surface. */
    ANativeWindow_setBuffersGeometry(window, 0, 0, WINDOW_FORMAT_RGBA_8888);

    if (ANativeWindow_lock(window, &buffer, 0) != 0) {
        return -1;
    }

    switch (buffer.format) {
    case WINDOW_FORMAT_RGBA_8888:
    case WINDOW_FORMAT_RGBX_8888:
        fill_red_8888(buffer.bits, buffer.width, buffer.height, buffer.stride);
        painted = 1;
        break;

    case WINDOW_FORMAT_RGB_565:
        fill_red_565(buffer.bits, buffer.width, buffer.height, buffer.stride);
        painted = 1;
        break;

    default:
        break;
    }

    if (ANativeWindow_unlockAndPost(window) != 0) {
        return -1;
    }

    return painted ? 0 : -1;
}

static void repaint_red(ANativeActivity *activity, ANativeWindow *window)
{
    (void)activity;
    (void)paint_red(window);
}

static void show_red_then_finish(ANativeActivity *activity, ANativeWindow *window)
{
    const struct timespec red_time = {
        .tv_sec = 3,
        .tv_nsec = 0,
    };

    (void)paint_red(window);
    (void)nanosleep(&red_time, 0);
    ANativeActivity_finish(activity);
}

__attribute__((visibility("default")))
void ANativeActivity_onCreate(ANativeActivity *activity,
                              void *saved_state,
                              size_t saved_state_size)
{
    (void)saved_state;
    (void)saved_state_size;

    activity->callbacks->onNativeWindowCreated = show_red_then_finish;
    activity->callbacks->onNativeWindowResized = repaint_red;
    activity->callbacks->onNativeWindowRedrawNeeded = repaint_red;

    ANativeActivity_setWindowFormat(activity, WINDOW_FORMAT_RGBA_8888);
    ANativeActivity_setWindowFlags(
        activity,
        AWINDOW_FLAG_FULLSCREEN | AWINDOW_FLAG_KEEP_SCREEN_ON,
        AWINDOW_FLAG_FORCE_NOT_FULLSCREEN);
}
