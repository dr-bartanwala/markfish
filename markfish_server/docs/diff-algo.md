# Diffing Algo for markfish

## I spent a day figuring out this thingy, and i think it came out pretty well

So by the grace of our parser, we will be getting a sync stream of chunks (chunkhash + chunkdata)

The initial diffing algo was inspired with Rsync as a reference, if you don't know about Rsync, I would suggest you check this out 

[Rsync Algo for reference](https://rsync.samba.org/tech_report/)

This was a random sideproject and i wanted to experiment with gleam, so i put some arbitrary constraints in order to attempt to make the algo very optimized (as these arbitary constraints also happen to be useful when you have a slow network and for some reason want to update your blogs in milliseconds idk)

#### Constraints: 
- 1. The chunks are streamed, so there is no look-ahead
- 2. Only one chunk should stay in memory at a time, so there is no look-back as well
- 3. Only thing we have for diffing is a list of block-hashes (which comes from the server)
- 4. Everything should occur in O(n) //In the implementation, the maximum worst case no. of iteration are 2 * N, where N is the number of characters in the file
- 5. Also this is a markdown to html host, so another constraint i have added is that there should be no redundancy for any form (this complicates the solution the most)


In the coming context, 
File A -> File on the client
File B -> File on the server
(anything + A -> on the client)
(anything + B -> on the server)


### More from RSync
- The Rsync algo splits the file A into non-overlapping fixed-sized blocks, computes a weak 32-Bit rolling checksum and a strong 128 bit MD4 hash for each block, and in the diffing algo, it basically rebuilds the file B
- This happens by scanning A and trying to find chunks which are already present on the server
- Only non-matching blocks are sent over the network, for the blocks already present, we only say "reuse the block with this hash"

The markfish algo adapts this but uses dynamically sized chunks based on markdown properties as described in the chunk parser section, the reason for this is that this is supposed to be a "markdown to html host", so we can't break chunks in between otherwise it won't be converted to html correctly

markfish uses a streaming approach so that the number of request can be reduced, and essentially serves a different purpose than rsync


## The markfish algo and the rubberbanding set

We will start by thinking about the basic operations needed to achieve sync

We only need two real operations, acting upon a state datastructure 
(which is essentially, `List(Chunks), Chunk -> {index, hash}`)

1. `Insert(index, hash)`
2. `Delete(index)`
3. (Technically 3rd i.e `DoNothing`, it is also an operation)

The input of the algo is a stream of data(Integers), and we also have a List(Int){the existing hashes on the server}

B : [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10]
A : [a1, a2, a3, a6, a5, a8, a10]

So intuitively, the we will be representing the current input block with pointer `HeadA`
and it will be incremented one-by-one

- Insert & DoNothing operations are pretty easy, if `HeadA == HeadB` then we don't need to do anything so we execute operation `DoNothing`, and if `HeadA != HeadB`, then we perform the operation `Insert(index, HeadA)`

- Deletion is the slightly difficult part, how do you determine if at the index at which we inserted headA, we needed to replace the block or will appear next?

I will go through the example for more clarity, 

HeadA, index = 0 is a1 == headB, index = 0
increment both

HeadA, index = 1 is a2 == headB, index = 1
...

HeadA, index = 3 is a6 != headB, index = 3 i.e a4

Now, now in case of a4, we could have repalced a4 (delete then insert), but in case of a5, it appears just next after a6, so deletion was not optimal, to mitigate this we somehow need to know if headB will ever appear in A or not, we cannot look ahead on A, so only option we have is to defer the decision for later..

To do that we need to move the data from List B to some other place where it is stored in order, so that they can be deleted later, 

so the lists **at index = 4** is something like: 

B -> completed: [a1, a2, a3] + defered [a4] + pending [a5, a6, a7, a8, a9, a10]

A -> completed: [a1, a2, a3, a6]            + pending [a5, a8, a9, a10]

now, 

HeadA, index = 4 is a5 == headB, index = 4

now, we can see that a5 appeared,and it matches the B array, by this we can say that, the element a4, was replaced 

if the current element were a4, then it would not have been replaced

and additionally, this means that we can say that, whenever the headB == headA, we should remove the pending elements

yep, all there is to it, 

and the current, implementation uses a rubberbanding lookup table which achieves look ahead instead of look back

This is because i got lost and didn't think about the look back approach for some reason, or most prolly i thought, and there was an edge case or something and now i have forgotten, 

anyways, rubberbanding set sounds a lot cooler, and its implemented as: 

```pseudocode
while (stream) {
  E = stream.next()

  if E in set:
    while (list.head() != E) {
      serverState.remove(index)
      set.remove(list.head())
      list = list.next()
    }
    index++

  if E not in set:
    set.extend()
    serverState.insert(index, E)
    index++
}

while (list.notEmpty()) {
  remove_elements
}
```

and the gleam implementation is something like:
```gleam
fn diff(
  new_hash: Int,
  new_context: Context,
  lookup_size: Int,
) -> #(Context, Operation) {
  let context = new_context |> refill_set(lookup_size)
  let is_present = context |> lookup_set(new_hash)
  let is_front = context |> check_queue_front(new_hash)
  case is_present, is_front {
    True, True -> #(roll_set(context), DoNothing)
    True, False -> #(shrink_set(context), Delete(context.index))
    False, _ -> #(extend_set(context), Insert(context.index, new_hash))
  }
}
```

Gleam doesn't have pointers (and doesn't need to have, because you can achieve the same thing by using a dequeue), and also the lists in gleam are linked lists, so lookups and getting the last element is really ineffitient, so the implementation is very very different from the earlier pseudocode

With this i conclude the diffing algo

This thingy prolly has a bunch of edge cases and weird behaviours ( i know weird behaviours but no edgecases), for example if a file is one big chunk then you can't do anything
But it works just fine and is pretty simple to understand and it was fun implementing this in gleam


