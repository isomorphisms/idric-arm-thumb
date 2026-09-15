#include <android/log.h>
#include <android/native_activity.h>
#include <jni.h>
#include <stddef.h>

#define WEGERT_TAG "IdricWegert"
#define WEGERT_JNI_SENTINEL 47047

JNIEXPORT jint JNICALL
Java_org_isomorphisms_wegert_WegertActivity_jniProbe(JNIEnv *environment,
                                                      jclass activity_class) {
    (void) environment;
    (void) activity_class;
    const jint result = WEGERT_JNI_SENTINEL;
    __android_log_print(ANDROID_LOG_INFO, WEGERT_TAG,
                        "jniProbe=%d", (int) result);
    return result;
}

void ANativeActivity_onCreate(ANativeActivity *activity,
                              void *saved_state,
                              size_t saved_state_size) {
    (void) activity;
    (void) saved_state;
    (void) saved_state_size;
    __android_log_print(ANDROID_LOG_INFO, WEGERT_TAG,
                        "ANativeActivity_onCreate");
}
