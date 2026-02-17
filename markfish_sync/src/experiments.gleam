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
import gleam/deque.{type Deque}
import gleam/io
import gleam/list
import gleam/set.{type Set}
import gleam/string
import internal/parser.{type Chunk, chunkify}
import mork
import simplifile

fn convert_to_html(chunks: List(Chunk), acc: String) -> String {
  case chunks {
    [chunk, ..rest] -> {
      { acc <> { chunk.chunk_data |> mork.parse |> mork.to_html } }
      |> convert_to_html(rest, _)
    }
    [] -> acc
  }
}

const lookup_size = 5

type Context {
  Context(
    index: Int,
    pending: List(Int),
    lookup: Set(Int),
    lookup_elements: Deque(Int),
  )
}

type Operation {
  DoNothing
  Delete(index: Int)
  Insert(index: Int, value: Int)
}

fn refill_set(context: Context) -> Context {
  case context.pending {
    [new, ..rest] -> {
      case context.lookup |> set.size < lookup_size {
        True -> {
          Context(
            context.index,
            rest,
            context.lookup |> set.insert(new),
            context.lookup_elements |> deque.push_back(new),
          )
          |> refill_set
        }
        False -> context
      }
    }
    [] -> context
  }
}

fn check_queue_front(context: Context, element: Int) -> Bool {
  case context.lookup_elements |> deque.pop_front {
    Ok(#(front, _)) -> element == front
    _ -> False
  }
}

fn lookup_set(context: Context, element: Int) -> Bool {
  context.lookup |> set.contains(element)
}

fn roll_set(context: Context) -> Context {
  let #(lookup_minus_front, rest_of_lookup_elements) = case
    context.lookup_elements |> deque.pop_front
  {
    Ok(#(front, rest)) -> #(context.lookup |> set.delete(front), rest)
    _ -> #(context.lookup, context.lookup_elements)
  }

  let #(lookup, lookup_elements, rest_of_pending) = case context.pending {
    [curr, ..rest] -> #(
      lookup_minus_front |> set.insert(curr),
      rest_of_lookup_elements |> deque.push_back(curr),
      rest,
    )
    [] -> #(lookup_minus_front, rest_of_lookup_elements, [])
  }

  Context(context.index + 1, rest_of_pending, lookup, lookup_elements)
}

fn extend_set(context: Context) -> Context {
  let #(lookup, rest_of_pending, lookup_elements) = case context.pending {
    [curr, ..rest] -> #(
      context.lookup |> set.insert(curr),
      rest,
      context.lookup_elements |> deque.push_back(curr),
    )

    _ -> #(context.lookup, [], context.lookup_elements)
  }
  Context(context.index + 1, rest_of_pending, lookup, lookup_elements)
  |> refill_set
}

fn shrink_set(context: Context) -> Context {
  let #(lookup_minus_front, rest_of_lookup_elements) = case
    context.lookup_elements |> deque.pop_front
  {
    Ok(#(front, rest)) -> #(context.lookup |> set.delete(front), rest)
    _ -> #(context.lookup, context.lookup_elements)
  }

  Context(
    context.index,
    context.pending,
    lookup_minus_front,
    rest_of_lookup_elements,
  )
  |> refill_set
}

fn diff(new_hash: Int, context: Context) -> #(Context, Operation) {
  io.println("Executing diff")
  echo new_hash
  case context |> lookup_set(new_hash) {
    True ->
      case context |> check_queue_front(new_hash) {
        True -> {
          echo "rolling set"
          #(roll_set(context), DoNothing)
        }
        False -> {
          echo "shrinking set"
          #(shrink_set(context), Delete(context.index))
        }
      }

    False -> {
      echo "extending_set"
      #(extend_set(context), Insert(context.index, new_hash))
    }
  }
}

fn run_algo_loop(
  new_hashes: List(Int),
  context: Context,
  acc: List(Operation),
) -> #(Context, List(Operation)) {
  case new_hashes {
    [new_hash, ..rest] -> {
      let #(new_context, op) = diff(new_hash, context)
      case op {
        Delete(_) -> run_algo_loop(new_hashes, new_context, [op, ..acc])
        _ -> run_algo_loop(rest, new_context, [op, ..acc])
      }
    }
    [] -> #(context, acc |> list.reverse)
  }
}

fn run_algo(hashes, new_hashes) -> #(Context, List(Operation)) {
  let context = Context(0, hashes, set.new(), deque.new()) |> refill_set
  run_algo_loop(new_hashes, context, [])
}

pub fn execute() -> Nil {
  let _filename = "./sample/test_suite.md"
  let hashes = [5, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 10, 10, 145]
  let new_hashes = [1, 2, 3, 5, 8, 10, 15, 11, 19, 12, 145, 10, 120, 10, 12]
  let generated_hashes = run_algo(hashes, new_hashes)
  echo hashes
  echo new_hashes
  echo generated_hashes.1
  io.println("terminated")
  //let encoding = text_encoding.Unicode
  //let assert Ok(stream) = file_stream.open_read_text(filename, encoding)
}
