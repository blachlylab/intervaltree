module intervaltree.avlx;

/// https://rosettacode.org/wiki/AVL_tree#D
/+
private struct IntervalTreeNode(IntervalType)
{
    IntervalType interval;

    // sort key
    alias key = interval.start;
    int balance;// balance factor
    int height; // aka size; # elements in subtree

    IntervalTreeNode *parent;
    IntervalTreeNode *left;
    IntervalTreeNode *right;

    invariant
    {
        // Ensure children are distinct
        if (this.left !is null && this.right !is null)
        {
            assert(this.left != this.right, "Left and righ child appear identical");
        }
    }
}

///
class IntervalAVLtree(IntervalType)
{
    alias Node = IntervalTreeNode!IntervalType;

    private Node* root;

    /**
    * Find a node in the tree
    *
    * @param x       node value to find (in)
    * @param cnt     number of nodes smaller than or equal to _x_; can be NULL (out)
    *
    * @return node equal to _x_ if present, or NULL if absent
    */
    Node* find(const(Node)* x, out uint cnt)
    {
        const Node* p = this.root;
        //uint cnt = 0;
        while (p !is null) {
            const int cmp = (x < p);
            if (cmp >= 0) cnt += (p.left ? p.left.height : 0) + 1;
            if (cmp < 0) p = p.left;
            else if (cmp > 0) p = p.right;
            else break;
        }
        //if (cnt_ !is null) *cnt_ = cnt;
        return p;
    }

    /// /* one rotation: (a,(b,c)q)p => ((a,b)p,c)q */
    /// /* dir=0 to left; dir=1 to right */
    private Node* rotate1(Node* p, const int dir)
    {
        const int opp = 1 - dir; /* opposite direction */
        Node *q = p.__head.p[opp];
        uint size_p = p.__head.size;
        p.__head.size -= q.__head.size - kavl_size_child(__head, q, dir);
        q.__head.size = size_p;
        p.__head.p[opp] = q.__head.p[dir];
        q.__head.p[dir] = p;
        return q;
    }

    ///
    pure nothrow @nogc @safe
    final bool insert(const Node key);

    ///
    pure nothrow @nogc @safe
    final bool remove(Node key);

    pure nothrow @nogc @safe
    private void rebalance(Node *n);


}
+/