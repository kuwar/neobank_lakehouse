from pyspark.sql import functions as F
from pyspark.sql import types as T


def null_count_expr(c, dtype):
    """
    null
    ----
    => is the absence of a value
    => it applies to any column type (string, int, double, date, boolean, etc.)
    
    NaN ("Not a Number")
    ----
    => NaN is an actual floating-point value
    => only exists in float and double columns
    => It arises from numeric operations rather than missing data, e.g. 0.0/0.0, sqrt(-1), or reading the literal token "NaN" into a double column.

    Note: They don't overlap. isNull() will not catch a NaN, and isnan() will not catch a null — and isnan() errors if called on a non-numeric column
    """
    cond = F.isnull(F.col(c))
    if isinstance(dtype, (T.DoubleType, T.FloatType)):
        cond = cond | F.isnan(F.col(c))
    return F.count(F.when(cond, c)).alias(c)