cpdef enum Diff:
    single
    double
    n_diff


cpdef enum Parameter:
    intercept = 0
    slope = 1


cpdef enum Variance:
    read_var = 0
    poisson_var = 1
    total_var = 2


cpdef enum RampJumpDQ:
    JUMP_DET = 4
