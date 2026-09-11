#include <jni.h>

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) {
    fprintf(stderr, "reddit: %s\n", message);
    fflush(stderr);
    exit(1);
}

static void usage(void) {
    fprintf(stderr, "usage: reddit {url QUERY | search QUERY}\n");
    fflush(stderr);
    exit(2);
}

static void jni_check(JNIEnv *env, const char *stage) {
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        fprintf(stderr, "reddit: Android runtime failure during %s\n", stage);
        fflush(stderr);
        exit(1);
    }
}

static jclass require_class(JNIEnv *env, const char *name) {
    jclass cls = (*env)->FindClass(env, name);
    jni_check(env, name);
    if (cls == NULL) fail("required Android class not found");
    return cls;
}

static jmethodID require_method(
    JNIEnv *env, jclass cls, const char *name, const char *signature
) {
    jmethodID method = (*env)->GetMethodID(env, cls, name, signature);
    jni_check(env, name);
    if (method == NULL) fail("required Android method not found");
    return method;
}

static char *copy_java_utf8(JNIEnv *env, jstring value) {
    if (value == NULL) {
        char *empty = malloc(1);
        if (empty == NULL) fail("out of memory");
        empty[0] = '\0';
        return empty;
    }

    jclass string_class = require_class(env, "java/lang/String");
    jmethodID get_bytes = require_method(
        env, string_class, "getBytes", "(Ljava/lang/String;)[B"
    );
    jstring utf8 = (*env)->NewStringUTF(env, "UTF-8");
    jni_check(env, "UTF-8 encoding selection");
    jbyteArray bytes = (jbyteArray)(*env)->CallObjectMethod(
        env, value, get_bytes, utf8
    );
    jni_check(env, "String.getBytes");

    jsize length = (*env)->GetArrayLength(env, bytes);
    char *result = malloc((size_t)length + 1);
    if (result == NULL) fail("out of memory");
    if (length > 0) {
        (*env)->GetByteArrayRegion(env, bytes, 0, length, (jbyte *)result);
        jni_check(env, "copying UTF-8 text");
    }
    result[length] = '\0';

    (*env)->DeleteLocalRef(env, bytes);
    (*env)->DeleteLocalRef(env, utf8);
    (*env)->DeleteLocalRef(env, string_class);
    return result;
}

static jstring java_string_from_utf8(
    JNIEnv *env, const unsigned char *bytes, size_t length
) {
    if (length > (size_t)INT32_MAX) fail("response is too large");

    jclass string_class = require_class(env, "java/lang/String");
    jmethodID constructor = require_method(
        env, string_class, "<init>", "([BLjava/lang/String;)V"
    );
    jbyteArray data = (*env)->NewByteArray(env, (jsize)length);
    jni_check(env, "allocating response string");
    if (length > 0) {
        (*env)->SetByteArrayRegion(
            env, data, 0, (jsize)length, (const jbyte *)bytes
        );
        jni_check(env, "copying response string");
    }
    jstring utf8 = (*env)->NewStringUTF(env, "UTF-8");
    jni_check(env, "UTF-8 encoding selection");
    jstring result = (jstring)(*env)->NewObject(
        env, string_class, constructor, data, utf8
    );
    jni_check(env, "decoding UTF-8 response");

    (*env)->DeleteLocalRef(env, data);
    (*env)->DeleteLocalRef(env, utf8);
    (*env)->DeleteLocalRef(env, string_class);
    return result;
}

static char *argument(JNIEnv *env, jobjectArray arguments, jsize index) {
    jstring value = (jstring)(*env)->GetObjectArrayElement(env, arguments, index);
    jni_check(env, "reading command argument");
    char *result = copy_java_utf8(env, value);
    (*env)->DeleteLocalRef(env, value);
    return result;
}

static int unreserved(unsigned char byte) {
    return isalnum(byte) || byte == '-' || byte == '.' || byte == '_' || byte == '~';
}

static char *percent_encode(const char *text) {
    static const char hex[] = "0123456789ABCDEF";
    size_t length = strlen(text);
    if (length > (SIZE_MAX - 1) / 3) fail("query is too large");
    char *encoded = malloc(length * 3 + 1);
    if (encoded == NULL) fail("out of memory");

    char *out = encoded;
    const unsigned char *in = (const unsigned char *)text;
    while (*in != '\0') {
        unsigned char byte = *in++;
        if (unreserved(byte)) {
            *out++ = (char)byte;
        } else {
            *out++ = '%';
            *out++ = hex[byte >> 4];
            *out++ = hex[byte & 15];
        }
    }
    *out = '\0';
    return encoded;
}

static char *search_url(const char *query) {
    const char *prefix =
        "https://oauth.reddit.com/search?raw_json=1&limit=25&sort=relevance&t=all&q=";
    char *encoded = percent_encode(query);
    size_t total = strlen(prefix) + strlen(encoded) + 1;
    char *url = malloc(total);
    if (url == NULL) fail("out of memory");
    snprintf(url, total, "%s%s", prefix, encoded);
    free(encoded);
    return url;
}

static unsigned char *http_get(
    JNIEnv *env,
    const char *url_text,
    const char *token,
    const char *user_agent,
    size_t *result_length
) {
    jclass url_class = require_class(env, "java/net/URL");
    jmethodID url_constructor = require_method(
        env, url_class, "<init>", "(Ljava/lang/String;)V"
    );
    jmethodID open_connection = require_method(
        env, url_class, "openConnection", "()Ljava/net/URLConnection;"
    );

    jstring url_string = (*env)->NewStringUTF(env, url_text);
    jni_check(env, "creating search URL");
    jobject url = (*env)->NewObject(env, url_class, url_constructor, url_string);
    jni_check(env, "creating search URL");
    jobject connection = (*env)->CallObjectMethod(env, url, open_connection);
    jni_check(env, "opening HTTPS connection");

    jclass connection_class = require_class(env, "java/net/URLConnection");
    jmethodID set_property = require_method(
        env,
        connection_class,
        "setRequestProperty",
        "(Ljava/lang/String;Ljava/lang/String;)V"
    );
    jmethodID set_connect_timeout = require_method(
        env, connection_class, "setConnectTimeout", "(I)V"
    );
    jmethodID set_read_timeout = require_method(
        env, connection_class, "setReadTimeout", "(I)V"
    );
    jmethodID get_input_stream = require_method(
        env, connection_class, "getInputStream", "()Ljava/io/InputStream;"
    );

    size_t bearer_length = strlen(token) + sizeof("Bearer ");
    char *bearer = malloc(bearer_length);
    if (bearer == NULL) fail("out of memory");
    snprintf(bearer, bearer_length, "Bearer %s", token);

    jstring authorization_name = (*env)->NewStringUTF(env, "Authorization");
    jstring authorization_value = (*env)->NewStringUTF(env, bearer);
    jstring agent_name = (*env)->NewStringUTF(env, "User-Agent");
    jstring agent_value = (*env)->NewStringUTF(env, user_agent);
    free(bearer);
    jni_check(env, "creating request headers");

    (*env)->CallVoidMethod(
        env, connection, set_property, authorization_name, authorization_value
    );
    jni_check(env, "setting Authorization header");
    (*env)->CallVoidMethod(env, connection, set_property, agent_name, agent_value);
    jni_check(env, "setting User-Agent header");
    (*env)->CallVoidMethod(env, connection, set_connect_timeout, 15000);
    jni_check(env, "setting connect timeout");
    (*env)->CallVoidMethod(env, connection, set_read_timeout, 30000);
    jni_check(env, "setting read timeout");

    jclass http_class = require_class(env, "java/net/HttpURLConnection");
    jmethodID response_code = require_method(
        env, http_class, "getResponseCode", "()I"
    );
    jint status = (*env)->CallIntMethod(env, connection, response_code);
    jni_check(env, "reading HTTP status");
    if (status < 200 || status >= 300) {
        fprintf(stderr, "reddit: HTTP status %d\n", (int)status);
        fflush(stderr);
        exit(1);
    }

    jobject stream = (*env)->CallObjectMethod(env, connection, get_input_stream);
    jni_check(env, "opening response body");
    jclass stream_class = require_class(env, "java/io/InputStream");
    jmethodID read = require_method(env, stream_class, "read", "([B)I");
    jmethodID close = require_method(env, stream_class, "close", "()V");
    jbyteArray block = (*env)->NewByteArray(env, 8192);
    jni_check(env, "allocating response buffer");

    size_t capacity = 16384;
    size_t length = 0;
    unsigned char *body = malloc(capacity + 1);
    if (body == NULL) fail("out of memory");

    for (;;) {
        jint count = (*env)->CallIntMethod(env, stream, read, block);
        jni_check(env, "reading response body");
        if (count < 0) break;
        if (count == 0) continue;
        if (length + (size_t)count > 8 * 1024 * 1024) {
            fail("response exceeded 8 MiB limit");
        }
        if (length + (size_t)count > capacity) {
            while (length + (size_t)count > capacity) capacity *= 2;
            unsigned char *grown = realloc(body, capacity + 1);
            if (grown == NULL) fail("out of memory");
            body = grown;
        }
        (*env)->GetByteArrayRegion(
            env, block, 0, count, (jbyte *)(body + length)
        );
        jni_check(env, "copying response body");
        length += (size_t)count;
    }
    body[length] = '\0';
    (*env)->CallVoidMethod(env, stream, close);
    jni_check(env, "closing response body");

    (*env)->DeleteLocalRef(env, block);
    (*env)->DeleteLocalRef(env, stream_class);
    (*env)->DeleteLocalRef(env, stream);
    (*env)->DeleteLocalRef(env, http_class);
    (*env)->DeleteLocalRef(env, agent_value);
    (*env)->DeleteLocalRef(env, agent_name);
    (*env)->DeleteLocalRef(env, authorization_value);
    (*env)->DeleteLocalRef(env, authorization_name);
    (*env)->DeleteLocalRef(env, connection_class);
    (*env)->DeleteLocalRef(env, connection);
    (*env)->DeleteLocalRef(env, url);
    (*env)->DeleteLocalRef(env, url_string);
    (*env)->DeleteLocalRef(env, url_class);

    *result_length = length;
    return body;
}

static void write_clean(const char *text) {
    for (const unsigned char *p = (const unsigned char *)text; *p != '\0'; ++p) {
        unsigned char byte = *p;
        if (byte == '\t' || byte == '\r' || byte == '\n') byte = ' ';
        fputc((int)byte, stdout);
    }
}

static void print_listing(JNIEnv *env, const unsigned char *body, size_t body_length) {
    jclass object_class = require_class(env, "org/json/JSONObject");
    jclass array_class = require_class(env, "org/json/JSONArray");
    jmethodID object_constructor = require_method(
        env, object_class, "<init>", "(Ljava/lang/String;)V"
    );
    jmethodID get_object = require_method(
        env,
        object_class,
        "getJSONObject",
        "(Ljava/lang/String;)Lorg/json/JSONObject;"
    );
    jmethodID get_array = require_method(
        env,
        object_class,
        "getJSONArray",
        "(Ljava/lang/String;)Lorg/json/JSONArray;"
    );
    jmethodID opt_long = require_method(
        env, object_class, "optLong", "(Ljava/lang/String;)J"
    );
    jmethodID opt_string = require_method(
        env,
        object_class,
        "optString",
        "(Ljava/lang/String;)Ljava/lang/String;"
    );
    jmethodID array_length = require_method(env, array_class, "length", "()I");
    jmethodID array_object = require_method(
        env, array_class, "getJSONObject", "(I)Lorg/json/JSONObject;"
    );

    jstring body_string = java_string_from_utf8(env, body, body_length);
    jobject root = (*env)->NewObject(env, object_class, object_constructor, body_string);
    jni_check(env, "decoding Reddit JSON");

    jstring key_data = (*env)->NewStringUTF(env, "data");
    jstring key_children = (*env)->NewStringUTF(env, "children");
    jstring key_created = (*env)->NewStringUTF(env, "created_utc");
    jstring key_score = (*env)->NewStringUTF(env, "score");
    jstring key_subreddit = (*env)->NewStringUTF(env, "subreddit");
    jstring key_author = (*env)->NewStringUTF(env, "author");
    jstring key_title = (*env)->NewStringUTF(env, "title");
    jstring key_permalink = (*env)->NewStringUTF(env, "permalink");
    jni_check(env, "creating Reddit JSON keys");

    jobject data = (*env)->CallObjectMethod(env, root, get_object, key_data);
    jni_check(env, "reading Reddit listing data");
    jobject children = (*env)->CallObjectMethod(env, data, get_array, key_children);
    jni_check(env, "reading Reddit listing children");
    jint count = (*env)->CallIntMethod(env, children, array_length);
    jni_check(env, "reading Reddit listing length");

    puts("created_utc\tscore\tsubreddit\tauthor\ttitle\tpermalink");

    for (jint index = 0; index < count; ++index) {
        jobject child = (*env)->CallObjectMethod(env, children, array_object, index);
        jni_check(env, "reading Reddit child");
        jobject post = (*env)->CallObjectMethod(env, child, get_object, key_data);
        jni_check(env, "reading Reddit post");

        jlong created = (*env)->CallLongMethod(env, post, opt_long, key_created);
        jlong score = (*env)->CallLongMethod(env, post, opt_long, key_score);
        jstring subreddit = (jstring)(*env)->CallObjectMethod(
            env, post, opt_string, key_subreddit
        );
        jstring author = (jstring)(*env)->CallObjectMethod(
            env, post, opt_string, key_author
        );
        jstring title = (jstring)(*env)->CallObjectMethod(
            env, post, opt_string, key_title
        );
        jstring permalink = (jstring)(*env)->CallObjectMethod(
            env, post, opt_string, key_permalink
        );
        jni_check(env, "reading Reddit post fields");

        char *subreddit_text = copy_java_utf8(env, subreddit);
        char *author_text = copy_java_utf8(env, author);
        char *title_text = copy_java_utf8(env, title);
        char *permalink_text = copy_java_utf8(env, permalink);

        printf("%lld\t%lld\t", (long long)created, (long long)score);
        write_clean(subreddit_text);
        fputc('\t', stdout);
        write_clean(author_text);
        fputc('\t', stdout);
        write_clean(title_text);
        fputc('\t', stdout);
        if (permalink_text[0] == '/') fputs("https://www.reddit.com", stdout);
        write_clean(permalink_text);
        fputc('\n', stdout);

        free(permalink_text);
        free(title_text);
        free(author_text);
        free(subreddit_text);
        (*env)->DeleteLocalRef(env, permalink);
        (*env)->DeleteLocalRef(env, title);
        (*env)->DeleteLocalRef(env, author);
        (*env)->DeleteLocalRef(env, subreddit);
        (*env)->DeleteLocalRef(env, post);
        (*env)->DeleteLocalRef(env, child);
    }
    fflush(stdout);

    (*env)->DeleteLocalRef(env, children);
    (*env)->DeleteLocalRef(env, data);
    (*env)->DeleteLocalRef(env, key_permalink);
    (*env)->DeleteLocalRef(env, key_title);
    (*env)->DeleteLocalRef(env, key_author);
    (*env)->DeleteLocalRef(env, key_subreddit);
    (*env)->DeleteLocalRef(env, key_score);
    (*env)->DeleteLocalRef(env, key_created);
    (*env)->DeleteLocalRef(env, key_children);
    (*env)->DeleteLocalRef(env, key_data);
    (*env)->DeleteLocalRef(env, root);
    (*env)->DeleteLocalRef(env, body_string);
    (*env)->DeleteLocalRef(env, array_class);
    (*env)->DeleteLocalRef(env, object_class);
}

JNIEXPORT void JNICALL
Java_org_isomorphisms_reddit_RedditCli_run(
    JNIEnv *env, jclass reddit_cli, jobjectArray arguments
) {
    (void)reddit_cli;

    jsize count = (*env)->GetArrayLength(env, arguments);
    if (count != 2) usage();

    char *command = argument(env, arguments, 0);
    char *query = argument(env, arguments, 1);
    char *url = search_url(query);

    if (strcmp(command, "url") == 0) {
        puts(url);
        fflush(stdout);
        free(url);
        free(query);
        free(command);
        return;
    }

    if (strcmp(command, "search") != 0) usage();

    const char *token = getenv("REDDIT_ACCESS_TOKEN");
    const char *user_agent = getenv("REDDIT_USER_AGENT");
    if (token == NULL || token[0] == '\0') fail("missing REDDIT_ACCESS_TOKEN");
    if (user_agent == NULL || user_agent[0] == '\0') fail("missing REDDIT_USER_AGENT");

    size_t body_length = 0;
    unsigned char *body = http_get(
        env, url, token, user_agent, &body_length
    );
    print_listing(env, body, body_length);

    free(body);
    free(url);
    free(query);
    free(command);
}
