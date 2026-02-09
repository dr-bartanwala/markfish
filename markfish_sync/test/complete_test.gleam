import file_streams/file_stream
import file_streams/text_encoding
import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/set.{type Set}
import internal/diff.{type Context, type Operation, sync}
import internal/parser.{type Chunk, parse_chunk}
import internal/test_server.{type Message, GetState, start_connection}

import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

fn sync_loop(stream, context: Context, server_addr) {
  let #(chunk, break) = parse_chunk(stream)

  let handle_operation = create_handle_operation(server_addr, chunk)

  case sync(break, chunk.chunk_hash, context, handle_operation) {
    new_context if !break -> sync_loop(stream, new_context, server_addr)
    _ -> Nil
  }
}

fn create_handle_operation(
  server_addr: Subject(Message),
  chunk: Chunk,
) -> fn(Operation) -> Nil {
  fn(op: Operation) {
    case op {
      diff.Insert(index, value) ->
        process.send(
          server_addr,
          test_server.Insert(index, value, chunk.chunk_data),
        )

      diff.Delete(index) -> process.send(server_addr, test_server.Delete(index))

      _ -> Nil
    }
  }
}

fn syncfile(file_name: String, server_addr: Subject(Message)) {
  let encoding = text_encoding.Unicode
  let assert Ok(stream) = file_stream.open_read_text(file_name, encoding)

  let existing_state = process.call(server_addr, 10, GetState)

  sync_loop(stream, diff.get_new_context(existing_state.0), server_addr)
}

fn execute_test(file, modified_file) {
  //sync processA, modify with modified state
  //sync processB with modified data
  //compare the state
  let subject = start_connection([], [])
  syncfile(file, subject)
  syncfile(modified_file, subject)
  let modified = process.call(subject, 10, GetState)

  let subject2 = start_connection([], [])
  syncfile(modified_file, subject2)
  let new_modified = process.call(subject2, 10, GetState)
  assert new_modified == modified
}

pub fn markdown_suite_test() {
  let suite = "./test/sample/test_suite.md"
  let modified_suite = "./test/sample/test_suite_modified.md"
  execute_test(suite, modified_suite)
}
