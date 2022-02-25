# Process of adding documentation in this directory, understanding source code

Do I want to understand this dir first? Or irmin-pack? Probably this dir.

So, the obvious place to start is the main irmin.mli file

Sequence of files to annotate (based on irmin.mli): 

* irmin.mli
* type.mli
* info
* merge
* diff
* perms
* read_only
* append_only
* indexable
* content_addressable
* atomic_write
* path
* hash
* metadata
* contents
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
