module intervaltree.kavl;

/* The MIT License
   Copyright (c) 2018 by Attractive Chaos <attractor@live.co.uk>
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

/* An example:
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "kavl.h"
struct my_node {
  char key;
  KAVL_HEAD(struct my_node) head;
};
#define my_cmp(p, q) (((q)->key < (p)->key) - ((p)->key < (q)->key))
KAVL_INIT(my, struct my_node, head, my_cmp)
int main(void) {
  const char *str = "MNOLKQOPHIA"; // from wiki, except a duplicate
  struct my_node *root = 0;
  int i, l = strlen(str);
  for (i = 0; i < l; ++i) {        // insert in the input order
    struct my_node *q, *p = malloc(sizeof(*p));
    p->key = str[i];
    q = kavl_insert(my, &root, p, 0);
    if (p != q) free(p);           // if already present, free
  }
  kavl_itr_t(my) itr;
  kavl_itr_first(my, root, &itr);  // place at first
  do {                             // traverse
    const struct my_node *p = kavl_at(&itr);
    putchar(p->key);
    free((void*)p);                // free node
  } while (kavl_itr_next(my, &itr));
  putchar('\n');
  return 0;
}
*/

alias cmpfn = (x,y) => ((y < x) - (x < y));

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

///
struct Node
{
    int key;  /// sortable

    /// below prev in ->head
    Node*[2] p;
    byte balance;   /// balance factor (signed, 8-bit)
    uint size;      /// #elements in subtree
}

/**
 * Find a node in the tree
 *
 * @param root    root of the tree
 * @param x       node value to find (in)
 * @param cnt     number of nodes smaller than or equal to _x_; can be NULL (out)
 *
 * @return node equal to _x_ if present, or NULL if absent
 */
@trusted    // cannot be @safe: casts away const
@nogc nothrow
Node *kavl_find(const(Node)* root, const(Node) *x, out uint cnt) {

    const(Node)* p = root;

    while (p !is null) {
        const int cmp = cmpfn(x, p);
        if (cmp >= 0) cnt += kavl_size_child(p, DIR.LEFT) + 1; // left tree plus self

        if (cmp < 0) p = p.p[DIR.LEFT];         // descend leftward
        else if (cmp > 0) p = p.p[DIR.RIGHT];   // descend rightward
        else break;
    }

    return cast(Node*)p;    // not allowed in @safe, but is const only within this fn
}


/// /* one rotation: (a,(b,c)q)p => ((a,b)p,c)q */
pragma(inline, true)
@safe @nogc nothrow
private
Node *kavl_rotate1(Node *p, int dir) { /* dir=0 to left; dir=1 to right */
    const int opp = 1 - dir; /* opposite direction */
    Node *q = p.p[opp];
    const uint size_p = p.size;
    p.size -= q.size - kavl_size_child(q, dir);
    q.size = size_p;
    p.p[opp] = q.p[dir];
    q.p[dir] = p;
    return q;
}

/** two consecutive rotations: (a,((b,c)r,d)q)p => ((a,b)p,(c,d)q)r */
pragma(inline, true)
@safe @nogc nothrow
private
Node *kavl_rotate2(Node *p, int dir) {
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
    return r;
}

/**
 * Insert a node to the tree
 *
 * @param proot   pointer to the root of the tree (in/out: root may change)
 * @param x       node to insert (in)
 * @param cnt     number of nodes smaller than or equal to _x_; can be NULL (out)
 *
 * @return _x_ if not present in the tree, or the node equal to x.
 */
@safe @nogc nothrow
Node *kavl_insert(Node **root_, Node *x, out uint cnt)
{
    
    ubyte[KAVL_MAX_DEPTH] stack;
    Node*[KAVL_MAX_DEPTH] path;

    Node* bp;
    Node* bq;
    Node* p;
    Node* q;
    Node* r = null; /* _r_ is potentially the new root */

    int i, which = 0, top, b1, path_len;

    bp = *root_, bq = null;
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
    }

    x.balance = 0, x.size = 1, x.p[DIR.LEFT] = x.p[DIR.RIGHT] = null;
    if (q is null) *root_ = x;
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
        r = kavl_rotate1(bp, which);
        q.balance = bp.balance = 0;
    } else r = kavl_rotate2(bp, which);
    if (bq is null) *root_ = r;
    else bq.p[bp != bq.p[0]] = r;   // wow
    return x;
}


/**
 * Delete a node from the tree
 *
 * @param proot   pointer to the root of the tree (in/out: root may change)
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
Node *kavl_erase(Node **root_, const(Node) *x, out uint cnt) {
    Node* p;
    Node*[KAVL_MAX_DEPTH] path;
    Node fake;
    ubyte[KAVL_MAX_DEPTH] dir;
    int i, d = 0, cmp;
    fake.p[DIR.LEFT] = *root_, fake.p[DIR.RIGHT] = null;

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
                path[d-1].p[dir[d-1]] = kavl_rotate2(q, which);
            } else {
                path[d-1].p[dir[d-1]] = kavl_rotate1(q, which);
                if (r.balance == 0) {
                    r.balance = cast(byte) -b1;
                    q.balance = cast(byte) b1;
                    break;
                } else r.balance = q.balance = 0;
            }
        }
    }
    *root_ = fake.p[0];
    return p;
}

/// free the entire tree
pragma(inline, true)
@safe @nogc nothrow
void kavl_free(Node * __root)
{
    import core.stdc.stdlib : free;
    Node *_p, _q;
    for (_p = __root; _p; _p = _q) {
        if (_p.p[DIR.LEFT] is null) {
            _q = _p.p[DIR.RIGHT];
            ( () @trusted => free(_p))();   // @trusted escape, see https://dlang.org/blog/2016/09/28/how-to-write-trusted-code-in-d/
        } else {
            _q = _p.p[DIR.LEFT];
            _p.p[DIR.LEFT] = _q.p[DIR.RIGHT];
            _q.p[DIR.RIGHT] = _p;
        }
    }
}

///
struct kavl_itr // @suppress(dscanner.style.phobos_naming_convention)
{
    //const Node *stack[KAVL_MAX_DEPTH], **top, *right; /* _right_ points to the right child of *top */
    const(Node)*[KAVL_MAX_DEPTH] stack; /// ?
    const(Node)** top;     /// _right_ points to the right child of *top
    const(Node)*  right;   /// _right_ points to the right child of *top

}

/**
 * Place the iterator at the smallest object
 *
 * @param root    root of the tree
 * @param itr     iterator
 */
void kavl_itr_first(const(Node)* root, kavl_itr* itr) {
    const(Node)* p;
    for (itr.top = &(itr.stack[0]) - 1, p = root; p; p = p.p[DIR.LEFT])
        *++itr.top = p;
    itr.right = (*itr.top).p[DIR.RIGHT];
}

/**
 * Place the iterator at the object equal to or greater than the query
 *
 * @param root    root of the tree
 * @param x       query (in)
 * @param itr     iterator (out)
 *
 * @return 1 if find; 0 otherwise. kavl_at(itr) is NULL if and only if query is
 *         larger than all objects in the tree
 */
int kavl_itr_find(const(Node)* root, const(Node)* x, kavl_itr* itr) {
    const(Node)* p = root;
    itr.top = &(itr.stack[0]) - 1;
    while (p !is null) {
        const int cmp = cmpfn(x, p);
        if (cmp < 0) *++itr.top = p, p = p.p[DIR.LEFT];
        else if (cmp > 0) p = p.p[DIR.RIGHT];
        else break; // found p == x
    }
    if (p !is null) {
        *++itr.top = p;
        itr.right = p.p[DIR.RIGHT];
        return 1;
    } else if (itr.top >= &(itr.stack[0]) ) {
        itr.right = (*itr.top).p[DIR.RIGHT];
        return 0;
    } else return 0;
}

/**
 * Move to the next object in order
 *
 * @param itr     iterator (modified)
 *
 * @return 1 if there is a next object; 0 otherwise
 */
int kavl_itr_next(kavl_itr *itr) {
    for (;;) {
        const(Node)* p;
        for (p = itr.right, --itr.top; p; p = p.p[DIR.LEFT])
            *++itr.top = p;
        if (itr.top < &(itr.stack[0]) ) return 0;
        itr.right = (*itr.top).p[DIR.RIGHT];
        return 1;
    }
}

/**
 * Return the pointer at the iterator
 *
 * @param itr     iterator
 *
 * @return pointer if present; NULL otherwise
 */
pragma(inline, true)
@safe @nogc nothrow
const(Node)* kavl_at(const(kavl_itr)* itr)
{
    return (itr.top < &(itr.stack[0])) ? null : *itr.top;
}