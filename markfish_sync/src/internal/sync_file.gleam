import file_streams/file_stream
import file_streams/text_encoding
import gleam/erlang/process.{type Subject}
import internal/connection.{type Message, GetState}
import internal/diff.{type Context, type Operation, sync}
import internal/parser.{type Chunk, parse_chunk}

fn sync_loop(stream, context: Context, connection) -> Bool {
  let #(chunk, break) = parse_chunk(stream)

  let handle_operation = create_handle_operation(connection, chunk)

  let new_context = sync(False, chunk.chunk_hash, context, handle_operation)

  case break {
    True -> {
      sync(True, chunk.chunk_hash, new_context, handle_operation).debug_info.required_sync
    }

    False -> sync_loop(stream, new_context, connection)
  }
}

fn create_handle_operation(
  connection: Subject(Message),
  chunk: Chunk,
) -> fn(Operation) -> Nil {
  fn(op: Operation) {
    case op {
      diff.Insert(index, value) -> {
        process.send(
          connection,
          connection.Insert(index, value, chunk.chunk_data),
        )
      }

      diff.Delete(index) -> {
        process.send(connection, connection.Delete(index))
      }

      _ -> Nil
    }
  }
}

//expects a full filename
pub fn syncfile(file_name: String, connection: Subject(Message)) -> Bool {
  let encoding = text_encoding.Unicode
  let assert Ok(stream) = file_stream.open_read_text(file_name, encoding)
  let existing_state = process.call(connection, 10_000, GetState)
  sync_loop(stream, diff.get_new_context(existing_state), connection)
}
