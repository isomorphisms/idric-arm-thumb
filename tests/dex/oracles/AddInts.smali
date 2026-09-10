.class public final LIdricDexAddInts;
.super Ljava/lang/Object;

# Bootstrap oracle for:
#   a ← 12
#   b ← 7
#   c ← a + b
#   return c
#
# This is not generated yet. It pins the first DEX lowering target.
.method public static add()I
    .registers 3

    const/16 v0, 12
    const/16 v1, 7
    add-int v2, v0, v1
    return v2
.end method
