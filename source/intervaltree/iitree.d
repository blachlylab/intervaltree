/** Interval Tree backed by Implicit Augmented Interval Tree, by Heng Li

    See: https://github.com/lh3/cgranges/

    Wrapper copyright: Copyright 2019 James S Blachly, MD
    Wrapper license: MIT
*/
module intervaltree.iitree;

import core.stdc.stdlib;    // malloc
import core.stdc.string;    // memcpy

import core.stdc.stdint;
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
    // 2019-05-21, if use GC would have to register the memory, just use malloc instead
    // TODO free() in ~this
    cr_intv_t* insert(S)(S contig, IntervalType i)
    if(isSomeString!S || is(S: const(char)*))
    {
        IntervalType* iheap = cast(IntervalType *) malloc(IntervalType.sizeof);
        memcpy(iheap, &i, IntervalType.sizeof);
        static if (isSomeString!S)
            return cr_add(this.cr, toStringz(contig), i.start, i.end, 0, iheap);
        else
            return cr_add(this.cr, contig, i.start, i.end, 0, iheap);
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
        pragma(inline, true);
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

        int64_t *b;
        int64_t m_b;
        const auto n_b = cr_overlap(this.cr, contig, start, end, &b, &m_b);
        if (!n_b) return [];

        /+ WORKS
        cr_intv_t[] ret;
        ret.length = n_b;
        for(int i; i<n_b; i++)
        {
            ret[i] = this.cr.r[b[i]];
        }+/
        
        const(cr_intv_t)[] ret = this.cr.r[b[0] .. (b[0] + n_b)];
        return ret;
    }
}