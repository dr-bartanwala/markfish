# Markfish Chunking Algo 

Markfish is basically a sync server, and uses mork (gleam library) as markdown to html converter, 

As mentioned in the project description, i am trying to minimize the number and size of the requests as much as possible, in case of [rsync](https://rsync.samba.org/), it is meant to be used for onetime sync, and uses a custom protocol, and in my case i am trying to not rebuild the file from scratch (read the attached link to rsync implementation for further context),

Now, markdown has a great property where you can divide then document into chunks based on blocks, 
i.e Paragraphs, CodeBlocks, Lists etc etc

So the markfish's parser divides the document into multiple chunks, which are dynamic but deterministic, and calculates a hash while processing these blocks


### Chunk Creation

These are the basic parts of the chunking algo
```gleam
type ChunkType {
  New
  Paragraph
  Quote
  Code1
  Code2
  List
}

type LineStyle {
  None
  EmptyLine
  ParagraphLine
  QuoteLine
  Code1Line
  Code1OnlyLine
  Code2Line
  Code2OnlyLine
  HeadingLine
  ListLine
  ThematicBreakLine
}

type ExitType {
  Continue
  ExitInclude
  ExitSkip
}
```

ChunkType is well, chunk type, we need this because for different chunk types we have to process new lines differently, 
For example: 
----
1. HELLO THIS IS A LIST
2. HELLO THIS IS ALSO A LIST
    - Hello this is the sub-list
    - another sublist






    - also a sublist even when there were spaces in between
3. STILL A LIST
```
code block
```
4. NOW ITS NOT THE SAME LIST !!

----

So we need to take care of all these edge cases, i have implemented all these, but still haven't passed it through commonmark tests (it will fail)

Currently markfish can't handle all properties of links, for example if you do: 

[Link1](link)


[link](this is the link)
----

The parser's code is pretty self-explainatory so i don't think i will repeat all the nuances here
