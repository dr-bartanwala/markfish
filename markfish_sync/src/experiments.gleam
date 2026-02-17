import file_streams/file_stream
import file_streams/text_encoding
import gleam/erlang/process.{type Subject}
import gleam/io
import internal/connection.{type Message, GetState, start_connection}
import internal/diff.{type Context, type Operation, sync}
import internal/parser.{type Chunk, parse_chunk}
import internal/scanner.{
  type CommonInfo, type ScannerMessage, CommonInfo, Scan, get_scanner,
}

fn sync_loop(stream, context: Context, server_addr) {
  let #(chunk, break) = parse_chunk(stream)

  let handle_operation = create_handle_operation(server_addr, chunk)

  let new_context = sync(False, chunk.chunk_hash, context, handle_operation)

  case break {
    True -> {
      sync(True, chunk.chunk_hash, new_context, handle_operation)
    }

    False -> sync_loop(stream, new_context, server_addr)
  }
}

fn create_handle_operation(
  server_addr: Subject(Message),
  chunk: Chunk,
) -> fn(Operation) -> Nil {
  fn(op: Operation) {
    case op {
      diff.Insert(index, value) -> {
        process.send(
          server_addr,
          connection.Insert(index, value, chunk.chunk_data),
        )
      }

      diff.Delete(index) -> {
        process.send(server_addr, connection.Delete(index))
      }

      _ -> Nil
    }
  }
}

fn syncfile(file_name: String, server_addr: Subject(Message)) {
  let encoding = text_encoding.Unicode
  let assert Ok(stream) = file_stream.open_read_text(file_name, encoding)
  let existing_state = process.call(server_addr, 10_000, GetState)
  sync_loop(stream, diff.get_new_context(existing_state), server_addr)
}

fn run_test() {
  let base_dir = "./test/sample/"
  let suite = "test_suite.md"

  let modified_suite = "test_suite_modified.md"

  let server_addr = "http://localhost:8000"
  let config =
    connection.ConnectionConfig(suite, server_addr, "default", "default")

  let scanner =
    get_scanner(CommonInfo(base_dir, "default", "default", server_addr))

  process.send(scanner, Scan)
  process.sleep_forever()
}

pub fn execute() -> Nil {
  run_test()
  io.println("completed")
  process.sleep_forever()
}
