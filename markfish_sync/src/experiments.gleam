import file_streams/file_stream
import file_streams/text_encoding
import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/set.{type Set}
import internal/connection.{type Message, GetState, start_connection}
import internal/diff.{type Context, type Operation, sync}
import internal/parser.{type Chunk, parse_chunk}

fn run_test() {
  todo
}

pub fn execute() -> Nil {
  run_test()
  io.println("completed")
}
