/** Interval Tree backed by augmented Splay Tree

This is not threadsafe! Every query modifies the tree.

Timing data:
    findOverlapsWith: UnrolledList < D array < SList (emsi)

Author: James S. Blachly, MD <james.blachly@gmail.com>
Copyright: Copyright (c) 2019 James Blachly
License for personal, academic, and noncomercial use: Apache 2.0
License for commercial use: Negotiable; contact author
*/
module intervaltree.splaytree;

import intervaltree : BasicInterval, overlaps;

import containers.unrolledlist;

/// Probably should not be used directly by consumer
struct IntervalTreeNode(IntervalType)
if (__traits(hasMember, IntervalType, "start") &&
    __traits(hasMember, IntervalType, "end"))
{
    //alias key = interval.start;   // no longer works with the embedded
                                    // structs and chain of alias this
    /// sort key
    pragma(inline,true)
    @property @safe @nogc nothrow const
    auto key() { return this.interval.start; }

    IntervalType interval;  /// must at a minimum include members start, end
    typeof(IntervalType.end) max;    /// maximum in this $(I subtree)

    IntervalTreeNode *parent;   /// parent node
    IntervalTreeNode *left;     /// left child
    IntervalTreeNode *right;    /// right child

    /// Does the interval in this node overlap the interval in the other node?
    pragma(inline, true) @nogc nothrow bool overlaps(const ref IntervalTreeNode other)
        { return this.interval.overlaps(other.interval); }

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

    /// Returns true if this node is the left child of its' parent
    @nogc nothrow
    bool isLeftChild()
    {
        if (this.parent !is null)   // may be null if is root
        {
            return (this.parent.left is &this);
        }
        else return false;
    }

    invariant
    {
        // the Interval type itself should include checks, but in case it does not:
        assert(this.interval.start <= this.interval.end, "Interval start must <= end");

        assert(this.max >= this.interval.end, "max must be at least as high as our own end");

        // Make sure this is a child of its parent
        if (this.parent !is null)
        {
            assert(this.parent.left is &this || this.parent.right is &this,
                "Broken parent/child relationship");
        }

        // Ensure children are distinct
        if (this.left !is null && this.right !is null)
        {
            assert(this.left != this.right, "Left and righ child appear identical");
        }

    }
}

///
struct IntervalSplayTree(IntervalType)
{
    alias Node = IntervalTreeNode!IntervalType;

    Node *root;    /// tree root
    Node *cur;      /// current or cursor for iteration

    // NB if change to class, add 'final'
    /** zig a child of the root node */
    pragma(inline, true)
    @safe @nogc nothrow
    private void zig(Node *n) 
    in
    {
        // zig should not be called on empty tree
        assert(n !is null);
        // zig should not be called on root node
        assert( n.parent !is null );
        // zig only to be called on child of root node -- i.e. no grandparent node
        assert( n.parent.parent is null );
    }
    do
    {
        Node *p = n.parent;

        if (p.left == n)    // node is left child of parent
        {
            //Node *A = n.left;   // left child
            Node *B = n.right;  // right child
            //Node *C = p.right;  // sister node

            n.parent = null;    // rotate to top (splay() fn handles tree.root reassignment)

            // place parent (former root) as right child
            n.right  = p;
            p.parent = n;

            // assign former right child to (former) parent's left (our prev pos)
            p.left = B;
            if (B !is null) B.parent = p;
        }
        else                // node is right child of parent
        {
            // safety check during development
            assert(p.right == n);

            //Node *A = p.left;   // sister node
            Node *B = n.left;   // left child
            //Node *C = n.right;  // right child

            n.parent = null;    // rotate to top (splay() fn handles tree.root reassignment)

            // place parent (former root) as left child
            n.left = p;
            p.parent = n;

            // assign former left child to (former) parent's right (our prev pos)
            p.right = B;
            if (B !is null) B.parent = p;
        }

        // update max
        // lemmas (with respect to their positions prior to rotation):
        // 1. scenarios when both root/"parent" and Node n need to be updated may exist
        // 2. A, B, C, D subtrees never need to be updated
        // 3. other subtree of root/"parent" never needs to be updated
        // conclusion: update p which is now child of n, will percolate upward
        updateMax(p); 
    }

    // NB if change to class, add 'final'
    /** zig-zig  */
    pragma(inline, true)
    @safe @nogc nothrow
    private void zigZig(Node *n) 
    in
    {
        // zig-zig should not be called on empty tree
        assert(n !is null);
        // zig-zig should not be called on the root node
        assert(n.parent !is null);
        // zig-zig requires a grandparent node
        assert(n.parent.parent !is null);
        // relationships must be identical:
        if(n == n.parent.left) assert(n.parent == n.parent.parent.left);
        else if(n == n.parent.right) assert(n.parent == n.parent.parent.right);
        else assert(0);
    }
    do
    {
        Node *p = n.parent;
        Node *g = p.parent;

        if (p.left == n)
        {
/*
        /g\
       /   \
     /p\   /D\
    /   \
  /n\   /C\
 /   \
/A\  /B\
*/
            //Node *A = n.left;
            Node *B = n.right;
            Node *C = p.right;
            //Node *D = g.right;

            n.parent = g.parent;
            if (n.parent !is null)
            {
                assert( n.parent.left == g || n.parent.right == g);
                if (n.parent.left == g) n.parent.left = n;
                else n.parent.right = n;
            }

            n.right = p;
            p.parent = n;

            p.left = B;
            if (B !is null) B.parent = p;
            p.right = g;
            g.parent = p;

            g.left = C;
            if (C !is null) C.parent = g;

        }
        else    // node is right child of parent
        {
/*
        /g\
       /   \
     /A\   /p\
          /   \
        /B\   /n\
             /   \
            /C\  /D\
*/
            // safety check during development
            assert(p.right == n);

            //Node *A = g.left;
            Node *B = p.left;
            Node *C = n.left;
            //Node *D = n.right;

            n.parent = g.parent;
            if (n.parent !is null)
            {
                assert( n.parent.left == g || n.parent.right == g);
                if (n.parent.left == g) n.parent.left = n;
                else n.parent.right = n;
            }

            n.left = p;
            p.parent = n;

            p.left = g;
            g.parent = p;
            p.right = C;
            if (C !is null) C.parent = p;

            g.right = B;
            if (B !is null) B.parent = g;

        }

        // update max
        // lemmas:
        // 1. A, B, C, D had only a parent changed => nver need max updated
        // 2. g, p, or n may need to be changed
        // 3. g -> p -> n after both left zigzig and right zigzig
        // conclusion: can update on g and it will percolate upward
        updateMax(g);
    }

    // NB if change to class, add 'final'
    /** zig-zag */
    pragma(inline, true)
    @safe @nogc nothrow
    private void zigZag(Node *n) 
    in
    {
        // zig-zag should not be called on empty tree
        assert(n !is null);
        // zig-zag should not be called on the root node
        assert(n.parent !is null);
        // zig-zag requires a grandparent node
        assert(n.parent.parent !is null);
        // relationships must be opposite:
        if(n == n.parent.left) assert(n.parent == n.parent.parent.right);
        else if(n == n.parent.right) assert(n.parent == n.parent.parent.left);
        else assert(0);
    }
    do
    {
        Node *p = n.parent;
        Node *g = p.parent;

        if (p.right == n)
        {
            assert(p.right == n && g.left == p);
/*  node is right child of parent; parent is left child of grandparent
              /g\             /n\
             /   \           /   \
           /p\   /D\   ->  /p\   /g\
          /   \           /   \ /   \
        /A\   /n\        A    B C   D
             /   \
            /B\  /C\
*/
            //Node *A = p.left;
            Node *B = n.left;
            Node *C = n.right;
            //Node *D = g.right;

            n.parent = g.parent;
            n.left = p;
            n.right = g;
            if (n.parent !is null)
            {
                assert( n.parent.left == g || n.parent.right == g);
                if (n.parent.left == g) n.parent.left = n;
                else n.parent.right = n;
            }

            p.parent = n;
            p.right = B;
            if (B !is null) B.parent = p;

            g.parent = n;
            g.left = C;
            if (C !is null) C.parent = g;
        }
        else
        {
            assert(p.left == n && g.right == p);
/*  node is left child of parent; parent is right child of grandparent
         /g\             /n\
        /   \           /   \
      /A\  /p\    ->   /g\   /p\
          /   \       /   \ /   \
        /n\   /D\    A    B C   D
       /   \
      /B\  /C\
*/
            //Node *A = g.left;
            Node *B = n.left;
            Node *C = n.right;
            //Node *D = p.right;

            n.parent = g.parent;
            n.left = g;
            n.right = p;
            if (n.parent !is null)
            {
                assert( n.parent.left == g || n.parent.right == g);
                if (n.parent.left == g) n.parent.left = n;
                else n.parent.right = n;
            }

            p.parent = n;
            p.left = C;
            if (C !is null) C.parent = p;

            g.parent = n;
            g.right = B;
            if (B !is null) B.parent = g;
        }

        // update max
        // lemmas:
        // 1. A, B, C, D had only a parent changed => nver need max updated
        // 2. g, p, or n may need to be changed
        // 3. p and g are children of n after left zig-zag or right zig-zag
        // conclusion: updating and percolating upward on both p and g would be wasteful
        updateMax(p, 1);    // do not bubble up
        updateMax(g);       // bubble up (default)
    }

    // NB if change to class, add 'final'
    /** Bring Node N to top of tree */
    @nogc nothrow
    private void splay(Node *n) 
    {
        while (n.parent !is null)
        {
            const Node *p = n.parent;
            const Node *g = p.parent;
            if (g is null) zig(n);
            else if (g.left == p && p.left == n) zigZig(n);
            else if (g.right== p && p.right== n) zigZig(n);
            else zigZag(n);
        }
        this.root = n;
    }

    // TBD: state of default ctor inited struct
    // TODO: @disable postblit?

/+
    /// Find interval(s) overlapping query interval qi
    Node*[] intervalsOverlappingWith(IntervalType qi)
    {
        Node*[] ret;    // stack

        Node *cur = root;
        
        if (qi.overlaps(cur)) ret ~= cur;

        // If left subtree's maximum is larger than current root's start,
        // there may be an overlap
        if (cur.left !is null &&
            cur.left.max > cur.key)           /// TODO: check whether should be >=
                break;
    }
+/

    /// find interval
    /// TODO: use augmented tree's 'max' to efficiently bail out early
    @nogc nothrow
    Node *find(IntervalType interval)
    {
        Node *ret;
        Node *current = this.root;
        Node *previous;

        while (current !is null)
        {
            previous = current;
            if (interval < current.interval) current = current.left;
            else if (interval > current.interval) current = current.right;
            else if (interval == current.interval)
            {
                ret = current;
                break;
            }
            else assert(0, "An unexpected inequality occurred");
        }

        if (ret !is null) splay(ret);        // splay to the found node
        // TODO: Benchmark with/without below condition
        //else if (prev !is null) splay(prev); // splay the last node searched before no result was found

        return ret;
    }

    /** find interval(s) overlapping given interval
        
        unlike find interval by key, matching elements could be in left /and/ right subtree

        We use template type "T" here instead of the enclosing struct's IntervalType
        so that we can from externally query with any type of interval object

        TODO: benchmark return Node[]
    */
    nothrow
    Node*[] findOverlapsWith(T)(T qinterval)
    if (__traits(hasMember, T, "start") &&
        __traits(hasMember, T, "end"))
    {
        Node*[] ret;
//        ret.reserve(7);
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
                if (current.left) stack.insertBack(current.left);
                continue;
            }

            // if current node overlaps query interval, save it and search its children
            if (current.interval.overlaps(qinterval)) ret ~= current;
            if (current.left) stack.insertBack(current.left);
            if (current.right) stack.insertBack(current.right);
        }

        if (ret.length == 1) splay(ret[0]);
        // TODO else len > 1 ??? 

        return ret;
    }

    /// find interval by exact key -- NOT overlap
    Node *findxxx(IntervalType interval)
    {
        Node*[] stack;

        if (this.root !is null)
            stack ~= this.root; // push

        while (stack.length > 0)
        {
            // pop
            Node *current = stack[$];
            stack = stack[0 .. $-1];

            // Check if the interval is to the right of our largest value;
            // if yes, bail out
            if (interval >= current.max)  // TODO: check inequality; is >= correct for half-open coords?
                continue;
            
            // If the interval starts less than curent interval,
            // search left subtree
            if (interval < current.interval) {
                if (current.left !is null)
                    stack ~= current.left;
                continue;
            }

            // if the current node is a match, return result; then check left and right subtrees
            if (interval == current.interval) 
            {
                splay(current);
                return current;
            }

            // Check left and right subtrees
            if (current.left !is null) stack ~= current.left;
            if (current.right!is null) stack ~= current.right;
            /*
            // If the current node's interval overlaps, include it in results; then check left and right subtrees
            if (interval.start >= current.start && interval.start <= current.end)   // TODO: check inequality for half-open coords
                results ~= current;
            
            if (current.left !is null) stack ~= current.left;
            if (current.right!is null) stack ~= current.right;
            */
        }

        // no match was found
        return null;        
    }

    /// find minimum valued Node (interval)
    @nogc nothrow
    Node *findMin() 
    {
        return findSubtreeMin(this.root);
    }
    /// ditto
    @nogc nothrow
    private static Node* findSubtreeMin(Node *n) 
    {
        Node *current = n;
        if (current is null) return current;
        while (current.left !is null)
            current = current.left;         // descend leftward
        return current;
    }

    /** Start at Node n, update max from subtrees, and bubble upward
    
    Will stop after `bubbleUp` # nodes were processed, or until root node hit 
    
    TODO: benchmark with/without bubbleUp param (used only in zig-zag fn to possibly save cycles)
    
    Params:
        n = node to update (or from which to begin)
        bubbleUp =  How many nodes to process recursively upward
                    (default: -1 => no limit])
    */
    @nogc nothrow
    void updateMax(Node *n, int bubbleUp = -1) 
    {
        import std.algorithm.comparison : max;

        Node *current = n;

        while (current && bubbleUp--)
        {
            int localmax = current.interval.end;
            if (current.left)
                localmax = max(current.left.max, localmax);
            if (current.right)
                localmax = max(current.right.max, localmax);
            current.max = localmax;

            current = current.parent;   // ascend
        }
    }

    /// insert interval, updating "max" on the way down
    // TODO: unit test degenerate start intervals (i.e. [10, 11), [10, 13) )
    Node * insert(IntervalType i) nothrow
    {
        // if empty tree, assign a new root and return
        if (this.root is null)
        {
            this.root = new Node(i);   // heap alloc
            return this.root;
        }

        Node *current = this.root;

        // TODO: can maybe speed this up by pulling the "add here and return" code out 
        while (current !is null)
        {
            // conditionally update max irrespective of whether we add new node, or descend
            if (i.end > current.max) current.max = i.end;

            if (i < current.interval)           // Look at left subtree
            {
                if (current.left is null)       // add here and return
                {
                    Node *newNode = new Node(i);   // heap alloc
                    current.left = newNode;
                    newNode.parent = current;

                    splay(newNode);
                    return newNode;
                }
                else current = current.left;    // descend leftward
            }
            else if (i > current.interval)      // Look at right subtree
            {
                if (current.right is null)      // add here and return
                {
                    Node *newNode = new Node(i);    // heap alloc
                    current.right = newNode;
                    newNode.parent = current;

                    splay(newNode);
                    return newNode;
                }
                else current = current.right;   // descend rightward
            }
            else                                // Aleady exists
            {
                assert(i == current.interval);
                splay(current);
                return current;
            }
        }

        assert(0, "Unexpectedly, current is null");
    }

    /** remove interval

        Returns:
            * True if interval i removed
            * False if interval not found

        TODO: check that the this.cur is not being removed, if so, also advance it to next
    */
    bool remove(IntervalType i);

    /// iterator functions: reset
    @nogc nothrow
    void iteratorReset()
    {
        this.cur = null;
    }
    /// iterator functions: next
    @nogc nothrow
    Node *iteratorNext()
    {
        if (this.cur is null)   // initial condition
        {
            this.cur = findMin();
            return this.cur;
        }
        else                    // anytime after start
        {
            if (this.cur.right is null)
            {
                while (!this.cur.isLeftChild() && this.cur.parent)   // if we are a right child (really, "if not the left child" -- root node returns false), (and not the root, or an orphan)
                    this.cur = this.cur.parent; // ascend one level
                
                if (this.cur.parent && this.cur == this.root)
                {
                    this.cur = null;
                    return null;
                }

                // now that we are a left child, ascend and return
                this.cur = this.cur.parent;
                return this.cur;
            }
            else    // there is a right subtree
            {
                // descend right, then find the minimum
                this.cur = findSubtreeMin(this.cur.right);
                return this.cur;
            }
        }
    }
}
unittest
{
    import std.stdio: writeln, writefln;

    IntervalSplayTree!BasicInterval t;

    writefln("Inserted node: %s", *t.insert(BasicInterval(0, 100)));
    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);

    writefln("Inserted node: %s", *t.insert(BasicInterval(100, 200)));
    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);

    writefln("Inserted node: %s", *t.insert(BasicInterval(200, 300)));
    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);

    writefln("Inserted node: %s", *t.insert(BasicInterval(300, 400)));
    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);

    writefln("Inserted node: %s", *t.insert(BasicInterval(400, 500)));
    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);
    
    const auto n0 = t.find(BasicInterval(200, 250));
    assert(n0 is null);

    const auto n1 = t.find(BasicInterval(200, 300));
    assert(n1.interval == BasicInterval(200, 300));

    writeln("\n---\n");

    while(t.iteratorNext() !is null)
        writefln("Value in order: %s", *t.cur);
    
    writefln("\nOne more shows it's been reset: %s", *t.iteratorNext());

    writeln("---\nCheck overlaps:");
    //auto x = t.findOverlapsWithXXX(BasicInterval(0, 100));

    auto o1 = t.findOverlapsWith(BasicInterval(150, 250));
    auto o2 = t.findOverlapsWith(BasicInterval(150, 350));
    auto o3 = t.findOverlapsWith(BasicInterval(300, 400));
    writefln("o1: %s", o1);
    writefln("o2: %s", o2);
    writefln("o3: %s", o3);

}