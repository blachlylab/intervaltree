module intervaltree;

/// Interval with zero-based, half-open coordinates
/// Any other Interval struct (or class?) OK
/// as long as it contains "start" and "end"
struct BasicInterval
{
    int start;  /// zero-based half-open
    int end;    /// zero-based half-open

    /// override the <, <=, >, >= operators; we'll use compiler generated default opEqual
    @nogc nothrow
    int opCmp(const ref BasicInterval other) const 
    {		
		if (this.start < other.start) return -1;
		else if(this.start > other.start) return 1;
		else if(this.start == other.start && this.end < other.end) return -1;	// comes third as should be less common
		else if(this.start == other.start && this.end > other.end) return 1;
		else return 0;	// would be reached in case of equality
    }
    /// override <, <=, >, >= to compare directly to int: compare only the start coordinate
    @nogc nothrow
    int opCmp(const int other) const 
    {
        return this.start - other;
    }

    string toString() const
	{
        import std.format : format;
		return format("[%d, %d)", this.start, this.end);
	}

    invariant
    {
        assert(this.start <= this.end);
    }
}

/** Detect overlap between this interval and other given interval
    in a half-open coordinate system [start, end)

Top-level function template for reuse by many types of Interval objects
Template type parameter Interval Type must have {start, end}
Still usable with member-function style due to UFCS: interval.overlaps(other)

return true in any of the following four situations:
    int1   =====    =======
    int2  =======  =======
    
    int1  =======  =======
    int2    ===      =======

return false in any other scenario:
    int1  =====       |       =====
    int2       =====  |  =====

NOTE that in half-open coordinates [start, end)
 i1.end == i2.start => Adjacent, but NO overlap
*/
@nogc pure @safe nothrow
bool overlaps(IntervalType1, IntervalType2)(IntervalType1 int1, IntervalType2 int2)
if (__traits(hasMember, IntervalType1, "start") &&
    __traits(hasMember, IntervalType1, "end") &&
    __traits(hasMember, IntervalType2, "start") &&
    __traits(hasMember, IntervalType2, "end"))
{
    // DMD cannot inline this
    version(LDC) pragma(inline, true);
    version(GDC) pragma(inline, true);
    // int1   =====    =======
    // int2 =======  =======
    if (int2.start <= int1.start &&  int1.start < int2.end) return true;

    // int1  =======  =======
    // int2   ===      =======
    else if (int1.start <= int2.start && int2.start < int1.end) return true;

    // int1  =====        |       =====
    // int2       =====   |  =====
    else return false;
}