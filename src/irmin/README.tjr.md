# Process of adding documentation in this directory, understanding source code

Do I want to understand this dir first? Or irmin-pack? Probably this dir.

So, the obvious place to start is the main irmin.mli file

Sequence of files to annotate (based on irmin.mli): 

* irmin.mli
* type.mli - ok; not actually exposed? Irmin.mli defines as module Type = Repr
* info - ok
* merge - complicated; skip on first reading FIXME come back if necessary
* diff - defines a simple updated/added/remove type
* perms - reflecting read/write perms as a phantom type [`Read | `Write]
* import - ok (used by store_properties_intf)

* conf (used by store_properties_intf) - confusing; a bit like cmdliner but for configs?;
  perhaps not used much

* store_properties_intf - various sigs to extend basic sig 'a t end; **batch** - which
  seems to convert a read only store into a read-write store, and performs some operations
  on it... but doesn't seem to want to give many guarantees beyond that); **closeable**
  (which states that close releases all resources... except it doesn't in `pack_store` and
  elsewhere); **Of_config** which exposes a [v] function from conf to [read t] (why just
  read?); **clearable** ("clear the store" - except that this operation is often not
  implemented properly, or requires that it is called only when a store is opened etc);

* read_only - simple store with mem, find, close; Maker adds ability to create from a config

* append_only - as read_only, but with add (k*v, returning unit), clear and batch; simple

* indexable - as read_only, with hash, add (value -> key) (was unit in append_only);
  requires each value is hashable to get the key; index function: hash -> key option, ;
  doc for index is very unclear about what guarantees it provides; "best-effort"; seems to
  imply that there is an index, to which a subset of values are added and indexed by hash

* `content_addressable_intf` - S as `read_only.S`, add (with assumed conversion of value
  to key), `unsafe_add` (allows to specify the key explicitly...with no guarantees if this
  is somehow wrong); clearable, closeable, batch all included; Maker from Hash,Value;
  Maker includes `Of_config`; Sigs reveals a Make functor, which takes an
  `Append_only_maker`!; there is also a `Check_closed` module, which takes a Maker and
  returns a Maker; this effectively wraps a F(K)(V) to give [ type 'a t = { closed : bool
  ref; t : 'a S.t } ] and various functions are lifted from F with an explicit check that
  the thing has not been closed; weird; why not just take the result sig from the Maker,
  and wrap this? no idea; also, could use a mutable record rather than a bool ref field
 
* `atomic_write_intf` - some k,v intf based on `Read_only.S`, but without the param'ed
  type; set, `test_and_set`; remove; list; various "watch" functions which uses a "diff"
  type; clearable; closeable; Maker with `Of_config`; Sigs include `Check_closed`
  
* path - a list of strings basically; t is the path type; step is the component ("short
  name"); Sigs includes a string_list impl, which is probably the only impl actually used;
  the impl of this has `of_string` ignore empty components, which seems
  not-filesystem-like; sep is hardcoded as forward-slash
  
* hash - two main sigs, S and Typed; S hash the hash function: [val hash : ((string ->
  unit) -> unit) -> t] which is a strange sig; basically you give hash not a list of
  strings, but a function of type (string->unit)->unit, which is presumably a "sequence of
  strings"; the type [type 'a iter = ('a -> unit) -> unit] is from digestif where it is
  described as a "general iterator" which applies the function to a collection of
  elements; so the idea is that the sequence is encoded in the funciton which takes the
  [string ->unit] that you want to apply to each string, and then executes that against
  all the strings; madness really; then the hash function will provide the [string ->
  unit] part, and the iterator will call that for every string it knows about; this maybe
  makes sense if we don't have sequences, and we want to hash some very large number of
  strings that perhaps are generated; hashes are fixed size; the [Typed] sig has values
  (rather than strings) and a more sensible hash function type.
  
  The final sigs includes various hash impls; for Make_BLAKE2B etc these allow to param by
  `digest_size`

* metadata_intf: a "defaultable" type which is a repr sig for a type with a default value;
  merge for performing a 3way merge on metadata; there is a dummy "None" impl for metadata
  
* contents - 
* branch
* node
* commit
* backend
* key
* Store
 * Store.kv
 * Json_tree?
 * Schema
 * Maker, Store.Maker
 * KV_maker

* Generic_key
* and maybe skip the stuff in irmin.mli from "Synchonization" onwards
* lock - seems to be an Lwt_mutex thing; there is maybe confusion about when an Lwt thread
  can be interrupted because there is a global lock that is locked before using a
  particular named lock; actually this code looks very strange; unlock seems to think the
  key might not be present (but it always is)




## .mli files, all files, files by size

.mli files:

```
append_only.mli
atomic_write.mli
branch.mli
commit.mli
conf.mli
content_addressable.mli
contents.mli
diff.mli
dot.mli
hash.mli
indexable.mli
info.mli
irmin.mli
key.mli
lock.mli
logging.mli
lru.mli
merge.mli
metadata.mli
node.mli
object_graph.mli
path.mli
read_only.mli
remote.mli
slice.mli
store.mli
store_properties.mli
sync.mli
tree.mli
type.mli
watch.mli
```

.mli by size

```
-rw-rw-r-- 1 tom tom  18k 2022-01-27 11:35 irmin.mli
  -rw-rw-r-- 1 tom tom 7.8k 2022-01-19 13:16 merge.mli
  -rw-rw-r-- 1 tom tom 5.4k 2022-01-19 13:16 key.mli
  -rw-rw-r-- 1 tom tom 5.0k 2022-01-19 13:16 conf.mli
  -rw-rw-r-- 1 tom tom 1.6k 2022-01-19 13:16 dot.mli
  -rw-rw-r-- 1 tom tom 1.4k 2022-01-19 13:16 lock.mli
  -rw-rw-r-- 1 tom tom 1.3k 2022-01-19 13:16 node.mli
  -rw-rw-r-- 1 tom tom 1.3k 2022-01-19 13:16 commit.mli
  -rw-rw-r-- 1 tom tom 1.1k 2022-01-19 13:16 lru.mli
  -rw-rw-r-- 1 tom tom  953 2022-01-19 13:16 diff.mli
  -rw-rw-r-- 1 tom tom  936 2022-01-19 13:16 store.mli
  -rw-rw-r-- 1 tom tom  936 2022-01-19 13:16 watch.mli
  -rw-rw-r-- 1 tom tom  915 2022-01-19 13:16 type.mli
  -rw-rw-r-- 1 tom tom  912 2022-01-19 13:16 tree.mli
  -rw-rw-r-- 1 tom tom  877 2022-01-19 13:16 branch.mli
  -rw-rw-r-- 1 tom tom  875 2022-01-19 13:16 sync.mli
  -rw-rw-r-- 1 tom tom  872 2022-01-19 13:16 path.mli
  -rw-rw-r-- 1 tom tom  869 2022-01-19 13:16 remote.mli
  -rw-rw-r-- 1 tom tom  868 2022-01-19 13:16 object_graph.mli
  -rw-rw-r-- 1 tom tom  864 2022-01-19 13:16 contents.mli
  -rw-rw-r-- 1 tom tom  859 2022-01-19 13:16 content_addressable.mli
  -rw-rw-r-- 1 tom tom  856 2022-01-19 13:16 store_properties.mli
  -rw-rw-r-- 1 tom tom  852 2022-01-19 13:16 atomic_write.mli
  -rw-rw-r-- 1 tom tom  851 2022-01-19 13:16 append_only.mli
  -rw-rw-r-- 1 tom tom  849 2022-01-19 13:16 read_only.mli
  -rw-rw-r-- 1 tom tom  848 2022-01-19 13:16 metadata.mli
  -rw-rw-r-- 1 tom tom  845 2022-01-19 13:16 slice.mli
  -rw-rw-r-- 1 tom tom  844 2022-01-19 13:16 hash.mli
  -rw-rw-r-- 1 tom tom  844 2022-01-19 13:16 info.mli
  -rw-rw-r-- 1 tom tom  837 2022-01-19 13:16 indexable.mli
  -rw-rw-r-- 1 tom tom  830 2022-01-19 13:16 logging.mli
```

All files:

```
append_only_intf.ml
append_only.ml
append_only.mli
atomic_write_intf.ml
atomic_write.ml
atomic_write.mli
backend.ml
branch_intf.ml
branch.ml
branch.mli
commit_intf.ml
commit.ml
commit.mli
conf.ml
conf.mli
content_addressable_intf.ml
content_addressable.ml
content_addressable.mli
contents_intf.ml
contents.ml
contents.mli
diff.ml
diff.mli
dot.ml
dot.mli
dune
export_for_backends.ml
hash_intf.ml
hash.ml
hash.mli
import.ml
indexable_intf.ml
indexable.ml
indexable.mli
info_intf.ml
info.ml
info.mli
irmin.ml
irmin.mli
key_intf.ml
key.ml
key.mli
lock.ml
lock.mli
logging_intf.ml
logging.ml
logging.mli
lru.ml
lru.mli
mem
merge.ml
merge.mli
metadata_intf.ml
metadata.ml
metadata.mli
node_intf.ml
node.ml
node.mli
object_graph_intf.ml
object_graph.ml
object_graph.mli
path_intf.ml
path.ml
path.mli
perms.ml
README.tjr.md
read_only_intf.ml
read_only.ml
read_only.mli
remote_intf.ml
remote.ml
remote.mli
schema.ml
slice_intf.ml
slice.ml
slice.mli
store_intf.ml
store.ml
store.mli
store_properties_intf.ml
store_properties.ml
store_properties.mli
sync_intf.ml
sync.ml
sync.mli
tree_intf.ml
tree.ml
tree.mli
type.ml
type.mli
version.ml
watch_intf.ml
watch.ml
watch.mli
```

All by size:

```
  -rw-rw-r-- 1 tom tom  78k 2022-01-31 10:59 tree.ml
  -rw-rw-r-- 1 tom tom  43k 2022-01-19 13:16 store.ml
  -rw-rw-r-- 1 tom tom  38k 2022-01-28 16:52 store_intf.ml
  -rw-rw-r-- 1 tom tom  22k 2022-01-28 17:09 node.ml
  -rw-rw-r-- 1 tom tom  21k 2022-01-19 13:16 commit.ml
  -rw-rw-r-- 1 tom tom  18k 2022-01-27 11:35 irmin.mli
  -rw-rw-r-- 1 tom tom  16k 2022-02-01 14:40 node_intf.ml
  -rw-rw-r-- 1 tom tom  16k 2022-01-31 11:18 tree_intf.ml
  -rw-rw-r-- 1 tom tom  13k 2022-01-19 13:16 merge.ml
  -rw-rw-r-- 1 tom tom 9.6k 2022-01-19 13:16 object_graph.ml
  -rw-rw-r-- 1 tom tom 9.5k 2022-01-19 13:16 watch.ml
  -rw-rw-r-- 1 tom tom 9.0k 2022-01-19 13:16 commit_intf.ml
  -rw-rw-r-- 1 tom tom 8.4k 2022-01-19 13:16 sync.ml
  -rw-rw-r-- 1 tom tom 7.8k 2022-01-19 13:16 merge.mli
  -rw-rw-r-- 1 tom tom 7.3k 2022-01-19 13:16 contents.ml
  -rw-rw-r-- 1 tom tom 7.1k 2022-01-19 13:16 dot.ml
  -rw-rw-r-- 1 tom tom 6.7k 2022-01-19 13:16 irmin.ml
  -rw-rw-r-- 1 tom tom 5.4k 2022-01-19 13:16 key.mli
  -rw-rw-r-- 1 tom tom 5.0k 2022-01-19 13:16 conf.mli
  -rw-rw-r-- 1 tom tom 4.8k 2022-01-19 13:16 indexable_intf.ml
  -rw-rw-r-- 1 tom tom 4.6k 2022-01-27 10:27 object_graph_intf.ml
  -rw-rw-r-- 1 tom tom 4.2k 2022-01-19 13:16 conf.ml

...
```
