# Rough Development Notes
5/2/26
-> Covered up the parser
-> Implemented the rolling FNV hash

From a architecture POV, 

Actors:
FileMan -> Executes Create/Delete operation on files it doesn't concern itself with the index
Server  -> Recieves Post request with -> [BlockHash, Add/Remove, Index/Nil(delete doesnt require indexes] //we can figureout the request structure later 
-> FileMan.send(Operation, FileName, Content)
-> Also sends, ContextMan.send(Operation, FileName) -> contextMan doesn't concern itself with the  data,
-> ContextMan modifies the internal state
ContextMan -> Stores and context i.e the blockHashes and their order
ReadMan -> Short lived process only meant to iterate when user request, supposed to be completed in milliseconds

BlockA,
BlockB, 
BlockC, 
BlockD, 
...

Note: Now, read and write ever block each other, and there is only read, append, and delete, so there is no chance that a block changes when the process was reading it

Diffing Algo: 

Server State: List[] //remaining elements (while diff is being calculated), initially complete

Remaining: Dict of List[]

Index = 0
actors:
FileMan -> Executes Create/Delete operation on files it doesn't concern itself with the index
Server  -> Recieves Post request with -> [BlockHash, Add/Remove, Index/Nil(delete doesnt require indexes] //we can figureout the request structure later 
-> FileMan.send(Operation, FileName, Content)
-> Also sends, ContextMan.send(Operation, FileName) -> contextMan doesn't concern itself with the  data,
-> ContextMan modifies the internal state
ContextMan -> Stores and context i.e the blockHashes and their order
ReadMan -> Short lived process only meant to iterate when user request, supposed to be completed in milliseconds

BlockA,
BlockB, 
BlockC, 
BlockD, 
...

Note: Now, read and write ever block each other, and there is only read, append, and delete, so there is no chance that a block changes when the process was reading it


Context: 
- This should support two operations, insert & delete
- These will be always performed based on indexes and not blockhashes
- BlockHashes will only be used for searching
- The ContextMan will take in 
- Dict(index, BlockHash)
- 
- List(blockHashes) ~maintains the order
- Requests: 
- GetState -> used by the ReadMan for giving the file reading order
- UpdateState(operation, new_data)

//ContextMan is responsible for syncing FileMan and ReadMan asin, 
-> ContextMan will take in requests like, 

server -> get request -> 
{ returns html chunks one by one by initiating a ReadMan(for each request), and providing it with a structure provided by ContextMan)

ReadMan -> Iterates and calls FileMan to provide the required chunks -> this will be done by indexes
        -> Streams these chunks back to the Server


                                                                      
while(stream){
    E = stream.next
    if NextNElementsDict has E:
        //basically removing all elements in between, as they don't appear
        //if just next element is E, then the count will be zero, and no element will be removed / added
        //if lets say the server state was: A B C D
        //new state is :                  : A M L O C D

        //if lets say the server state was: A B C D
        //new state is :                  : D A B C 
        //when reacing C (in new state), the list will be: 
        //with us: B C D
        //state on the server: A [M] [L] [O] B C D
        //state on the client: A [M] [L] [O] C <- new element
        //thus B, will be deleted, with the operation (
           relative count:
           while(List.head != E){
            server.delete(List.head, Index)
            List = List.head()
           }
           Index++ //no need to send
    else
    //this means that this block is entirely new and doesn't match the current pointer
    server.append(E, index)
    Index++
    (This Index is after the last element)
    //after the stream completes, remote the tail elements
    while(list.empty){
        server.delete(List.head, Index)
    }
}
-> an interesting property of this algo, is that, if lets say, size of dict is limited, and it can't find a the element, 
all the elements will just be pushed back technically, and will get pruned in the final operation

-> but this will prevent the delete optimization we are trying to perform, 
-> so we need a way to make the current Dict Stale, 

-> A B C D F
-> D O P Q F 
it will prevent the A, B, C's unncessary removal
-> but lets say, 

lets say, dict window is, 5 elements, 


improvised algo:

//these are basically hashes, in Int
stream = G P O Q M B C R S T U V
copy_of_serverState = [A B C D E F G R S T U V]

actual_serverState = [A B C D E F G R S T U V]

index = 0
dict[]

while(stream){
    E = stream.next
    if E in rollingDict:
        while(list.head() != E){
            serverState.remove(Index)
            set.remove(list.head())
            list = list.next()
        }
        index++
    if E not in Dict:
        Dict.extend()
        serverState.insert(Index, E)
        index++
}
while(list.notempty){
    remove_elements
}


Context: 
- This should support two operations, insert & delete
- These will be always performed based on indexes and not blockhashes
- BlockHashes will only be used for searching
- The ContextMan will take in 
- Dict(index, BlockHash)
- 
- List(blockHashes) ~maintains the order
- Requests: 
- GetState -> used by the ReadMan for giving the file reading order
- UpdateState(operation, new_data)

//ContextMan is responsible for syncing FileMan and ReadMan asin, 
-> ContextMan will take in requests like, 

server -> get request -> 
{ returns html chunks one by one by initiating a ReadMan(for each request), and providing it with a structure provided by ContextMan)

ReadMan -> Iterates and calls FileMan to provide the required chunks -> this will be done by indexes
        -> Streams these chunks back to the Server








4/2/26

-> 
Types of possible blocks: 

Paragraph 


-> The parser will divide the markdown into blocks, 
these blocks include things like a simple new line character, to a bulleted list
therefore, new line is simply newline, [1 character], no hashing  needed, 
also, if we use stuff like FNV-1 hash, it just requires a single iteration, therefore is faster than sending the entire chunk


hashing would be a simple checksum, 

instead found something as Fowler-Noll-Vo hash function, hash based on the size of the string, so will take only a small time for parsing small blocks, 

now i am thinking that instead of using mork's types, i'll just implement new types myself, 

just ignore the newline character

no need to store the file as a parsed data structure, just iterate through it line by line

-> simple parsing

line starting with > {quote}
-> then parse till you find a line without the first character as tab or the previous character, dealing with tabs is a different thing altogether

if paragraph -> blankline -> paragraph, seperate them into, [paragraph+blankline] + paragraph

balance between block size and block count will be required

also, the server doesn't need to send state each time, 
assuming server is non-mutable for short periods, we can avoid having to fetch server state,server follows the client's operations blindly

we can maintain a ping timer, to show that 

we also need to maintain chunk relationships, if we are considering urls


3/2/26
Dividing into chunks might be a difficult process, 
i am thinking of relying on the mork lib's data types + a modification to store the data

on the initial sync, 

// rsync like implementation for syncing blocks
server;
shares the DocumentHash on the server to the client, 
the documenthash will contain the hash of each block and the hash of other parts of the document
client;
after recieving the hash, 
will iterate through all blocks, 
and maintain a list for now (can be modified to streaming, similar to rsync)
if similarity found, will add a blockhash

i was thinking of going based on a append / remove approach, 

will send the list of append blocks, and remove blocks

after iterating, we have a sequential list of blocks

server: A B C D E F G

client: A C D E M F G

the message will be sent to the server:

append: (stack)
- M(index)

remove (stack)
- B

serverside: 

iterate through all the blocks:

if remove block encountered:
- remove lines owned by the block
- relative_index++
- remove.pop()

if index == relative_index + append[0].index
-> add the appended block, move to next
-> (the indexes of the append blocks were created based on A itself, so we don't need to increment anything)

three operations,

remove
replace
append

so for the  A B C D E F G


and modified    A X C Y D E F Z
        index   0 1 2 3 4 5 6 7

append stack: 
        (X, 1)
        (Y, 3)
        (Z, 7)


remove stack:
        (B)
        (G)

starting the algo

index = 0; relative_index = 0;

case checkOperation(){
        replace: 
                remove the current, block replace it with new
        remove:
                remove the current
        append:
                add the new block at the index
}


pointer movement for each operation

we will be maintinaing a pointer for moving through the lines in html file

for each markdown block, we have a corresponding size,

when iterating through the markdown we maintain a block index
on every increment, 
blockindex++
htmlindex += block.size

on replace: 
        we perform operations, 
        -> remove line operation * previous block.size()
        //if we use a static html this is required
        if the html is being streamed, directly blocks can be replaced/removed/appended
        without needing a complete html file, for the optimizations for the network we have done, this would be a better thing to do 
        on replace: 
                we perform operations, 
                -> remove line operation * previous block.size()

replace:








2/2/26
So starting with basic server setup, 
the server will be handling two tasks, 

1. sync: getting the markdown file chunks from the client, and modifying the html files accordingly

sync request: (documentID (document name), 
2. 


31/1/26
### Initial Ideation
- The idea behing markfish is to create a simple sync service to host my blogs
- this is mostly intended as a personal project to sync to my webserver directly(more like a excuse to learn gleam)


Project Structuring what i have in mind
- Project
-   /src 
-       /markfish.gleam -> just introduction, and ASCII shenanigans, will point to server.gleam
        /server.gleam   -> will handle, routing, starting the server, calling the generator
        /generator -> will fetch the files from the file system, and call the colorizer on them
        /colorizer  -> will take in a plain html, and add CSS by reading a theme config
        /sync -> will be responsible for either maintaining the sync with the file system or with the obsidian client
        -> will be handling authenticated post requests from the client

    /theme.lua -> contains themes for html (need to search if there exists an already implemented theme system somewhere)
    /config.lua -> contains the directory roots

Architechture
- Read markdown files from a given folder or operate in sync mode with obsidian 
- Generate a html store, which will be read by the server and presented
- Have a basic index file indended for routing users 
- The index file will be created by the sync / read utility
- maybe add a sort / search functionality
- keep it in simple readable html

- generator
- this will read the markdown files provided in the route, and return a formatted html response
- can add a simple theme support with lua
- server will return the html files
- exteremely simple and basic

Authentication: 
- [client] -> shares encrypted diffs signed by the private key -> recieved encrypted diffs and checks signature

method -> create a strong password, put it in the obsidian plugin as well as server config
basically the server will generate a URI which needs to be kept safe
