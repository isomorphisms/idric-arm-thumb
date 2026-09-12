.class public Lorg/isomorphisms/reddit/RedditCli;
.super Ljava/lang/Object;

.method public static main([Ljava/lang/String;)V
    .registers 2

    const-string v0, "reddit.library"
    invoke-static {v0}, Ljava/lang/System;->getProperty(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    invoke-static {v0}, Ljava/lang/System;->load(Ljava/lang/String;)V
    invoke-static {p0}, Lorg/isomorphisms/reddit/RedditCli;->run([Ljava/lang/String;)V
    return-void
.end method

.method public static native run([Ljava/lang/String;)V
.end method
