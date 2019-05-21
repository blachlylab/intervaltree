module intervaltree.roundup;

import std.traits;

alias kroundup32 = roundup32;

version(X86_64)
{
    /// round 32 bit (u)int x to power of 2 that is equal or greater
    uint roundup32(uint x)
    {
        if (x <= 2) return x;

        asm
        {
            mov EAX, x[EBP];
            sub EAX, 1;
            bsr ECX, EAX;   // ecx = y = msb(x-1)
            mov EAX, 2;
            shl EAX, CL;    // return (2 << y)
        }
   }    // returns EAX
}
else
{
    /// round 32 bit (u)int x to power of 2 that is equal or greater
    uint roundup32(ref uint x)
    {
        pragma(inline, true)

        x -= 1;
        x |= (x >> 1);
        x |= (x >> 2);
        x |= (x >> 4);
        x |= (x >> 8);
        x |= (x >> 16);

        return ++x;
    }   
}