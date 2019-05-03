/** Interval Tree backed by Implicit Augmented Interval Tree, by lh3

    See: https://github.com/lh3/cgranges/
*/
module intervaltree.cgranges;

import core.stdc.stdint;
import std.bitmanip;
import std.string : toStringz;

debug import std.stdio;

/** Implicit Interval Tree */
struct IITree(IntervalType)
if (__traits(hasMember, IntervalType, "start") &&
    __traits(hasMember, IntervalType, "end"))
{
    cgranges_t* cr; /// encapsulated range
    debug {
        bool indexed;   /// in debug mode, make sure the IITree is indexed before query
    }

    invariant
    {
        assert(this.cr !is null);
    }
    ~this()
    {
        if (this.cr !is null)
            cr_destroy(this.cr);
    }

    ///
    cr_intv_t* add(string contig, IntervalType i)
    {
        return cr_add(this.cr, toStringz(contig), i.start, i.end, 0);
    }

    /// 
    void index()
    {
        cr_index(this.cr);
        debug { this.indexed = true; }
    }

    /// 
    cr_intv_t*[] findOverlapsWith(T)(string contig, T qinterval)
    if (__traits(hasMember, T, "start") &&
    __traits(hasMember, T, "end"))
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
        const auto n_b = cr_overlap(this.cr, toStringz(contig), qinterval.start, qinterval.end, &b, &m_b);

        cr_intv_t*[] ret;
        ret.length = n_b;
        for(int i; i<n_b; i++)
        {
            ret[i] = &this.cr.r[b[i]];
        }

        return ret;
    }
}

extern(C):

/* The MIT License
   Copyright (c) 2019 Dana-Farber Cancer Institute
   Permission is hereby granted, free of charge, to any person obtaining
   a copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to
   permit persons to whom the Software is furnished to do so, subject to
   the following conditions:
   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
*/

struct cr_ctg_t {    // a contig
	char *name;     // name of the contig
	int32_t len;    // max length seen in data
	int32_t root_k;
	int64_t n, off; // sum of lengths of previous contigs
}

struct cr_intv_t {    // an interval
	uint64_t x;     // prior to cr_index(), x = ctg_id<<32|start_pos; after: x = start_pos<<32|end_pos
	//uint32_t y:31, rev:1;
    mixin(bitfields!(
        uint32_t, "y", 31,
        uint32_t, "rev", 1
    ));
	int32_t label;  // NOT used
}

struct cgranges_t {
	int64_t n_r, m_r;     // number and max number of intervals
	cr_intv_t *r;         // list of intervals (of size _n_r_)
	int32_t n_ctg, m_ctg; // number and max number of contigs
	cr_ctg_t *ctg;        // list of contigs (of size _n_ctg_)
	void *hc;             // dictionary for converting contig names to integers
}

/// retrieve start and end positions from a cr_intv_t object
pragma(inline, true)
{
int32_t cr_st(const cr_intv_t *r) { return cast(int32_t)(r.x>>32); }
int32_t cr_en(const cr_intv_t *r) { return cast(int32_t)r.x; }
int32_t cr_start(const cgranges_t *cr, int64_t i) { return cr_st(&cr.r[i]); }
int32_t cr_end(const cgranges_t *cr, int64_t i) { return cr_en(&cr.r[i]); }
int32_t cr_label(const cgranges_t *cr, int64_t i) { return cr.r[i].label; }
}

/// Initialize
cgranges_t *cr_init();

/// Deallocate
void cr_destroy(cgranges_t *cr);

/// Add an interval
cr_intv_t *cr_add(cgranges_t *cr, const(char) *ctg, int32_t st, int32_t en, int32_t label_int);

/// Sort and index intervals
void cr_index(cgranges_t *cr);

/** Find (and count) overlaps

    Params:
        cr   =  cgranges struct
        ctg  =  contig \0 term Cstring
        st   =  start coord
        en   =  end coord
        b    =  array (returned)
        m_b_ =  max b
*/
int64_t cr_overlap(const(cgranges_t) *cr, const(char) *ctg, int32_t st, int32_t en, int64_t **b_, int64_t *m_b_);

/// Add a contig and length. Call this for desired contig ordering. _len_ can be 0.
int32_t cr_add_ctg(cgranges_t *cr, const(char) *ctg, int32_t len);

/// Get the contig ID given its name
int32_t cr_get_ctg(const cgranges_t *cr, const(char) *ctg);