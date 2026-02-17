## Hashing Algo for markfish

Markfish scans the files character by character, 
Max operations taken for scanning a line is 2*n, where n is the no of characters before eol
A rolling FNV hash is used for every character, and the final hash is used for syncing

Current implementation doesn't have a stronger hash for collision checks, if collisions are a problem, another rolling hash with a different profile can be used, which will reduce the collisions further


### FNV-a1
- [WikiPedia Article](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function)
 
