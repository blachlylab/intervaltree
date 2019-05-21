/// Based on https://github.com/attractivechaos/klib commit 8ffbbdb2bf80ee84ba089dbabd5fa2420ee9aefe dated 2019-03-24
module intervaltree.khash;

import std.traits;	// isIntegral

/*
#include <memory>
#include <functional>
#include <cstdlib> // for malloc() etc
#include <cstring> // for memset()
*/
import core.stdc.stdlib;	// for malloc() etc

import core.std.stdint;	// for uint32_t

//FIXME: doesn't work for 64-bit integers
//#define kroundup32(x) (--(x), (x)|=(x)>>1, (x)|=(x)>>2, (x)|=(x)>>4, (x)|=(x)>>8, (x)|=(x)>>16, ++(x))
import intervaltree.roundup;

pragma(inline, true) {
///#define __ac_isempty(flag, i) ((flag[i>>4]>>((i&0xfU)<<1))&2)
auto __ac_isempty(T)(uint32_t* flag, T i) if (isIntegral!T)
{ return ((flag[i>>4]>>((i&0xfU)<<1))&2); }
///#define __ac_isdel(flag, i) ((flag[i>>4]>>((i&0xfU)<<1))&1)
auto __ac_isdel(T)(uint32_t* flag, T i) if (isIntegral!T)
{ return ((flag[i>>4]>>((i&0xfU)<<1))&1); }
///#define __ac_isempty(flag, i) ((flag[i>>4]>>((i&0xfU)<<1))&2)
auto __ac_isempty(T)(uint32_t* flag, T i) if (isIntegral!T)
{ return ((flag[i>>4]>>((i&0xfU)<<1))&2); }
///#define __ac_isdel(flag, i) ((flag[i>>4]>>((i&0xfU)<<1))&1)
auto __ac_isdel(T)(uint32_t* flag, T i) if (isIntegral!T)
{ return ((flag[i>>4]>>((i&0xfU)<<1))&1); }
///#define __ac_iseither(flag, i) ((flag[i>>4]>>((i&0xfU)<<1))&3)
auto __ac_iseither(T)(uint32_t* flag, T i) if (isIntegral!T)
{ return ((flag[i>>4]>>((i&0xfU)<<1))&3); }
///#define __ac_set_isdel_false(flag, i) (flag[i>>4]&=~(1ul<<((i&0xfU)<<1)))
void __ac_set_isdel_false(T)(uint32_t* flag, T i) if (isIntegral!T)
{ (flag[i>>4]&=~(1uL<<((i&0xfU)<<1))); }
///#define __ac_set_isempty_false(flag, i) (flag[i>>4]&=~(2ul<<((i&0xfU)<<1)))
void __ac_set_isempty_false(T)(uint32_t* flag, T i) if (isIntegral!T)
{ (flag[i>>4]&=~(2uL<<((i&0xfU)<<1))); }
///#define __ac_set_isboth_false(flag, i) (flag[i>>4]&=~(3ul<<((i&0xfU)<<1)))
void __ac_set_isboth_false(T)(uint32_t* flag, T i) if (isIntegral!T)
{ (flag[i>>4]&=~(3uL<<((i&0xfU)<<1))); }
///#define __ac_set_isdel_true(flag, i) (flag[i>>4]|=1ul<<((i&0xfU)<<1))
void __ac_set_isdel_true(T)(uint32_t* flag, T i) if (isIntegral!T)
{ (flag[i>>4]|=1uL<<((i&0xfU)<<1)); }
} // pragma inline

/// If < 16 return 1, othewise return m / 16
/// #define __ac_fsize(m) ((m) < 16? 1 : (m)>>4)
string __ac_fsize(string m)	{ return "(" ~ m ~ "< 16? 1 : " ~ m ~ ">>4)"; }

///template<class T, class Hash, class Eq = std::equal_to<T>, typename khint_t = uint32_t>
class KHash(T, hashfn, khint_t = uint32_t)
{
private:
	khint_t n_buckets, count, n_occupied, upper_bound;
	uint32_t *flags;
	T *keys;
public:
	~this()
	{
		free(flags);
		free(keys);
	}
	/// capacity (number of buckets)
	khint_t capacity(void) const { return n_buckets; }
	/// actual size (num objects)
	khint_t size(void) const { return count; }
	/// zero
	khint_t begin(void) const { return 0; }
	/// same as capacity / n.buckets
	khint_t end(void) const { return n_buckets; }

	/// does object exist at this integer offset?
	void exist(khint_t x) const { return !__ac_iseither(flags, x); }

	/// return bucket contents at integer offset by reference
	ref T at(khint_t x) { return keys[x]; } // validate

	/// get integer offset of value for key
	khint_t get(ref const T key) const {
		if (n_buckets) {
			khint_t k, i, last, mask, step = 0;
			mask = n_buckets - 1;
			k = Hash()(key); i = k & mask;
			last = i;
			while (!__ac_isempty(flags, i) && (__ac_isdel(flags, i) || !Eq()(keys[i], key))) {
				i = (i + (++step)) & mask;
				if (i == last) return n_buckets;
			}
			return __ac_iseither(flags, i)? n_buckets : i;
		} else return 0;
	}

	/// resize the hash table
	int resize(khint_t new_n_buckets) {
		uint32_t *new_flags = null;
		khint_t j = 1;
		{
			new_n_buckets = kroundup32(new_n_buckets);	// JSB: prior macro updates in place, my asm returns rounded value
			if (new_n_buckets < 4) new_n_buckets = 4;
			if (count >= (new_n_buckets>>1) + (new_n_buckets>>2)) j = 0;	/* requested count is too small */
			else { /* hash table count to be changed (shrink or expand); rehash */
				new_flags = cast(uint32_t*) malloc( mixin(__ac_fsize(new_n_buckets)) * sizeof(uint32_t));
				if (!new_flags) return -1;
				memset(new_flags, 0xaa, mixin(__ac_fsize(new_n_buckets)) * sizeof(uint32_t));
				if (n_buckets < new_n_buckets) {	/* expand */
					T *new_keys = (T*)std::realloc((void *)keys, new_n_buckets * sizeof(T));
					if (!new_keys) { std::free(new_flags); return -1; }
					keys = new_keys;
				} /* otherwise shrink */
			}
		}
		if (j) { /* rehashing is needed */
			for (j = 0; j != n_buckets; ++j) {
				if (__ac_iseither(flags, j) == 0) {
					T key = keys[j];
					khint_t new_mask;
					new_mask = new_n_buckets - 1;
					__ac_set_isdel_true(flags, j);
					while (1) { /* kick-out process; sort of like in Cuckoo hashing */
						khint_t k, i, step = 0;
						k = Hash()(key);
						i = k & new_mask;
						while (!__ac_isempty(new_flags, i)) i = (i + (++step)) & new_mask;
						__ac_set_isempty_false(new_flags, i);
						if (i < n_buckets && __ac_iseither(flags, i) == 0) { /* kick out the existing element */
							{ T tmp = keys[i]; keys[i] = key; key = tmp; }
							__ac_set_isdel_true(flags, i); /* mark it as deleted in the old hash table */
						} else { /* write the element and jump out of the loop */
							keys[i] = key;
							break;
						}
					}
				}
			}
			if (n_buckets > new_n_buckets) /* shrink the hash table */
				keys = (T*)std::realloc((void *)keys, new_n_buckets * sizeof(T));
			free(flags); /* free the working space */
			flags = new_flags;
			n_buckets = new_n_buckets;
			n_occupied = count;
			upper_bound = (n_buckets>>1) + (n_buckets>>2);
		}
		return 0;
	}

	/// put a new object in the hash table
	khint_t put(const T &key, int *ret) {
		khint_t x;
		if (n_occupied >= upper_bound) { /* update the hash table */
			if (n_buckets > (count<<1)) {
				if (resize(n_buckets - 1) < 0) { /* clear "deleted" elements */
					*ret = -1; return n_buckets;
				}
			} else if (resize(n_buckets + 1) < 0) { /* expand the hash table */
				*ret = -1; return n_buckets;
			}
		} /* TODO: to implement automatically shrinking; resize() already support shrinking */
		{
			khint_t k, i, site, last, mask = n_buckets - 1, step = 0;
			x = site = n_buckets; k = Hash()(key); i = k & mask;
			if (__ac_isempty(flags, i)) x = i; /* for speed up */
			else {
				last = i;
				while (!__ac_isempty(flags, i) && (__ac_isdel(flags, i) || !Eq()(keys[i], key))) {
					if (__ac_isdel(flags, i)) site = i;
					i = (i + (++step)) & mask;
					if (i == last) { x = site; break; }
				}
				if (x == n_buckets) {
					if (__ac_isempty(flags, i) && site != n_buckets) x = site;
					else x = i;
				}
			}
		}
		if (__ac_isempty(flags, x)) { /* not present at all */
			keys[x] = key;
			__ac_set_isboth_false(flags, x);
			++count; ++n_occupied;
			*ret = 1;
		} else if (__ac_isdel(flags, x)) { /* deleted */
			keys[x] = key;
			__ac_set_isboth_false(flags, x);
			++count;
			*ret = 2;
		} else *ret = 0; /* Don't touch keys[x] if present and not deleted */
		return x;
	}

	/// remove the object at integer offset
	void del(khint_t x) {
		if (x != n_buckets && !__ac_iseither(flags, x)) {
			__ac_set_isdel_true(flags, x);
			--count;
		}
	}//ok
}
