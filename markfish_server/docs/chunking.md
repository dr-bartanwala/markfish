# Markfish Chunking Algo

Markfish is basically a sync server, and uses [mork](https://github.com) (gleam library) as markdown to html converter. As mentioned in the project description, I am trying to minimize the number and size of the requests as much as possible.

In the case of [rsync](https://rsync.samba.org/), it is meant to be used for one-time sync and uses a custom protocol. In my case I am trying to not rebuild the file from scratch *(read the attached link to rsync implementation for further context)*. Now, markdown has a great property where you can divide the document into chunks based on blocks — i.e. Paragraphs, CodeBlocks, Lists etc.

So the markfish's parser divides the document into multiple chunks, which are **dynamic in size**, and calculates a hash while processing these blocks.

---

## Chunk Creation

These are the basic parts of the chunking algo:

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

`ChunkType` is well, chunk type. We need this because for different chunk types we have to process new lines differently.

For example:

---

```
1. HELLO THIS IS A LIST
2. HELLO THIS IS ALSO A LIST
   - Hello this is the sub-list
   - another sublist
   - also a sublist
   even when there were spaces in between
3. STILL A LIST
   ``` code block is seperate type of chunk```
4. NOW ITS NOT THE SAME LIST !!
```

---

So we need to take care of all these cases. I have implemented all these, but still haven't passed it through commonmark tests *(it will fail)* i think markfish covers most cases well enough.

---

## Known Limitations

Currently markfish can't handle all properties of links. For example, if you try **labelled links**:

```markdown
[Link1][link]

[link]: https://dr.bartanwala.wtf/kitchen/home
```

The parser's code is pretty self-explanatory so I don't think I will be repeating all the nuances here.