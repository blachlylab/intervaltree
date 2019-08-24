/** Interval Tree backed by Implicit Augmented Interval Tree, by Heng Li

    See: https://github.com/lh3/cgranges/

    Wrapper copyright: Copyright 2019 James S Blachly, MD
    Wrapper license: MIT
*/
module intervaltree.iitree;

import core.stdc.stdlib;    // malloc
import core.stdc.string;    // memcpy
import core.stdc.stdint;

import core.memory;

import std.bitmanip;
import std.string : toStringz;
import std.traits;

debug import std.stdio;

import intervaltree.cgranges;

/** Implicit Interval Tree */
struct IITree(IntervalType)
if (__traits(hasMember, IntervalType, "start") &&
    __traits(hasMember, IntervalType, "end"))
{
    cgranges_t* cr;     /// encapsulated range
    debug bool indexed; /// ensure the IITree is indexed before query

    invariant
    {
        assert(this.cr !is null);
    }
    ~this()
    {
        if (this.cr !is null)
            cr_destroy(this.cr);
    }
    @disable this(this);    /// if reenable, must add refcounting and check to destructor

    alias add = insert; // prior API 

    /// Insert interval for contig
    ///
    /// Note this differs from the other trees in the package in inclusion of "contig" parameter,
    /// because underlying cgranges has built-in hashmap and essentially stores multiple trees.
    /// Passing a \0-terminated C string contig will be faster than passing a D string or char[],
    /// due to the need to call toStringz before calling the C API.
    ///
    /// last param "label" of cr_add not used by cgranges as of 2019-05-04
    ///
    /// Params:
    ///     S = string-like contig name (if absent will pass "default" to cr_add)
    ///     i = IntervalType or IntervalType*
    ///     trackGC = (Default true) add i to the GC scanned ranges. see discussion
    ///     GCptr   = (Default true) when i is IntervalType*, is the pointer to GC-mgd memory?
    ///
    /// Discussion:
    ///     This container structure may store an IntervalType in one of two ways.
    ///     First, you can pass a pointer which will be stored directly without additional
    ///     memory allocations. Note however that if this pointer is to garbage collected
    ///     memory and no other reference exists in the D code, it could be swept away.
    ///     Even if it is not to GC memory, if it encapsulates a pointer (e.g., a string )
    ///     you can still be bitten. Thus trackGC defaults to true. If unneeded, you might
    ///     obtain a marginal speedup by setting trackGC = false.
    ///
    ///     The interval to be contained may also be passed by value. In this case,
    ///     memory will be allocated with malloc and the pointer will be stored. In this case
    ///     the same caveats regarding contained GC-pointing objects like D-arrays and strings
    ///     still apply. For example, passing a struct by value may not necessitate tracking
    ///     the memory in the GC if it contains only value types, but if the struct contains
    ///     a D-style array or string, it must be tracked
    ///
    ///     Finally, there is a variant missing the first contig parameter. Unlike other trees,
    ///     cgranges requires a string contig parameter, so a default value of "default"
    ///     will be supplied.
    cr_intv_t* insert(S)(S contig, IntervalType* i, bool trackGC = true, bool GCptr = true)
    if(isSomeString!S || is(S: const(char)*))
    in ( i !is null )
    {
        if (GCptr)  // i is ptr to GC-managed memory
            GC.addRoot(i);
        else        // i is ptr to non-GC heap mem but may contain ptr to GC-mem
            if (trackGC) GC.addRange(i, IntervalType.sizeof, typeid(IntervalType));

        static if (isSomeString!S)
            return cr_add(this.cr, toStringz(contig), i.start, i.end, 0, i);
        else
            return cr_add(this.cr, contig, i.start, i.end, 0, i);
    }
    /// ditto
    cr_intv_t* insert(S)(S contig, IntervalType i, bool trackGC = true)
    if(isSomeString!S || is(S: const(char)*))
    {
        // TODO: this is a direct leak reported by LSAN (was indirect until i added free(cr->r) in cgranges.c)
        IntervalType* iheap = cast(IntervalType *) malloc(IntervalType.sizeof);
        memcpy(iheap, &i, IntervalType.sizeof);
        if (trackGC) GC.addRange(iheap, IntervalType.sizeof, typeid(IntervalType));
        
        static if (isSomeString!S)
            return cr_add(this.cr, toStringz(contig), i.start, i.end, 0, iheap);
        else
            return cr_add(this.cr, contig, i.start, i.end, 0, iheap);
    }
    /// ditto
    cr_intv_t* insert(I)(I i, bool trackGC = true)
    {
        pragma(inline,true);
        immutable(char) *contig = "default";
        insert(contig, i, trackGC);
    }

    /// Index the data structure -- required after all inserts completed, before query
    @nogc nothrow
    void index()
    {
        cr_index(this.cr);
        debug { this.indexed = true; }
    }

    /// Locate and return intervals overlapping parameter qinterval in contig
    ///
    /// qinterval must have members "start" and "end" (just like IntervalType
    /// stored in the tree, but the types needn't be the same).
    ///
    /// Note that because the cgranges IITree stores contig this must be included,
    /// unlike the other interval tree implementations.
    ///
    /// findOverlapsWith may also be called with \0-terminated contig, integer start, end
    auto findOverlapsWith(T)(const(char)[] contig, T qinterval)
    if (__traits(hasMember, T, "start") &&
    __traits(hasMember, T, "end"))
    {
        version(DigitalMars) pragma(inline);
        version(GDC) pragma(inline, true);
        version(LDC) pragma(inline, true);
        return findOverlapsWith(toStringz(contig), qinterval.start, qinterval.end);
    }
    /// ditto
    const(cr_intv_t)[] findOverlapsWith(const(char)* contig, int start, int end)
    {
        debug
        {
            if (!this.indexed) {
                stderr.writeln("WARNING cgranges: query before index!");
                this.index();
            }
        }

        // static to prevent cr_overlap from calling malloc/realloc every time
        // TODO should move to struct level then free(b) in destructor
        static int64_t *b;
        static int64_t m_b;
        const auto n_b = cr_overlap(this.cr, contig, start, end, &b, &m_b);
        if (!n_b) return [];

        if (n_b == 1)
            return this.cr.r[b[0] .. (b[0] + 1)];
        else {
            // can't do this.cr.r[b[0] .. (b[0] + n_b)] because elements of b[] may not be contiguous throughout r
            // PROOF:
            // consider intervals (3,10) (4, 6) (5, 12) (6, 20) (7,15) which lie in r[] sorted by start coord
            // coordinate 7 overlaps first and last
            /+ WORKS +/
            cr_intv_t[] ret;
            ret.length = n_b;
            for(int i; i<n_b; i++)
            {
                ret[i] = this.cr.r[b[i]];
            }
            return ret;
        }
        //const(cr_intv_t)[] ret = this.cr.r[b[0] .. (b[0] + n_b)];
        //return ret;
    }
}