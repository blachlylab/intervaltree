/** Interval Tree backed by augmented AVL tree

The AVL implementation is derived from attractivechaos'
klib (kavl.h) and the derived code remains MIT licensed.

Author: James S. Blachly, MD <james.blachly@gmail.com>
Copyright: Copyright (c) 2019 James Blachly
License for personal, academic, and noncomercial use: Apache 2.0
License for commercial use: Negotiable; contact author
*/
module intervaltree.avltree;

import intervaltree : BasicInterval, overlaps;

import containers.unrolledlist;

// LOL, this compares pointer addresses
//alias cmpfn = (x,y) => ((y < x) - (x < y));
@safe alias cmpfn = (x,y) => ((y.interval < x.interval) - (x.interval < y.interval));

/// child node direction
private enum DIR : int
{
    LEFT = 0,
    RIGHT = 1
}

///
private enum KAVL_MAX_DEPTH = 64;

///
pragma(inline, true)
@safe @nogc nothrow
auto kavl_size(T)(T* p) { return (p ? p.size : 0); }

///
pragma(inline, true)
@safe @nogc nothrow
auto kavl_size_child(T)(T* q, int i) { return (q.p[i] ? q.p[i].size : 0); }

/// Consumer needs to use this with insert functions (unlike splaytree fns, which take interval directly)
struct IntervalTreeNode(IntervalType)
if (__traits(hasMember, IntervalType, "start") &&
    __traits(hasMember, IntervalType, "end"))
{
    /// sort key
    pragma(inline,true)
    @property @safe @nogc nothrow const
    auto key() { return this.interval.start; }

    IntervalType interval;  /// must at a minimum include members start, end
    
    IntervalTreeNode*[2] p;     /// 0:left, 1:right
    // no parent pointer in KAVL implementation
    byte balance;   /// balance factor (signed, 8-bit)
    uint size;      /// #elements in subtree
    typeof(IntervalType.end) max;   /// maximum in this $(I subtree)

    /// non-default ctor: construct Node from interval, update max
    /// side note: D is beautiful in that Node(i) will work just fine
    /// without this constructor since its first member is IntervalType interval,
    /// but we need the constructor to update max.
    @nogc nothrow
    this(IntervalType i) 
    {
        this.interval = i;  // blit
        this.max = i.end;
    }

    invariant
    {
        // the Interval type itself should include checks, but in case it does not:
        assert(this.interval.start <= this.interval.end, "Interval start must <= end");

        assert(this.max >= this.interval.end, "max must be at least as high as our own end");

        // Ensure children are distinct
        if (this.p[DIR.LEFT] !is null && this.p[DIR.RIGHT] !is null)
        {
            assert(this.p[DIR.LEFT] != this.p[DIR.RIGHT], "Left and righ child appear identical");
        }
    }
}

///
struct IntervalAVLTree(IntervalType)
{
    alias Node = IntervalTreeNode!IntervalType;

    Node *root;    /// tree root

    /+
    /// needed for iterator / range
    const(Node)*[KAVL_MAX_DEPTH] itrstack; /// ?
    const(Node)** top;     /// _right_ points to the right child of *top
    const(Node)*  right;   /// _right_ points to the right child of *top
    +/

    /**
    * Find a node in the tree
    *
    * @param x       node value to find (in)
    * @param cnt     number of nodes smaller than or equal to _x_; can be NULL (out)
    *
    * @return node equal to _x_ if present, or NULL if absent
    */
    @trusted    // cannot be @safe: casts away const
    @nogc nothrow
    Node *find(const(Node) *x, out uint cnt) {

        const(Node)* p = this.root;

        while (p !is null) {
            const int cmp = cmpfn(x, p);
            if (cmp >= 0) cnt += kavl_size_child(p, DIR.LEFT) + 1; // left tree plus self

            if (cmp < 0) p = p.p[DIR.LEFT];         // descend leftward
            else if (cmp > 0) p = p.p[DIR.RIGHT];   // descend rightward
            else break;
        }

        return cast(Node*)p;    // not allowed in @safe, but is const only within this fn
    }

    /** find interval(s) overlapping given interval
        
        unlike find interval by key, matching elements could be in left /and/ right subtree

        We use template type "T" here instead of the enclosing struct's IntervalType
        so that we can from externally query with any type of interval object

        TODO: benchmark return Node[]
    */
    nothrow 
    // cannot be safe due to emsi container UnrolledList
    // cannot be @nogc due to return dynamic array
    Node*[] findOverlapsWith(T)(T qinterval)
    if (__traits(hasMember, T, "start") &&
        __traits(hasMember, T, "end"))
    {
        Node*[] ret;
        //ret.reserve(7);
        UnrolledList!(Node *) stack;

        Node* current;

        stack.insertBack(this.root);

        while(stack.length >= 1)
        {
            current = stack.moveBack();

            // if query interval lies to the right of current tree, skip  
            if (qinterval.start >= current.max) continue;

            // if query interval end is left of the current node's start,
            // look in the left subtree
            if (qinterval.end <= current.interval.start)
            {
                if (current.p[DIR.LEFT]) stack.insertBack(current.p[DIR.LEFT]);
                continue;
            }

            // if current node overlaps query interval, save it and search its children
            if (current.interval.overlaps(qinterval)) ret ~= current;
            if (current.p[DIR.LEFT]) stack.insertBack(current.p[DIR.LEFT]);
            if (current.p[DIR.RIGHT]) stack.insertBack(current.p[DIR.RIGHT]);
        }

        return ret;
    }

    /// /* one rotation: (a,(b,c)q)p => ((a,b)p,c)q */
    pragma(inline, true)
    @safe @nogc nothrow
    private
    Node *rotate1(Node *p, int dir) { /* dir=0 to left; dir=1 to right */
        const int opp = 1 - dir; /* opposite direction */
        Node *q = p.p[opp];
        const uint size_p = p.size;
        p.size -= q.size - kavl_size_child(q, dir);
        q.size = size_p;
        p.p[opp] = q.p[dir];
        q.p[dir] = p;

        //JSB: update max
        q.max = p.max;          // q came to top, can take p (prvious top)'s
        updateMax(p);

        return q;
    }

    /** two consecutive rotations: (a,((b,c)r,d)q)p => ((a,b)p,(c,d)q)r */
    pragma(inline, true)
    @safe @nogc nothrow
    private
    Node *rotate2(Node *p, int dir) {
        int b1;
        const int opp = 1 - dir;
        Node* q = p.p[opp];
        Node* r = q.p[dir];
        const uint size_x_dir = kavl_size_child(r, dir);
        r.size = p.size;
        p.size -= q.size - size_x_dir;
        q.size -= size_x_dir + 1;
        p.p[opp] = r.p[dir];
        r.p[dir] = p;
        q.p[dir] = r.p[opp];
        r.p[opp] = q;
        b1 = dir == 0 ? +1 : -1;
        if (r.balance == b1) q.balance = 0, p.balance = cast(byte)-b1;
        else if (r.balance == 0) q.balance = p.balance = 0;
        else q.balance = cast(byte)b1, p.balance = 0;
        r.balance = 0;

        //JSB: update max
        r.max = p.max;          // r came to top, can take p (prvious top)'s
        updateMax(p);
        updateMax(q);

        return r;
    }

    /**
    * Insert a node to the tree
    *
    *   Will update Node .max values on the way down
    *
    * @param x       node to insert (in)
    * @param cnt     number of nodes smaller than or equal to _x_; can be NULL (out)
    *
    * @return _x_ if not present in the tree, or the node equal to x.
    */
    @safe @nogc nothrow
    Node *insert(Node *x, out uint cnt)
    {
        
        ubyte[KAVL_MAX_DEPTH] stack;
        Node*[KAVL_MAX_DEPTH] path;

        Node* bp;
        Node* bq;
        Node* p;    // current node in iteration
        Node* q;    // parent of p
        Node* r = null; /* _r_ is potentially the new root */

        int i, which = 0, top, b1, path_len;

        bp = this.root, bq = null;
        /* find the insertion location */
        for (p = bp, q = bq, top = path_len = 0; p; q = p, p = p.p[which]) {
            const int cmp = cmpfn(x, p);
            if (cmp >= 0) cnt += kavl_size_child(p, DIR.LEFT) + 1; // left tree plus self
            if (cmp == 0) {
                // an identical Node is already present here
                return p;
            }
            if (p.balance != 0)
                bq = q, bp = p, top = 0;
            stack[top++] = which = (cmp > 0);
            path[path_len++] = p;

            // JSB: conditionally update max irrespective of whether we add new node, or descend
            if (x.interval.end > p.max) p.max = x.interval.end;
        }

        x.balance = 0, x.size = 1, x.p[DIR.LEFT] = x.p[DIR.RIGHT] = null;
        if (q is null) this.root = x;
        else q.p[which] = x;
        if (bp is null) return x;
        for (i = 0; i < path_len; ++i) ++path[i].size;
        for (p = bp, top = 0; p != x; p = p.p[stack[top]], ++top) /* update balance factors */
            if (stack[top] == 0) --p.balance;
            else ++p.balance;
        if (bp.balance > -2 && bp.balance < 2) return x; /* balance in [-1, 1] : no re-balance needed */
        /* re-balance */
        which = (bp.balance < 0);
        b1 = which == 0 ? +1 : -1;
        q = bp.p[1 - which];
        if (q.balance == b1) {
            r = rotate1(bp, which);
            q.balance = bp.balance = 0;
        } else r = rotate2(bp, which);
        if (bq is null) this.root = r;
        else bq.p[bp != bq.p[0]] = r;   // wow
        return x;
    }

    /**
    * Delete a node from the tree
    *
    * @param x       node value to delete; if NULL, delete the first (NB: NOT ROOT!) node (in)
    *
    * @return node removed from the tree if present, or NULL if absent
    */
    /+
    #define kavl_erase(suf, proot, x, cnt) kavl_erase_##suf(proot, x, cnt)
    #define kavl_erase_first(suf, proot) kavl_erase_##suf(proot, 0, 0)
    +/
    @trusted    // cannot be @safe: takes &fake
    @nogc nothrow
    Node *kavl_erase(const(Node) *x, out uint cnt) {
        Node* p;
        Node*[KAVL_MAX_DEPTH] path;
        Node fake;
        ubyte[KAVL_MAX_DEPTH] dir;
        int i, d = 0, cmp;
        fake.p[DIR.LEFT] = this.root, fake.p[DIR.RIGHT] = null;

        if (x !is null) {
            for (cmp = -1, p = &fake; cmp; cmp = cmpfn(x, p)) {
                const int which = (cmp > 0);
                if (cmp > 0) cnt += kavl_size_child(p, DIR.LEFT) + 1; // left tree plus self
                dir[d] = which;
                path[d++] = p;
                p = p.p[which];
                if (p is null) {
                    // node not found
                    return null;
                }
            }
            cnt += kavl_size_child(p, DIR.LEFT) + 1; /* because p==x is not counted */
        } else {    // NULL, delete the first node
            assert(x is null);
            // Descend leftward as far as possible, set p to this node
            for (p = &fake, cnt = 1; p; p = p.p[DIR.LEFT])
                dir[d] = 0, path[d++] = p;
            p = path[--d];
        }

        for (i = 1; i < d; ++i) --path[i].size;

        if (p.p[DIR.RIGHT] is null) { /* ((1,.)2,3)4 => (1,3)4; p=2 */
            path[d-1].p[dir[d-1]] = p.p[DIR.LEFT];
        } else {
            Node *q = p.p[DIR.RIGHT];
            if (q.p[0] is null) { /* ((1,2)3,4)5 => ((1)2,4)5; p=3 */
                q.p[0] = p.p[0];
                q.balance = p.balance;
                path[d-1].p[dir[d-1]] = q;
                path[d] = q, dir[d++] = 1;
                q.size = p.size - 1;
            } else { /* ((1,((.,2)3,4)5)6,7)8 => ((1,(2,4)5)3,7)8; p=6 */
                Node *r;
                int e = d++; /* backup _d_ */
                for (;;) {
                    dir[d] = 0;
                    path[d++] = q;
                    r = q.p[0];
                    if (r.p[0] is null) break;
                    q = r;
                }
                r.p[0] = p.p[0];
                q.p[0] = r.p[1];
                r.p[1] = p.p[1];
                r.balance = p.balance;
                path[e-1].p[dir[e-1]] = r;
                path[e] = r, dir[e] = 1;
                for (i = e + 1; i < d; ++i) --path[i].size;
                r.size = p.size - 1;
            }
        }

        // Rebalance on the way up
        while (--d > 0) {
            Node *q = path[d];
            int which, other, b1 = 1, b2 = 2;
            which = dir[d], other = 1 - which;
            if (which) b1 = -b1, b2 = -b2;
            q.balance += b1;
            if (q.balance == b1) break;
            else if (q.balance == b2) {
                Node *r = q.p[other];
                if (r.balance == -b1) {
                    path[d-1].p[dir[d-1]] = rotate2(q, which);
                } else {
                    path[d-1].p[dir[d-1]] = rotate1(q, which);
                    if (r.balance == 0) {
                        r.balance = cast(byte) -b1;
                        q.balance = cast(byte) b1;
                        break;
                    } else r.balance = q.balance = 0;
                }
            }
        }
        this.root = fake.p[0];
        return p;
    }

    /** update Node n's max from subtrees
    
    Params:
        n = node to update
    */
    pragma(inline, true)
    @safe @nogc nothrow
    private
    void updateMax(Node *n) 
    {
        import std.algorithm.comparison : max;

        if (n !is null)
        {
            int localmax = n.interval.end;
            if (n.p[DIR.LEFT])
                localmax = max(n.p[DIR.LEFT].max, localmax);
            if (n.p[DIR.RIGHT])
                localmax = max(n.p[DIR.RIGHT].max, localmax);
            n.max = localmax;

        }
    }

    // TODO: iterator as InputRange
}
unittest
{
    // module-level unit test
    import std.stdio : write, writeln;
    write(__MODULE__ ~ " unittest ...");

    auto tree = new IntervalAVLTree!BasicInterval;

    auto a = BasicInterval(0, 10);
    auto b = BasicInterval(10, 20);
    auto c = BasicInterval(25, 35);

    auto anode = new IntervalTreeNode!(BasicInterval)(a);
    auto bnode = new IntervalTreeNode!(BasicInterval)(b);
    auto cnode = new IntervalTreeNode!(BasicInterval)(c);

    uint cnt;
    tree.insert(anode, cnt);
    tree.insert(bnode, cnt);
    tree.insert(cnode, cnt);
    
    auto found = tree.find(bnode, cnt);
    assert(found == bnode);

    // TODO, actually not sure that these are returned strictly ordered if there are many
    auto o = tree.findOverlapsWith(BasicInterval(15, 30));
    assert(o.length == 2);
    assert(o[0] == bnode);
    assert(o[1] == cnode);

    writeln("passed");
}