.class public final LIdric/Runner;
.super Ljava/lang/Object;

# This is an external runtime harness, not the candidate backend. Every value
# under test is computed by a method in the directly encoded candidate DEX.
.method public static main([Ljava/lang/String;)V
    .registers 4

    const/16 v0, 12
    const/16 v1, 7
    invoke-static {v0, v1}, LIdric/Generated;->add(II)I
    move-result v2
    const/16 v3, 19
    if-ne v2, v3, :fail_add

    invoke-static {}, LIdric/Generated;->add_constants()I
    move-result v2
    if-ne v2, v3, :fail_add_constants

    invoke-static {v0}, LIdric/Generated;->copy(I)I
    move-result v2
    if-ne v2, v0, :fail_copy

    invoke-static {v0, v1}, LIdric/Generated;->subtract(II)I
    move-result v2
    const/4 v3, 5
    if-ne v2, v3, :fail_subtract

    invoke-static {v0, v1}, LIdric/Generated;->multiply(II)I
    move-result v2
    const/16 v3, 84
    if-ne v2, v3, :fail_multiply

    const/16 v0, 7
    const/16 v1, 12
    invoke-static {v0, v1}, LIdric/Generated;->choose_less(II)I
    move-result v2
    const/16 v3, 41
    if-ne v2, v3, :fail_branch_true

    const/16 v0, 12
    const/16 v1, 7
    invoke-static {v0, v1}, LIdric/Generated;->choose_less(II)I
    move-result v2
    const/16 v3, 99
    if-ne v2, v3, :fail_branch_false

    invoke-static {}, LIdric/Generated;->negative()I
    move-result v2
    const v3, -32769
    if-ne v2, v3, :fail_negative

    invoke-static {}, LIdric/Generated;->constant_4_min()I
    move-result v2
    const/4 v3, -8
    if-ne v2, v3, :fail_constant_4_min

    invoke-static {}, LIdric/Generated;->constant_4_max()I
    move-result v2
    const/4 v3, 7
    if-ne v2, v3, :fail_constant_4_max

    invoke-static {}, LIdric/Generated;->constant_16_min()I
    move-result v2
    const/16 v3, -32768
    if-ne v2, v3, :fail_constant_16_min

    invoke-static {}, LIdric/Generated;->constant_16_max()I
    move-result v2
    const/16 v3, 32767
    if-ne v2, v3, :fail_constant_16_max

    invoke-static {}, LIdric/Generated;->constant_32_min()I
    move-result v2
    const v3, -32769
    if-ne v2, v3, :fail_constant_32_min

    invoke-static {}, LIdric/Generated;->constant_32_max()I
    move-result v2
    const v3, 32768
    if-ne v2, v3, :fail_constant_32_max

    invoke-static {}, LIdric/Generated;->constant_min()I
    move-result v2
    const v3, -2147483648
    if-ne v2, v3, :fail_min

    invoke-static {}, LIdric/Generated;->constant_max()I
    move-result v2
    const v3, 2147483647
    if-ne v2, v3, :fail_max

    const/4 v0, 0
    invoke-static {v0}, Ljava/lang/System;->exit(I)V
    return-void

:fail_add
    const/16 v0, 41
    goto :exit
:fail_add_constants
    const/16 v0, 42
    goto :exit
:fail_subtract
    const/16 v0, 44
    goto :exit
:fail_multiply
    const/16 v0, 45
    goto :exit
:fail_branch_true
    const/16 v0, 46
    goto :exit
:fail_branch_false
    const/16 v0, 47
    goto :exit
:fail_negative
    const/16 v0, 48
    goto :exit
:fail_constant_4_min
    const/16 v0, 49
    goto :exit
:fail_constant_4_max
    const/16 v0, 50
    goto :exit
:fail_constant_16_min
    const/16 v0, 51
    goto :exit
:fail_constant_16_max
    const/16 v0, 52
    goto :exit
:fail_constant_32_min
    const/16 v0, 53
    goto :exit
:fail_constant_32_max
    const/16 v0, 54
    goto :exit
:fail_min
    const/16 v0, 55
    goto :exit
:fail_max
    const/16 v0, 56
    goto :exit

:fail_copy
    const/16 v0, 43

:exit
    invoke-static {v0}, Ljava/lang/System;->exit(I)V
    return-void
.end method
