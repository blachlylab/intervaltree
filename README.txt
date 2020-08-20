intervaltree
============

intervaltree provides 3 implementations of an interval tree structure:

1. Augmented AVL tree
2. Augmented Splay tree
3. Implicit Interval Tree

A classic Red-Black tree is not included but would be welcomed.

In addition to the package module itself, which includes a "BasicInterval"
struct and an "overlaps" function, the package includes 3 sub-modules,
one for each of the tree types listed above:

intervaltree.avltree
intervaltree.splaytree
intervaltree.iitree

Simply `include intervaltree.<treetype>` in your code.

Overview
--------
Each tree is implemented as a container type. So, in addition to [start,end)
interval coordinates, it may contain arbitrary other data.

API (unstable until 1.0.0)
--------------------------
Encapsulating Struct, templated on "IntervalType", containing ValueType IntervalType or a pointer to it (in the case of IITree)

Operations implemented in various combinations across the 3 tree types:
insert
remove
find
findOverlapsWith
findMin

Planned: ForwardRange interface

Debugging
---------
Debug messages:
    Debug messages are only printed when debug symbol `intervaltree_debug`
    is defined in order to better preserve debug messages from your own
    program's `debug { }` blocks.

Instrumentation:
    * Defining version `instrument` creates a variable
    `__gshared int[] _{treename}_visited` where `{treename}` in (avltree, splaytree)
    and holds statistics on the number of nodes visited to find results.
    * For cgranges (iitree), you must additionally #define INSTRUMENT and recompile
    `cgranges.c`

Brief discussion of interval trees and relative tradeoffs
---------------------------------------------------------
https://en.wikipedia.org/wiki/Interval_tree

https://en.wikipedia.org/wiki/Red%E2%80%93black_tree
https://en.wikipedia.org/wiki/AVL_tree
https://en.wikipedia.org/wiki/Splay_tree
https://github.com/lh3/cgranges

Interval trees are often implemented as augmented binary search trees.
Here, we explore several different types of binary search trees.

Red-Black trees are relatively well-balanced, but not perfectly so.
Insertion is fastest; query is slightly slower than AVL tree due to
imperfect balance, but it is a good compromise and widely used.

AVL trees are more well-balanced than Red-Black trees.
This makes insertion slightly slower, but provides the fastest
amortized lookups.

Splay trees "splay" the most recently accessed node to the top/root
of the tree, so they may become extremely unbalanced.
However, this imbalance provides an implicit caching effect when
the next insertion, deletion, or lookup is very close in coordinate space
to the most recently accessed node. In sequential queries, one may need
only to descend a single node from the root. This means for sequentially
ordered operations, it can beat the perfectly balanced AVL tree. Random access,
on the other hand, can be extremely poor.

Implicit Interval Trees (IIT) store the entire tree in a compact linear array
sorted by start position. They were created by Heng Li and implemented
as the "cgranges" C library. This library is intended for genome applications,
and includes a "contig" parameter. The IIT structure excels at both sequential
and random access, with the disadvantage that it must be reindexed (resorted)
after any/all inserts or deletes, so it works best with static trees.

Credits
-------
AVL tree based on attractivechaos' klib https://github.com/attractivechaos/klib
Splay tree is my own implementation
IITree is a D wrapper around Heng Li's cgranges C library, which is included as source
https://github.com/lh3/cgranges