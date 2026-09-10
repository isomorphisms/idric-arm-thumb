.class public Lorg/isomorphisms/wegert/WegertActivity;
.super Landroid/app/NativeActivity;

.method static constructor <clinit>()V
    .registers 1

    const-string v0, "wegert"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    return-void
.end method

.method public constructor <init>()V
    .registers 1

    invoke-direct {p0}, Landroid/app/NativeActivity;-><init>()V
    return-void
.end method

.method public static native jniProbe()I
.end method

.method protected onCreate(Landroid/os/Bundle;)V
    .registers 2

    invoke-static {}, Lorg/isomorphisms/wegert/WegertActivity;->jniProbe()I
    invoke-super {p0, p1}, Landroid/app/NativeActivity;->onCreate(Landroid/os/Bundle;)V
    return-void
.end method
