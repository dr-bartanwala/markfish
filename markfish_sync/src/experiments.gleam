// we will be experimenting by implementing a emitter and a reciever as experimental modules emitter
//   read a markdown file -> convert it into blocks
//   create a block hashed structure
//   structure:
//   //exactly the same as the mork
//   //but data replaced by block = [old_block_data, simple checksum] for each block
//links -> List<Link, link_hash, List<block_hash>>
//   
//   then it will recieve from the client
//   list of block_hashes
//   link_hash, List<link_hashes>
//
//

// hashing algori
import file_streams/file_stream
import file_streams/text_encoding
import gleam/io
import gleam/list
import gleam/string
import internal/parser.{type Chunk, chunkify}
import simplifile

pub fn execute() -> Nil {
  let filename = "./sample/test_suite.md"
  let assert Ok(file) = simplifile.read(filename)
  io.println(file)
  let encoding = text_encoding.Unicode

  let assert Ok(stream) = file_stream.open_read_text(filename, encoding)

  let chunks = chunkify(stream)

  io.println("Chunkify Output")
  list.each(chunks, fn(chunk: Chunk) {
    io.println("////////////Chunk Start//////////")
    io.println(chunk.chunk_hash |> string.inspect)
    list.each(chunk.chunk_data, fn(line: String) { io.print(line) })
    io.println("////////////Chunk End////////////")
  })
}
